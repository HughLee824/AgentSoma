import XCTest
import Foundation
import Network
@testable import AgentSomaCore

private final class ControlledBackend: SessionBackend {
    let opened = DispatchSemaphore(value: 0)
    let releaseOpen = DispatchSemaphore(value: 0)
    let stopped = DispatchSemaphore(value: 0)
    var blockOpen = false
    var loseOpenResponse = false
    private(set) var openCount = 0
    private(set) var stopCount = 0

    func start() throws -> [String: Any] { ["runnerSession": "controlled-runner", "runnerPid": 123] }
    func status() throws -> [String: Any] { try start() }
    func open(bundle: String) throws -> [String: Any] {
        openCount += 1
        opened.signal()
        if blockOpen { _ = releaseOpen.wait(timeout: .now() + 5) }
        if loseOpenResponse { throw TransportError(description: "Lost response", possiblySent: true) }
        return ["bundleId": bundle]
    }
    func stop() -> [String: Any] {
        stopCount += 1
        stopped.signal()
        return ["shutdownAcknowledged": true, "xcodebuildExited": true, "xcodebuildExitCode": 0, "forced": false]
    }
}

final class HostTests: XCTestCase {
    private func host(timeout: Double, backend: ControlledBackend) throws -> (SessionPaths, String, XCTestExpectation) {
        let directory = URL(fileURLWithPath: "/private/tmp/as-test-\(UUID().uuidString.prefix(8))")
        try SessionPaths.secureDirectory(directory)
        let paths = SessionPaths(directory: directory)
        let session = "test-session"
        let config = HostConfiguration(session: session, device: "test", xctestrun: "/unused", idleTimeoutSeconds: timeout)
        let host = SessionHost(config: config, paths: paths, backend: backend)
        let finished = expectation(description: "host exited")
        DispatchQueue.global().async {
            do { try host.run() } catch { XCTFail("Host failed: \(error)") }
            finished.fulfill()
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let response = try? call(paths, session: session, op: "status"), response["ok"] as? Bool == true {
                return (paths, session, finished)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw SomaError("test_start_timeout", "Test host never became ready")
    }

    private func call(_ paths: SessionPaths, session: String, op: String, fields: [String: Any] = [:]) throws -> [String: Any] {
        var request = fields
        request["version"] = 1
        request["id"] = UUID().uuidString
        request["session"] = session
        request["op"] = op
        return try JSONTransport.exchange(endpoint: .unix(path: paths.socket), request: request, timeout: 5)
    }

    func testUnixIPCReuseDisconnectAndSocketRemoval() throws {
        let backend = ControlledBackend()
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        for _ in 0..<3 {
            let response = try call(paths, session: session, op: "status")
            XCTAssertEqual((response["result"] as? [String: Any])?["runnerSession"] as? String, "controlled-runner")
        }
        XCTAssertEqual(try call(paths, session: session, op: "disconnect")["ok"] as? Bool, true)
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(backend.stopCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.socket))
        XCTAssertThrowsError(try call(paths, session: session, op: "status"))
    }

    func testHealthTrafficCannotPreventIdleCleanup() throws {
        let backend = ControlledBackend()
        let (paths, session, finished) = try host(timeout: 0.4, backend: backend)
        let deadline = Date().addingTimeInterval(1.2)
        var checks = 0
        while Date() < deadline {
            if let reply = try? call(paths, session: session, op: "status"), reply["ok"] as? Bool == true { checks += 1 }
            else { break }
            Thread.sleep(forTimeInterval: 0.04)
        }
        wait(for: [finished], timeout: 2)
        XCTAssertGreaterThan(checks, 2)
        XCTAssertEqual(try jsonObject(Data(contentsOf: paths.exit))["reason"] as? String, "idle_timeout")
    }

    func testInFlightCommandSurvivesTimeoutAndRenewsAtCompletion() throws {
        let backend = ControlledBackend()
        backend.blockOpen = true
        let (paths, session, finished) = try host(timeout: 0.4, backend: backend)
        let responseReceived = expectation(description: "open completed")
        DispatchQueue.global().async {
            do {
                let response = try self.call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])
                XCTAssertEqual(response["outcome"] as? String, "completed")
            } catch { XCTFail("\(error)") }
            responseReceived.fulfill()
        }
        XCTAssertEqual(backend.opened.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(backend.stopped.wait(timeout: .now() + 0.65), .timedOut)
        backend.releaseOpen.signal()
        wait(for: [responseReceived], timeout: 2)
        let status = try call(paths, session: session, op: "status")
        XCTAssertGreaterThan(status["idleRemainingSeconds"] as? Double ?? 0, 0.2)
        wait(for: [finished], timeout: 2)
    }

    func testDisconnectWaitsForAdmittedCommand() throws {
        let backend = ControlledBackend()
        backend.blockOpen = true
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        let action = expectation(description: "action returned")
        let disconnect = expectation(description: "disconnect returned")
        DispatchQueue.global().async {
            _ = try? self.call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])
            action.fulfill()
        }
        XCTAssertEqual(backend.opened.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            do {
                let response = try self.call(paths, session: session, op: "disconnect")
                XCTAssertEqual(response["ok"] as? Bool, true)
            }
            catch { XCTFail("\(error)") }
            disconnect.fulfill()
        }
        XCTAssertEqual(backend.stopped.wait(timeout: .now() + 0.2), .timedOut)
        backend.releaseOpen.signal()
        wait(for: [action, disconnect, finished], timeout: 3)
        XCTAssertEqual(backend.openCount, 1)
        XCTAssertEqual(backend.stopCount, 1)
    }

    func testInvalidRequestsDoNotDispatchAndUnknownIsNotReplayed() throws {
        let backend = ControlledBackend()
        backend.loseOpenResponse = true
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        XCTAssertEqual(try call(paths, session: session, op: "open")["outcome"] as? String, "not_dispatched")
        XCTAssertEqual(backend.openCount, 0)
        XCTAssertEqual(try call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])["outcome"] as? String, "unknown")
        _ = try call(paths, session: session, op: "status")
        XCTAssertEqual(backend.openCount, 1)
        _ = try call(paths, session: session, op: "disconnect")
        wait(for: [finished], timeout: 3)
    }

    func testDeviceLockExclusionAndRelease() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/as-lock-\(UUID().uuidString.prefix(8))")
        try SessionPaths.secureDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: DeviceLock? = try DeviceLock(root: directory, device: "device-1")
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try DeviceLock(root: directory, device: "device-1"))
        first = nil
        XCTAssertNoThrow(try DeviceLock(root: directory, device: "device-1"))
    }
}
