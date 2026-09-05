import Foundation
import Darwin

final class SessionHost {
    private let paths: SessionPaths
    private let config: HostConfiguration
    private let backend: SessionBackend
    private let observations: ObservationCache
    private let control = DispatchQueue(label: "agentsoma.host.control")
    private let work = DispatchQueue(label: "agentsoma.host.device")
    private let done = DispatchSemaphore(value: 0)
    private var lifecycle: SessionLifecycle
    private var server: JSONServer?
    private var timer: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    private var backendInfo: [String: Any] = [:]

    init(config: HostConfiguration, paths: SessionPaths, backend: SessionBackend) {
        self.config = config
        self.paths = paths
        self.backend = backend
        observations = ObservationCache(directory: paths.directory)
        lifecycle = SessionLifecycle(timeout: config.idleTimeoutSeconds)
    }

    func run() throws {
        do {
            let server = try JSONServer(path: paths.socket)
            self.server = server
            server.onRequest = { [self] request, reply in control.async { self.receive(request, reply: reply) } }
            server.onFailure = { [self] error in
                control.async { self.close(reason: "ipc_failed: \(error)") }
            }
            for number in [SIGTERM, SIGINT] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: control)
                source.setEventHandler { [self] in close(reason: "signal") }
                source.resume()
                signals.append(source)
            }
            server.start { [self] in
                control.async {
                    guard self.lifecycle.phase == .starting else { return }
                    self.work.async {
                        do {
                            let info = try self.backend.start()
                            self.control.async {
                                self.backendInfo = info
                                guard self.lifecycle.phase == .starting else { return }
                                self.lifecycle.ready(at: ProcessInfo.processInfo.systemUptime)
                                let timer = DispatchSource.makeTimerSource(queue: self.control)
                                timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
                                timer.setEventHandler { [self] in
                                    if lifecycle.isExpired(at: ProcessInfo.processInfo.systemUptime) { close(reason: "idle_timeout") }
                                }
                                timer.resume()
                                self.timer = timer
                            }
                        } catch {
                            try? saveJSON(["code": (error as? SomaError)?.code ?? "host_start_failed",
                                           "message": String(describing: error)],
                                          to: self.paths.directory.appendingPathComponent("startup-error.json"))
                            self.control.async { self.close(reason: "startup_failed") }
                        }
                    }
                }
            }
            done.wait()
            timer?.cancel()
            signals.forEach { $0.cancel() }
            try? FileManager.default.removeItem(atPath: paths.socket)
        } catch { _ = backend.stop(); throw error }
    }

    private func receive(_ request: [String: Any], reply: @escaping JSONServer.Reply) {
        let id = request["id"] as? String ?? ""
        let operation = request["op"] as? String ?? ""
        func reject(_ code: String, _ message: String) {
            reply(["id": id, "session": config.session, "ok": false,
                   "outcome": "not_dispatched", "error": ["code": code, "message": message]], {})
        }
        guard request["version"] as? Int == 1, request["session"] as? String == config.session,
              !id.isEmpty, ["status", "open", "observe", "inspect", "disconnect"].contains(operation) else {
            reject("invalid_request", "Invalid session request")
            return
        }
        if operation == "open" {
            guard let bundle = request["bundleId"] as? String, !bundle.isEmpty, bundle.utf8.count <= 255 else {
                reject("invalid_bundle_id", "A bundle identifier is required")
                return
            }
        }
        var reference: ObservationReference?
        if operation == "inspect" {
            do {
                reference = try ObservationReference(request["reference"] as? String ?? "")
                guard let offset = request["offset"] as? Int, offset >= 0 else {
                    throw SomaError("invalid_offset", "A nonnegative offset is required")
                }
            } catch {
                reject((error as? SomaError)?.code ?? "invalid_reference", String(describing: error))
                return
            }
        }
        guard lifecycle.accept(at: ProcessInfo.processInfo.systemUptime) else {
            reject("session_closed", "Session has expired or is closing; connect again")
            if lifecycle.isExpired(at: ProcessInfo.processInfo.systemUptime) { close(reason: "idle_timeout") }
            return
        }
        if operation == "disconnect" {
            close(reason: "disconnect", requestID: id, reply: reply)
            return
        }
        work.async { [self] in
            var response: [String: Any] = ["id": id, "session": config.session, "ok": true]
            var previousObservation: String?
            var effective = operation == "open"
            do {
                switch operation {
                case "status": response["result"] = try backend.status()
                case "open":
                    previousObservation = observations.beginAction()
                    response["result"] = try backend.open(bundle: request["bundleId"] as! String)
                    observations.finishAction(previous: previousObservation, dispatched: true)
                    response["outcome"] = "completed"
                case "observe":
                    observations.invalidate("superseded")
                    response["result"] = try observations.store(backend.observe())
                    effective = true
                case "inspect":
                    response["result"] = try observations.inspect(reference!, offset: request["offset"] as! Int)
                    effective = true
                default: break
                }
            } catch {
                response["ok"] = false
                let uncertain = (error as? TransportError)?.possiblySent ?? false
                if operation == "open" {
                    observations.finishAction(previous: previousObservation, dispatched: uncertain)
                    response["outcome"] = uncertain ? "unknown" : "not_dispatched"
                }
                if operation == "status" { observations.invalidate("backend_unavailable") }
                response["error"] = ["code": (error as? SomaError)?.code ?? "backend_error", "message": String(describing: error)]
            }
            // The control queue serializes command admission against expiry and completion.
            control.sync {
                lifecycle.finish(effective: effective, at: ProcessInfo.processInfo.systemUptime)
                if operation == "status" {
                    response["hostPid"] = ProcessInfo.processInfo.processIdentifier
                    response["idleTimeoutSeconds"] = config.idleTimeoutSeconds
                    response["idleRemainingSeconds"] = max(0, config.idleTimeoutSeconds - (ProcessInfo.processInfo.systemUptime - lifecycle.lastActivity))
                }
                reply(response, {})
            }
        }
    }

    private func close(reason: String, requestID: String? = nil, reply: JSONServer.Reply? = nil) {
        guard lifecycle.phase != .closing else { return }
        lifecycle.close()
        timer?.cancel()
        server?.stopAccepting()
        // Already admitted work finishes first on this same serial queue.
        work.async { [self] in
            var cleanup = backend.stop()
            do { try observations.clear(); cleanup["observationCacheRemoved"] = true }
            catch { cleanup["observationCacheRemoved"] = false; cleanup["cacheError"] = String(describing: error) }
            let clean = cleanup["xcodebuildExited"] as? Bool == true && cleanup["forced"] as? Bool != true
                && cleanup["shutdownAcknowledged"] as? Bool == true && cleanup["xcodebuildExitCode"] as? Int == 0
                && cleanup["observationCacheRemoved"] as? Bool == true
            let result: [String: Any] = ["session": config.session, "reason": reason,
                "hostPid": ProcessInfo.processInfo.processIdentifier, "backend": backendInfo,
                "cleanup": cleanup, "endedAt": Date().timeIntervalSince1970]
            try? saveJSON(result, to: paths.exit)
            if let reply, let requestID {
                reply(["id": requestID, "session": config.session, "ok": clean, "result": result], { self.done.signal() })
            } else { done.signal() }
        }
    }
}

public func runHost(directory: URL) throws {
    umask(0o077)
    setsid()
    let paths = SessionPaths(directory: directory)
    do {
        try SessionPaths.secureDirectory(directory)
        let config = try JSONDecoder().decode(HostConfiguration.self, from: Data(contentsOf: paths.config))
        let host = SessionHost(config: config, paths: paths, backend: XCTestBackend(config: config, paths: paths))
        try host.run()
    } catch {
        try? saveJSON(["code": (error as? SomaError)?.code ?? "host_start_failed", "message": String(describing: error)],
                      to: directory.appendingPathComponent("startup-error.json"))
        throw error
    }
}
