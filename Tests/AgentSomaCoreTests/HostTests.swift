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
    var rejectOpenBeforeSend = false
    private(set) var openCount = 0
    private(set) var stopCount = 0
    private(set) var observeCount = 0
    private(set) var actionCount = 0
    var actionFailure: ActionFailure?
    var blockAction = false
    let actionStarted = DispatchSemaphore(value: 0)
    let releaseAction = DispatchSemaphore(value: 0)

    func start() throws -> [String: Any] { ["runnerSession": "controlled-runner", "runnerPid": 123] }
    func status() throws -> [String: Any] { try start() }
    func open(bundle: String) throws -> [String: Any] {
        if rejectOpenBeforeSend { throw TransportError(description: "Not connected", possiblySent: false) }
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
    func observe() throws -> CapturedObservation {
        observeCount += 1
        return try observationFixture()
    }
    func perform(_ action: DeviceAction, target: ObservedTarget) throws -> [String: Any] {
        actionCount += 1
        actionStarted.signal()
        if blockAction { _ = releaseAction.wait(timeout: .now() + 5) }
        if let actionFailure { throw actionFailure }
        return ["kind": action.kind]
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
        let observed = try call(paths, session: session, op: "observe")["result"] as! [String: Any]
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: observed["screenshot"] as! String))
        XCTAssertThrowsError(try call(paths, session: session, op: "inspect", fields: ["reference": "o1", "offset": 0]))
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

    func testInspectDoesNotCallDeviceAndDispatchedOpenInvalidatesCachedRefs() throws {
        let backend = ControlledBackend()
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        let observed = try call(paths, session: session, op: "observe")["result"] as! [String: Any]
        let image = observed["screenshot"] as! String
        let inspect: [String: Any] = ["reference": "o1:e27", "offset": 0]
        func validity() throws -> String? {
            (try call(paths, session: session, op: "inspect", fields: inspect)["result"] as? [String: Any])?["refs"] as? String
        }
        XCTAssertEqual(try validity(), "current")
        _ = try call(paths, session: session, op: "open") // Invalid parameter, never admitted.
        XCTAssertEqual(try validity(), "current")
        backend.rejectOpenBeforeSend = true
        XCTAssertEqual(try call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])["outcome"] as? String, "not_dispatched")
        XCTAssertEqual(try validity(), "current")
        backend.rejectOpenBeforeSend = false
        backend.loseOpenResponse = true
        XCTAssertEqual(try call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])["outcome"] as? String, "unknown")
        XCTAssertEqual(try validity(), "invalidated")
        XCTAssertEqual(backend.observeCount, 1)
        XCTAssertEqual(backend.openCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image))
        _ = try call(paths, session: session, op: "observe")
        backend.loseOpenResponse = false
        _ = try call(paths, session: session, op: "open", fields: ["bundleId": "fixture"])
        let latest = try call(paths, session: session, op: "inspect", fields: ["reference": "o2:e27", "offset": 0])
        XCTAssertEqual((latest["result"] as? [String: Any])?["refs"] as? String, "invalidated")
        _ = try call(paths, session: session, op: "disconnect")
        wait(for: [finished], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: image))
    }

    func testObservationAndInspectRenewIdleButInvalidInspectDoesNot() throws {
        let backend = ControlledBackend()
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        _ = try call(paths, session: session, op: "observe")
        let first = try call(paths, session: session, op: "status")["idleRemainingSeconds"] as! Double
        Thread.sleep(forTimeInterval: 0.1)
        let invalid = try call(paths, session: session, op: "inspect", fields: ["reference": "o99", "offset": 0])
        XCTAssertEqual(invalid["ok"] as? Bool, false)
        let afterInvalid = try call(paths, session: session, op: "status")["idleRemainingSeconds"] as! Double
        XCTAssertLessThan(afterInvalid, first - 0.08)
        _ = try call(paths, session: session, op: "inspect", fields: ["reference": "o1", "offset": 0])
        let renewed = try call(paths, session: session, op: "status")["idleRemainingSeconds"] as! Double
        XCTAssertGreaterThan(renewed, afterInvalid + 0.08)
        XCTAssertEqual(backend.observeCount, 1)
        _ = try call(paths, session: session, op: "disconnect")
        wait(for: [finished], timeout: 3)
    }

    func testActionFactsPreserveRejectedReferencesAndInvalidateChangedOrUnknownTargets() throws {
        let backend = ControlledBackend()
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        for (index, failure) in [
            ActionFailure(code: "ambiguous_target", description: "Ambiguous", possiblyExecuted: false, requiresObservation: false),
            ActionFailure(code: "target_changed", description: "Changed", possiblyExecuted: false, requiresObservation: true),
            ActionFailure(code: "lost_result", description: "Unknown", possiblyExecuted: true, requiresObservation: true)
        ].enumerated() {
            _ = try call(paths, session: session, op: "observe")
            backend.actionFailure = failure
            let reference = "o\(index + 1):e11"
            let result = try call(paths, session: session, op: "tap", fields: ["reference": reference])
            XCTAssertEqual(result["outcome"] as? String, failure.possiblyExecuted ? "unknown" : "not_dispatched")
            let detail = try call(paths, session: session, op: "inspect", fields: ["reference": reference, "offset": 0])
            XCTAssertEqual((detail["result"] as? [String: Any])?["refs"] as? String,
                           index == 0 ? "current" : (index == 1 ? "target_changed" : "invalidated"))
        }
        XCTAssertEqual(backend.actionCount, 3)
        let stale = try call(paths, session: session, op: "tap", fields: ["reference": "o3:e11"])
        XCTAssertEqual(stale["outcome"] as? String, "not_dispatched")
        XCTAssertEqual(backend.actionCount, 3)
        _ = try call(paths, session: session, op: "disconnect")
        wait(for: [finished], timeout: 3)
    }

    func testQueuedActionsCannotReuseAReferenceAfterTheFirstAction() throws {
        let backend = ControlledBackend()
        backend.blockAction = true
        let (paths, session, finished) = try host(timeout: 5, backend: backend)
        _ = try call(paths, session: session, op: "observe")
        let first = expectation(description: "first action")
        let second = expectation(description: "second action rejected")
        DispatchQueue.global().async {
            do {
                let result = try self.call(paths, session: session, op: "tap", fields: ["reference": "o1:e11"])
                XCTAssertEqual(result["outcome"] as? String, "completed")
            } catch { XCTFail("\(error)") }
            first.fulfill()
        }
        XCTAssertEqual(backend.actionStarted.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            do {
                let result = try self.call(paths, session: session, op: "tap", fields: ["reference": "o1:e11"])
                XCTAssertEqual(result["outcome"] as? String, "not_dispatched")
            } catch { XCTFail("\(error)") }
            second.fulfill()
        }
        backend.releaseAction.signal()
        wait(for: [first, second], timeout: 3)
        XCTAssertEqual(backend.actionCount, 1)
        _ = try call(paths, session: session, op: "disconnect")
        wait(for: [finished], timeout: 3)
    }
}
