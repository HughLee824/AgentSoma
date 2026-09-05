import ArgumentParser
import AgentSomaCore
import Foundation

struct SessionOptions: ParsableArguments {
    @Option(help: "Session identifier returned by connect.") var session: String?

    func requiredSession() throws -> String {
        guard let session else { throw ValidationError("--session is required") }
        return session
    }
}

@main
struct AgentSoma: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentsoma", abstract: "Eyes and hands for agents operating a real iPhone.",
        subcommands: [BuildRunner.self, Devices.self, Connect.self, Status.self, Apps.self, Open.self, Observe.self, Inspect.self, Tap.self, Swipe.self, TypeText.self, Press.self, Disconnect.self, Host.self])
    @OptionGroup var options: SessionOptions
}

private func output(compact: Bool = false, _ operation: () throws -> [String: Any]) throws {
    let response: [String: Any]
    do { response = try operation() }
    catch {
        response = ["ok": false, "error": ["code": (error as? SomaError)?.code ?? "command_failed",
                                            "message": String(describing: error)]]
    }
    if compact, response["ok"] as? Bool == true, let result = response["result"] as? [String: Any],
       let text = result["text"] as? String { print(text) }
    else { print(String(decoding: try jsonData(response), as: UTF8.self)) }
    if response["ok"] as? Bool != true { throw ExitCode.failure }
}

struct BuildRunner: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "build-runner", abstract: "Build and verify the signed Runner using Xcode; return its .xctestrun path.")
    @Option(help: "AgentSoma source checkout; defaults to the current directory.") var sourceRoot = "."
    @Option(help: "Apple development team ID; omit to use the Runner project's signing settings.") var team: String?
    @Option(help: "Runner test bundle ID; omit to use the Runner project's signing settings.") var bundleID: String?

    mutating func run() throws {
        try output {
            ["ok": true, "result": try RunnerBuild.build(sourceRoot: URL(fileURLWithPath: sourceRoot), team: team, bundleID: bundleID)]
        }
    }
}

struct Connect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a session and return once the Runner is ready.")
    @Option(help: "Connected iPhone UDID or CoreDevice identifier.") var device: String
    @Option(help: "Signed .xctestrun path returned by build-runner.") var xctestrun: String
    @Option(help: "Idle duration, such as 30m, 60m or 10s.") var idleTimeout = "30m"

    mutating func run() throws {
        try output {
            try SessionClient.connect(device: device,
                xctestrun: URL(fileURLWithPath: xctestrun).standardizedFileURL,
                idleTimeout: IdleTimeout(idleTimeout))
        }
    }
}

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List devices known to CoreDevice; connect checks session readiness.")
    mutating func run() throws {
        try output { ["ok": true, "result": ["devices": try DeviceDiscovery.devices()]] }
    }
}

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List installed apps, up to 50 per page, without changing the device UI.")
    @OptionGroup var options: SessionOptions
    @Option(help: "Case-insensitive substring of the app name or bundle ID.") var query: String?
    @Option(help: "Offset returned as nextOffset by the previous page.") var offset = 0
    mutating func run() throws {
        let session = try options.requiredSession()
        var fields: [String: Any] = ["offset": offset]
        fields["query"] = query
        try output { try SessionClient.call(session: session, operation: "apps", fields: fields) }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the session and Runner without renewing idle time.")
    @OptionGroup var options: SessionOptions
    mutating func run() throws {
        let session = try options.requiredSession()
        try output { try SessionClient.call(session: session, operation: "status") }
    }
}

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Bring an app to the foreground and renew the session.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Installed app bundle identifier returned by apps.") var bundleID: String
    mutating func run() throws {
        let session = try options.requiredSession()
        try output { try SessionClient.call(session: session, operation: "open", fields: ["bundleId": bundleID]) }
    }
}

struct Disconnect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Finish admitted commands and release the session.")
    @OptionGroup var options: SessionOptions
    mutating func run() throws {
        let session = try options.requiredSession()
        try output { try SessionClient.call(session: session, operation: "disconnect") }
    }
}

struct Observe: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture a screenshot and compact AX text with new element references.")
    @OptionGroup var options: SessionOptions
    mutating func run() throws {
        let session = try options.requiredSession()
        try output(compact: true) { try SessionClient.call(session: session, operation: "observe") }
    }
}

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read a cached observation or subtree without recapturing or renewing references.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Observation or element reference, such as o1 or o1:e2.") var reference: String
    @Option(help: "Node offset within the cached subtree, returned by a previous inspect page.") var offset = 0
    mutating func run() throws {
        let session = try options.requiredSession()
        try output(compact: true) {
            try SessionClient.call(session: session, operation: "inspect", fields: ["reference": reference, "offset": offset])
        }
    }
}

struct Host: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "_host", shouldDisplay: false)
    @Option var directory: String
    mutating func run() throws { try runHost(directory: URL(fileURLWithPath: directory, isDirectory: true)) }
}

struct Tap: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Tap a current element, or a point in a current observation.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Element reference; use an observation ID with --x and --y.") var reference: String
    @Option(help: "Horizontal screen point coordinate.") var x: Double?
    @Option(help: "Vertical screen point coordinate.") var y: Double?
    mutating func run() throws {
        let session = try options.requiredSession()
        var fields: [String: Any] = ["reference": reference]
        fields["x"] = x; fields["y"] = y
        try output { try SessionClient.call(session: session, operation: "tap", fields: fields) }
    }
}

struct Swipe: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Swipe within a current element's area.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Current element reference, such as o1:e13.") var reference: String
    @Option(help: "Finger movement: up, down, left or right.") var direction: String
    mutating func run() throws {
        let session = try options.requiredSession()
        try output { try SessionClient.call(session: session, operation: "swipe", fields: ["reference": reference, "direction": direction]) }
    }
}

struct TypeText: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "type", abstract: "Insert at the existing caret, or replace a text input's entire contents.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Current text input reference.") var reference: String
    @Option(help: "insert requires existing keyboard focus; replace focuses and selects all.") var mode: String
    @Option(help: "Literal text up to 4096 UTF-8 bytes; no control keys or newlines. Empty text clears in replace mode.") var text: String?
    @Flag(help: "Read UTF-8 text from stdin until EOF, up to 4096 bytes. No trimming; use instead of --text.") var stdin = false

    mutating func validate() throws {
        guard (text != nil) != stdin else { throw ValidationError("Choose exactly one of --text or --stdin") }
    }

    mutating func run() throws {
        let session = try options.requiredSession()
        try output {
            let value: String
            do { value = try stdin ? TextInput.read(from: .standardInput) : text! }
            catch {
                return ["ok": false, "outcome": "not_dispatched",
                        "error": ["code": (error as? SomaError)?.code ?? "stdin_read_failed", "message": String(describing: error)]]
            }
            return try SessionClient.call(session: session, operation: "type", fields: ["reference": reference, "mode": mode, "text": value])
        }
    }
}

struct Press: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Send an explicit Return to a text input with existing keyboard focus.")
    @OptionGroup var options: SessionOptions
    @Argument(help: "Current text input reference; this command does not tap to focus.") var reference: String
    @Option(help: "Key to send; currently only return is supported.") var key: String
    mutating func run() throws {
        let session = try options.requiredSession()
        try output { try SessionClient.call(session: session, operation: "press", fields: ["reference": reference, "key": key]) }
    }
}
