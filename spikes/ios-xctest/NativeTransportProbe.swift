import Foundation
import Network

// Bounded transport probe, not the product CLI or session host.
struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func json(_ url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
        throw ProbeError("Expected a JSON object at \(url.path)")
    }
    return value
}

func save(_ value: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        .write(to: url, options: .atomic)
}

func start(_ directory: URL, udid: String) throws {
    let files = FileManager.default
    guard !files.fileExists(atPath: directory.path) else { throw ProbeError("Use a fresh evidence directory") }
    try files.createDirectory(at: directory, withIntermediateDirectories: true,
                              attributes: [.posixPermissions: 0o700])
    let logURL = directory.appendingPathComponent("xcodebuild.log")
    files.createFile(atPath: logURL.path, contents: nil)
    let log = try FileHandle(forWritingTo: logURL)
    defer { try? log.close() }
    let detailsURL = directory.appendingPathComponent("device-details.json")
    let discovery = Process()
    discovery.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    discovery.arguments = ["devicectl", "device", "info", "details", "--device", udid,
                           "--timeout", "20", "--json-output", detailsURL.path]
    discovery.standardOutput = log
    discovery.standardError = log
    try discovery.run()
    discovery.waitUntilExit()
    guard discovery.terminationStatus == 0,
          let result = try json(detailsURL)["result"] as? [String: Any],
          let properties = result["connectionProperties"] as? [String: Any],
          let address = properties["tunnelIPAddress"] as? String,
          IPv6Address(address) != nil, address != "::" else {
        throw ProbeError("Native CoreDevice IPv6 discovery failed; see \(logURL.path)")
    }
    let token = UUID().uuidString + UUID().uuidString
    let configURL = directory.appendingPathComponent("session.json")
    try save(["host": address, "port": 47821, "token": token, "udid": udid], to: configURL)
    try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

    let spike = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let runner = Process()
    runner.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    runner.currentDirectoryURL = spike
    runner.arguments = ["xcodebuild", "test-without-building", "-xctestrun",
        "build/Build/Products/AgentSomaSpike_iphoneos18.0-arm64.xctestrun",
        "-destination", "platform=iOS,id=\(udid)", "-parallel-testing-enabled", "NO",
        "-only-testing:AgentSomaTests/LiveSessionTests/testCommandSession",
        "-resultBundlePath", directory.appendingPathComponent("run.xcresult").path]
    var environment = ProcessInfo.processInfo.environment
    environment["TEST_RUNNER_AGENTSOMA_SESSION_TOKEN"] = token
    environment["TEST_RUNNER_AGENTSOMA_LISTEN_HOST"] = address
    runner.environment = environment
    runner.standardOutput = log
    runner.standardError = log
    try runner.run()
    try save(["host": address, "port": 47821, "transport": "native-coredevice-ipv6",
              "launcherPid": ProcessInfo.processInfo.processIdentifier,
              "xcodebuildPid": runner.processIdentifier, "startedAt": Date().timeIntervalSince1970],
             to: directory.appendingPathComponent("launch.json"))
    print("SESSION_DIRECTORY=\(directory.path) host=\(address)")
    fflush(stdout)
    runner.waitUntilExit()
    try save(["exitCode": runner.terminationStatus, "endedAt": Date().timeIntervalSince1970],
             to: directory.appendingPathComponent("exit.json"))
    guard runner.terminationStatus == 0 else { throw ProbeError("XCTest failed; see \(logURL.path)") }
}

func exchange(host: String, port: UInt16, data: Data) throws -> Data {
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let queue = DispatchQueue(label: "agentsoma.native-probe")
    let completed = DispatchSemaphore(value: 0)
    var outcome: Result<Data, Error>?
    var buffer = Data()
    func finish(_ value: Result<Data, Error>) {
        guard outcome == nil else { return }
        outcome = value
        connection.cancel()
        completed.signal()
    }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, done, error in
            buffer.append(chunk ?? Data())
            if buffer.count > 16 * 1024 * 1024 {
                finish(.failure(ProbeError("Response exceeds probe limit")))
            } else if let newline = buffer.firstIndex(of: 10) {
                finish(.success(Data(buffer[..<newline])))
            } else if let error {
                finish(.failure(error))
            } else if done {
                finish(.failure(ProbeError("EOF before response; do not replay an action")))
            } else { receive() }
        }
    }
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { finish(.failure(error)) } else { receive() }
            })
        case .failed(let error): finish(.failure(error))
        default: break
        }
    }
    queue.asyncAfter(deadline: .now() + 45) {
        finish(.failure(ProbeError("Response timeout; do not replay an action")))
    }
    connection.start(queue: queue)
    completed.wait()
    return try outcome!.get()
}

func call(_ directory: URL, input: String) throws {
    let config = try json(directory.appendingPathComponent("session.json"))
    guard let host = config["host"] as? String, let port = config["port"] as? UInt16,
          let token = config["token"] as? String,
          let inputData = input.data(using: .utf8),
          var request = try JSONSerialization.jsonObject(with: inputData) as? [String: Any],
          let operation = request["op"] as? String,
          ["ping", "launch", "observe", "tap", "type", "swipe", "shutdown"].contains(operation) else {
        throw ProbeError("Invalid probe configuration or command")
    }
    request["id"] = UUID().uuidString
    let publicRequest = request
    request["token"] = token
    var wire = try JSONSerialization.data(withJSONObject: request)
    wire.append(10)
    let began = ProcessInfo.processInfo.systemUptime
    let data = try exchange(host: host, port: port, data: wire)
    guard var response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          response["id"] as? String == publicRequest["id"] as? String,
          let sequence = response["sequence"] as? Int else { throw ProbeError("Mismatched response") }
    response["hostMs"] = (ProcessInfo.processInfo.systemUptime - began) * 1000
    response["responseBytes"] = data.count
    response["clientPid"] = ProcessInfo.processInfo.processIdentifier
    response["receivedAt"] = Date().timeIntervalSince1970
    response["request"] = publicRequest
    let stem = String(format: "%03d-%@", sequence, operation)
    if var result = response["result"] as? [String: Any],
       let base64 = result.removeValue(forKey: "screenshotBase64") as? String,
       let png = Data(base64Encoded: base64) {
        let screenshotURL = directory.appendingPathComponent(stem + ".png")
        try png.write(to: screenshotURL)
        result["screenshotPath"] = screenshotURL.path
        response["result"] = result
    }
    try save(response, to: directory.appendingPathComponent(stem + ".json"))
    if var result = response["result"] as? [String: Any], let nodes = result.removeValue(forKey: "nodes") as? [Any] {
        result["nodeCount"] = nodes.count
        response["result"] = result
    }
    print(String(decoding: try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), as: UTF8.self))
    if response["ok"] as? Bool != true { throw ProbeError("Runner rejected the command; response saved") }
}

do {
    let args = CommandLine.arguments
    guard args.count == 4 else { throw ProbeError("Usage: native-probe start <fresh-directory> <udid> | call <directory> '<command-json>'") }
    let directory = URL(fileURLWithPath: args[2], isDirectory: true).standardizedFileURL
    switch args[1] {
    case "start": try start(directory, udid: args[3])
    case "call": try call(directory, input: args[3])
    default: throw ProbeError("Unknown probe mode")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
