import Foundation
import Network
import Darwin

public enum SessionClient {
    public static func connect(device: String, xctestrun: URL, idleTimeout: IdleTimeout) throws -> [String: Any] {
        guard FileManager.default.isReadableFile(atPath: xctestrun.path), xctestrun.pathExtension == "xctestrun" else {
            throw SomaError("runner_not_built", "Provide a readable, signed .xctestrun using --xctestrun")
        }
        umask(0o077)
        let session = "s" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let paths = try SessionPaths(session: session)
        try SessionPaths.secureDirectory(paths.directory)
        let config = HostConfiguration(session: session, device: device, xctestrun: xctestrun.path,
                                       idleTimeoutSeconds: idleTimeout.seconds)
        try JSONEncoder().encode(config).write(to: paths.config, options: .atomic)
        FileManager.default.createFile(atPath: paths.log.path, contents: nil)
        let log = try FileHandle(forWritingTo: paths.log)
        defer { try? log.close() }
        let host = Process()
        host.executableURL = Bundle.main.executableURL
        host.arguments = ["_host", "--directory", paths.directory.path]
        host.standardInput = FileHandle.nullDevice
        host.standardOutput = log
        host.standardError = log
        try host.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 150
        while ProcessInfo.processInfo.systemUptime < deadline {
            let errorURL = paths.directory.appendingPathComponent("startup-error.json")
            if let data = try? Data(contentsOf: errorURL), let error = try? jsonObject(data) {
                host.waitUntilExit()
                throw SomaError(error["code"] as? String ?? "host_start_failed", error["message"] as? String ?? "Host startup failed")
            }
            guard host.isRunning else {
                throw SomaError("host_start_failed", "Session host exited; see \(paths.log.path)")
            }
            if let response = try? call(session: session, operation: "status", timeout: 4), response["ok"] as? Bool == true {
                var response = response
                response["directory"] = paths.directory.path
                return response
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        host.terminate()
        throw SomaError("connect_timeout", "Host did not become ready; cleanup requested. See \(paths.log.path)")
    }

    public static func call(session: String, operation: String, fields: [String: Any] = [:], timeout: TimeInterval = 75) throws -> [String: Any] {
        let paths = try SessionPaths(session: session)
        let id = UUID().uuidString
        var request = fields
        request["id"] = id
        request["version"] = 1
        request["session"] = session
        request["op"] = operation
        do {
            let response = try JSONTransport.exchange(endpoint: .unix(path: paths.socket), request: request, timeout: timeout)
            guard response["session"] as? String == session else {
                throw TransportError(description: "Response session does not match", possiblySent: true)
            }
            return response
        } catch {
            let uncertain = (error as? TransportError)?.possiblySent ?? false
            var response: [String: Any] = ["id": id, "session": session, "ok": false,
                "error": ["code": "session_unavailable", "message": String(describing: error)]]
            if operation == "open" || DeviceAction.operations.contains(operation) {
                response["outcome"] = uncertain ? "unknown" : "not_dispatched"
            }
            return response
        }
    }
}
