import Foundation
import Network
import Darwin

// The host depends on these few operations, not XCTest objects or an agent-facing Runner protocol.
protocol SessionBackend: AnyObject {
    func start() throws -> [String: Any]
    func status() throws -> [String: Any]
    func open(bundle: String) throws -> [String: Any]
    func observe() throws -> CapturedObservation
    func stop() -> [String: Any]
}

final class XCTestBackend: SessionBackend {
    private let config: HostConfiguration
    private let paths: SessionPaths
    private var process: Process?
    private var log: FileHandle?
    private var deviceLock: DeviceLock?
    private var endpoint: NWEndpoint?
    private let token = UUID().uuidString + UUID().uuidString
    private var identity: String?
    private var runnerPID: Int?

    init(config: HostConfiguration, paths: SessionPaths) {
        self.config = config
        self.paths = paths
    }

    func start() throws -> [String: Any] {
        let logURL = paths.directory.appendingPathComponent("xcodebuild.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        log = try FileHandle(forWritingTo: logURL)
        let details = try deviceInfo("details")
        guard let hardware = details["hardwareProperties"] as? [String: Any],
              let udid = hardware["udid"] as? String,
              let connection = details["connectionProperties"] as? [String: Any],
              let address = connection["tunnelIPAddress"] as? String,
              IPv6Address(address) != nil, address != "::" else {
            throw SomaError("coredevice_unavailable", "No native CoreDevice IPv6 address; see \(logURL.path)")
        }
        deviceLock = try DeviceLock(root: paths.directory.deletingLastPathComponent(), device: udid)
        let lockState = try deviceInfo("lockState")
        if lockState["passcodeRequired"] as? Bool == true {
            throw SomaError("device_locked", "Unlock the iPhone and connect again")
        }
        endpoint = .hostPort(host: .init(address), port: 47821)
        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        runner.arguments = ["xcodebuild", "test-without-building", "-xctestrun", config.xctestrun,
            "-destination", "platform=iOS,id=\(udid)", "-parallel-testing-enabled", "NO",
            "-only-testing:AgentSomaTests/LiveSessionTests/testCommandSession",
            "-resultBundlePath", paths.directory.appendingPathComponent("run.xcresult").path]
        var environment = ProcessInfo.processInfo.environment
        environment["TEST_RUNNER_AGENTSOMA_SESSION_TOKEN"] = token
        environment["TEST_RUNNER_AGENTSOMA_LISTEN_HOST"] = address
        environment["TEST_RUNNER_AGENTSOMA_HOST_MANAGED"] = "1"
        runner.environment = environment
        runner.standardInput = FileHandle.nullDevice
        runner.standardOutput = log
        runner.standardError = log
        try runner.run()
        process = runner
        try saveJSON(["device": udid, "address": address, "xcodebuildPid": runner.processIdentifier],
                     to: paths.directory.appendingPathComponent("backend.json"))
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        while runner.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            // Only startup health checks retry. No UI command is sent until readiness succeeds.
            if let response = try? request("ping", timeout: 1), response["ok"] as? Bool == true,
               let result = response["result"] as? [String: Any] {
                guard result["lifecycleOwner"] as? String == "host", result["observationVersion"] as? Int == 1 else {
                    throw SomaError("runner_needs_rebuild", "Rebuild the Runner with host-managed lifetime and observation support")
                }
                identity = response["sessionId"] as? String
                runnerPID = response["runnerPid"] as? Int
                guard identity != nil, runnerPID != nil else {
                    throw SomaError("invalid_runner_identity", "Runner did not report its session identity")
                }
                return metadata()
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw SomaError("runner_start_failed", "XCTest did not become ready; see \(logURL.path)")
    }

    private func deviceInfo(_ kind: String) throws -> [String: Any] {
        let output = paths.directory.appendingPathComponent("device-\(kind).json")
        let discovery = Process()
        discovery.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        discovery.arguments = ["devicectl", "device", "info", kind, "--device", config.device,
                               "--timeout", "20", "--json-output", output.path]
        discovery.standardInput = FileHandle.nullDevice
        discovery.standardOutput = log
        discovery.standardError = log
        try discovery.run()
        discovery.waitUntilExit()
        guard discovery.terminationStatus == 0,
              let result = try jsonObject(Data(contentsOf: output))["result"] as? [String: Any] else {
            throw SomaError("device_preflight_failed", "CoreDevice \(kind) failed; see xcodebuild.log")
        }
        return result
    }

    private func metadata() -> [String: Any] {
        ["runnerSession": identity ?? "", "runnerPid": runnerPID ?? 0,
         "xcodebuildPid": process?.processIdentifier ?? 0, "transport": "native-coredevice"]
    }

    private func request(_ operation: String, fields: [String: Any] = [:], timeout: TimeInterval = 45) throws -> [String: Any] {
        guard let endpoint else { throw SomaError("backend_unavailable", "Runner is not connected") }
        var request = fields
        request["id"] = UUID().uuidString
        request["token"] = token
        request["op"] = operation
        let response = try JSONTransport.exchange(endpoint: endpoint, request: request, timeout: timeout)
        if let identity, response["sessionId"] as? String != identity {
            throw TransportError(description: "Runner session changed; reconnect and observe", possiblySent: true)
        }
        return response
    }

    func status() throws -> [String: Any] {
        let response = try request("ping", timeout: 3)
        guard response["ok"] as? Bool == true else {
            throw SomaError("runner_unavailable", "Runner health check failed")
        }
        var result = metadata()
        result["sequence"] = response["sequence"]
        return result
    }

    func open(bundle: String) throws -> [String: Any] {
        let response = try request("launch", fields: ["bundleId": bundle])
        guard response["ok"] as? Bool == true else {
            // The spike has no precise execution-phase facts. Conservatively classify this as unknown.
            throw TransportError(description: response["error"] as? String ?? "Runner rejected open", possiblySent: true)
        }
        return response["result"] as? [String: Any] ?? [:]
    }

    func observe() throws -> CapturedObservation {
        let response = try request("observe")
        guard let result = response["result"] as? [String: Any],
              response["ok"] as? Bool == true || result["axStatus"] as? String == "unavailable" else {
            throw SomaError("observe_failed", response["error"] as? String ?? "Runner did not return an observation")
        }
        return try XCTestCapture.decode(result)
    }

    func stop() -> [String: Any] {
        guard let runner = process else {
            deviceLock = nil
            return ["xcodebuildExited": true]
        }
        var acknowledged = false
        if identity != nil, runner.isRunning {
            acknowledged = (try? request("shutdown", timeout: 5)["ok"] as? Bool) == true
        }
        var deadline = ProcessInfo.processInfo.systemUptime + 15
        while runner.isRunning, ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.05) }
        var forced = false
        if runner.isRunning {
            forced = true
            runner.terminate()
            deadline = ProcessInfo.processInfo.systemUptime + 3
            while runner.isRunning, ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if runner.isRunning { kill(runner.processIdentifier, SIGKILL) }
        }
        runner.waitUntilExit()
        process = nil
        deviceLock = nil
        try? log?.close()
        log = nil
        return ["shutdownAcknowledged": acknowledged, "xcodebuildExited": true,
                "xcodebuildExitCode": Int(runner.terminationStatus), "forced": forced]
    }
}
