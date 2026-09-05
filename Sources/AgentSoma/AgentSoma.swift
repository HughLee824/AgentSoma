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
        subcommands: [Connect.self, Status.self, Open.self, Observe.self, Inspect.self, Disconnect.self, Host.self])
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

struct Connect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a session and return once the Runner is ready.")
    @Option(help: "Connected iPhone UDID or CoreDevice identifier.") var device: String
    @Option(help: "Signed .xctestrun produced by the current Runner build.") var xctestrun: String
    @Option(help: "Idle duration, such as 30m, 60m or 10s.") var idleTimeout = "30m"

    mutating func run() throws {
        try output {
            try SessionClient.connect(device: device,
                xctestrun: URL(fileURLWithPath: xctestrun).standardizedFileURL,
                idleTimeout: IdleTimeout(idleTimeout))
        }
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
    @Argument(help: "Installed app bundle identifier. The current spike Runner supports Fixture and Calculator only.") var bundleID: String
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
