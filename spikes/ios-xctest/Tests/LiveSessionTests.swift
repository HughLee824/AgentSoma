import Network
import XCTest

private struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private final class CommandServer {
    struct Request {
        let body: [String: Any]
        let connection: NWConnection
    }

    let requests: AsyncStream<Request>
    private let continuation: AsyncStream<Request>.Continuation
    private let listener: NWListener
    private let queue = DispatchQueue(label: "agentsoma.commands")
    private var connections: [NWConnection] = []

    init() throws {
        var sink: AsyncStream<Request>.Continuation!
        requests = AsyncStream { sink = $0 }
        continuation = sink
        let parameters = NWParameters.tcp
        let host = ProcessInfo.processInfo.environment["AGENTSOMA_LISTEN_HOST"] ?? "127.0.0.1"
        guard host == "127.0.0.1" || (IPv6Address(host) != nil && host != "::") else {
            throw CommandError("invalid_listen_address")
        }
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: 47821)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { print("AGENTSOMA_LIVE_READY host=\(host) port=47821") }
            if case .failed(let error) = state {
                print("AGENTSOMA_LISTENER_FAILED \(error)")
                self?.continuation.finish()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connections.append(connection)
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                if case .cancelled = state { self?.connections.removeAll { $0 === connection } }
            }
            connection.start(queue: queue)
            receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            buffer.append(data ?? Data())
            guard buffer.count <= 65536, error == nil else { connection.cancel(); return }
            if let newline = buffer.firstIndex(of: 10) {
                guard let body = (try? JSONSerialization.jsonObject(with: buffer[..<newline])) as? [String: Any] else {
                    connection.cancel()
                    return
                }
                continuation.yield(Request(body: body, connection: connection))
            } else if done { connection.cancel() }
            else { receive(connection, buffer: buffer) }
        }
    }

    func reply(_ body: [String: Any], to request: Request) async throws {
        var data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        data.append(10)
        await withCheckedContinuation { (sent: CheckedContinuation<Void, Never>) in
            request.connection.send(content: data, completion: .contentProcessed { _ in
                request.connection.cancel()
                sent.resume()
            })
        }
    }

    func stop() {
        listener.cancel()
        continuation.finish()
        queue.async { [self] in connections.forEach { $0.cancel() } }
    }
}

final class LiveSessionTests: XCTestCase {
    private var currentApp: XCUIApplication?
    private var currentBundleID: String?
    private var commandIssues: [String] = []

    override func record(_ issue: XCTIssue) {
        commandIssues.append(issue.compactDescription)
        super.record(issue)
    }

    @MainActor
    func testCommandSession() async throws {
        guard let token = ProcessInfo.processInfo.environment["AGENTSOMA_SESSION_TOKEN"], token.count >= 32 else {
            throw XCTSkip("Start through a spike launcher to enable the bounded command session")
        }
        continueAfterFailure = true
        let server = try CommandServer()
        let sessionID = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        var sequence = 0
        var didShutdown = false
        let hostManaged = ProcessInfo.processInfo.environment["AGENTSOMA_HOST_MANAGED"] == "1"
        let expiry: Task<Void, Never>? = hostManaged ? nil : Task {
            try? await Task.sleep(nanoseconds: 900_000_000_000)
            if !Task.isCancelled { server.stop() }
        }
        defer { expiry?.cancel(); server.stop() }

        for await request in server.requests {
            sequence += 1
            commandIssues = []
            let began = ProcessInfo.processInfo.systemUptime
            let command = request.body
            var response: [String: Any] = [
                "id": command["id"] ?? NSNull(), "sessionId": sessionID,
                "runnerPid": ProcessInfo.processInfo.processIdentifier, "sequence": sequence,
                "uptimeMs": (began - started) * 1000
            ]
            var stopping = false
            do {
                guard command["token"] as? String == token else { throw CommandError("unauthorized") }
                response["result"] = try execute(command)
                if !commandIssues.isEmpty { throw CommandError(commandIssues.joined(separator: "\n")) }
                response["ok"] = true
                stopping = command["op"] as? String == "shutdown"
            } catch {
                response["ok"] = false
                response["error"] = String(describing: error)
            }
            response["runnerMs"] = (ProcessInfo.processInfo.systemUptime - began) * 1000
            try await server.reply(response, to: request)
            print("AGENTSOMA_COMMAND sequence=\(sequence) op=\(command["op"] ?? "missing") ok=\(response["ok"] ?? false)")
            if stopping { didShutdown = true; break }
        }
        XCTAssertTrue(didShutdown, "Session ended without an explicit shutdown command")
    }

    @MainActor
    private func execute(_ command: [String: Any]) throws -> [String: Any] {
        let op = command["op"] as? String ?? ""
        if op == "ping" {
            let hostManaged = ProcessInfo.processInfo.environment["AGENTSOMA_HOST_MANAGED"] == "1"
            return ["protocol": "agentsoma-spike-jsonl-v1", "lifecycleOwner": hostManaged ? "host" : "spike",
                    "lifetimeLimitSeconds": hostManaged ? NSNull() : 900, "observationVersion": 1]
        }
        if op == "shutdown" { return ["stopped": true] }
        if op == "launch" {
            let bundle = command["bundleId"] as? String ?? ""
            guard ["com.somnus.agentsoma.spike.fixture", "com.apple.calculator"].contains(bundle) else {
                throw CommandError("bundle_not_allowed_in_spike")
            }
            let app = XCUIApplication(bundleIdentifier: bundle)
            if app.state == .notRunning { app.launch() } else { app.activate() }
            guard app.state == .runningForeground else { throw CommandError("app_not_foreground") }
            currentApp = app
            currentBundleID = bundle
            return ["bundleId": bundle, "appState": app.state.rawValue]
        }
        if op == "observe" {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alerts = springboard.alerts
            let count = alerts.count
            if count == 1 {
                return observe(springboard, root: alerts.firstMatch, scope: "systemAlert")
            }
            if count == 0, let app = currentApp, app.state == .runningForeground {
                return observe(app, root: app, scope: "app")
            }
            return observe(nil, root: nil, scope: "unknown",
                           error: count > 1 ? "multiple_system_alerts" : "foreground_app_unknown")
        }
        guard var app = currentApp else { throw CommandError("launch_an_app_first") }
        let scope = command["scope"] as? String ?? "app"
        var root: XCUIElement = app
        switch scope {
        case "app":
            guard app.state == .runningForeground else { throw CommandError("app_not_foreground") }
        case "systemAlert":
            guard currentBundleID == "com.somnus.agentsoma.spike.fixture", ["observe", "tap"].contains(op) else {
                throw CommandError("system_alert_scope_not_allowed")
            }
            app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alerts = app.alerts
            guard alerts.count == 1 else { throw CommandError("system_alert_count_\(alerts.count)") }
            root = alerts.firstMatch
        default: throw CommandError("unknown_scope")
        }
        if op == "tap", let x = command["x"] as? Double, let y = command["y"] as? Double {
            guard command["identifier"] == nil, x.isFinite, y.isFinite,
                  root.frame.contains(CGPoint(x: x, y: y)) else { throw CommandError("invalid_screen_point") }
            let frame = app.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - frame.minX, dy: y - frame.minY)).tap()
            return ["coordinateSpace": "screen_points", "x": x, "y": y]
        }
        guard ["tap", "type", "swipe"].contains(op) else { throw CommandError("unknown_operation") }
        guard let identifier = command["identifier"] as? String, !identifier.isEmpty else {
            throw CommandError("identifier_required")
        }
        var elementType = XCUIElement.ElementType.any
        if let raw = command["elementType"] {
            guard let value = raw as? UInt, let type = XCUIElement.ElementType(rawValue: value) else {
                throw CommandError("invalid_element_type")
            }
            elementType = type
        }
        let matches = root.descendants(matching: elementType).matching(identifier: identifier)
        guard matches.count == 1 else { throw CommandError("element_match_count_\(matches.count)") }
        let target = matches.firstMatch
        guard target.isHittable else { throw CommandError("element_not_hittable") }
        switch op {
        case "tap": target.tap()
        case "type":
            guard let text = command["text"] as? String, text.count <= 1024 else { throw CommandError("invalid_text") }
            target.tap()
            target.typeText(text)
        case "swipe":
            switch command["direction"] as? String {
            case "up": target.swipeUp()
            case "down": target.swipeDown()
            default: throw CommandError("direction_must_be_up_or_down")
            }
        default: break
        }
        return ["identifier": identifier]
    }

    @MainActor
    private func observe(_ app: XCUIApplication?, root: XCUIElement?, scope: String, error: String? = nil) -> [String: Any] {
        let snapshotTime = Date().timeIntervalSince1970
        var nodes: [[String: Any]] = []
        var truncated = false
        var axError = error
        func visit(_ node: XCUIElementSnapshot, parent: Int?) {
            guard nodes.count < 200 else { truncated = true; return }
            let index = nodes.count
            let frame = node.frame
            nodes.append([
                "index": index, "parent": parent.map { $0 as Any } ?? NSNull(),
                "type": node.elementType.rawValue, "identifier": node.identifier,
                "label": node.label, "value": node.value ?? NSNull(), "enabled": node.isEnabled,
                "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            ])
            node.children.forEach { visit($0, parent: index) }
        }
        if let root {
            do { visit(try root.snapshot(), parent: nil) }
            catch { axError = String(describing: error) }
        }
        let snapshotFinished = Date().timeIntervalSince1970
        let screenshot = XCUIScreen.main.screenshot()
        let frame = app?.frame
        return [
            "bundleId": scope == "systemAlert" ? "com.apple.springboard" : (scope == "app" ? currentBundleID as Any? ?? NSNull() : NSNull()),
            "targetBundleId": currentBundleID as Any? ?? NSNull(), "scope": scope,
            "foregroundBundleId": scope == "app" ? currentBundleID as Any? ?? NSNull() : NSNull(),
            "appState": app.map { $0.state.rawValue as Any } ?? NSNull(),
            "screenFrame": frame.map { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] as Any } ?? NSNull(),
            "coordinateSpace": "screen_points", "nodes": nodes, "truncated": truncated,
            "axStatus": nodes.isEmpty ? "unavailable" : "available", "axError": axError as Any? ?? NSNull(),
            "snapshotStartedAt": snapshotTime, "snapshotFinishedAt": snapshotFinished,
            "screenshotCapturedAt": Date().timeIntervalSince1970,
            "screenshotWidth": screenshot.image.size.width * screenshot.image.scale,
            "screenshotHeight": screenshot.image.size.height * screenshot.image.scale,
            "screenshotBase64": screenshot.pngRepresentation.base64EncodedString()
        ]
    }
}
