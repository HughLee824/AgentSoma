import XCTest
@testable import AgentSomaCore

final class DeviceActionTests: XCTestCase {
    func testInputModesUnicodeAndControlKeys() throws {
        for mode in ["insert", "replace"] {
            let action = try DeviceAction(operation: "type", request: ["reference": "o1:e27", "mode": mode, "text": "北京👩‍💻e\u{301}"])
            XCTAssertEqual(action.fields["text"] as? String, "北京👩‍💻e\u{301}")
        }
        XCTAssertNoThrow(try DeviceAction(operation: "type", request: ["reference": "o1:e27", "mode": "replace", "text": ""]))
        for text in ["", "submit\n", "\r", "\t", "\u{7f}", "\u{F700}", String(repeating: "北", count: 1366)] {
            XCTAssertThrowsError(try DeviceAction(operation: "type", request: ["reference": "o1:e27", "mode": "insert", "text": text]))
        }
        XCTAssertThrowsError(try DeviceAction(operation: "type", request: ["reference": "o1:e27", "text": "hello"]))
    }

    func testCoordinateAndSwipeTargetsAreExplicit() throws {
        XCTAssertNoThrow(try DeviceAction(operation: "tap", request: ["reference": "o1", "x": 10, "y": 20]))
        for request: [String: Any] in [["reference": "o1"], ["reference": "o1:e2", "x": 1, "y": 2],
                                      ["reference": "o1", "x": 1], ["reference": "o1", "x": Double.infinity, "y": 1]] {
            XCTAssertThrowsError(try DeviceAction(operation: "tap", request: request))
        }
        for direction in ["up", "down", "left", "right"] {
            XCTAssertNoThrow(try DeviceAction(operation: "swipe", request: ["reference": "o1:e2", "direction": direction]))
        }
        XCTAssertThrowsError(try DeviceAction(operation: "swipe", request: ["reference": "o1:e2", "direction": "forward"]))
    }

    func testReturnRequiresAnExplicitKeyAndElement() throws {
        let action = try DeviceAction(operation: "press", request: ["reference": "o1:e27", "key": "return"])
        XCTAssertEqual(action.fields["key"] as? String, "return")
        for request: [String: Any] in [["reference": "o1:e27"], ["reference": "o1:e27", "key": "enter"],
                                      ["reference": "o1:e27", "key": "\n"], ["reference": "o1", "key": "return"],
                                      ["reference": "o1", "key": "return", "x": 1, "y": 2]] {
            XCTAssertThrowsError(try DeviceAction(operation: "press", request: request))
        }
    }

    func testExecutionFactsDistinguishRejectionUnknownAndMalformedSuccess() throws {
        let done: [String: Any] = ["ok": true, "execution": ["started": true, "completed": true], "result": ["kind": "tap"]]
        XCTAssertEqual(try ActionReply.decode(done)["kind"] as? String, "tap")
        let cases: [([String: Any], Bool)] = [
            (["ok": false, "execution": ["started": false, "completed": false]], false),
            (["ok": false, "execution": ["started": true, "completed": false]], true),
            (["ok": false, "execution": ["started": false, "inputCompleted": true, "completed": false]], true),
            (["ok": true], true),
            (["ok": true, "execution": ["started": false, "completed": true]], true),
            (["ok": true, "execution": ["started": true, "completed": false]], true)
        ]
        for (response, uncertain) in cases {
            XCTAssertThrowsError(try ActionReply.decode(response)) { error in
                XCTAssertEqual((error as? ActionFailure)?.possiblyExecuted, uncertain)
            }
        }
    }

    func testTargetPathPreservesSourceAncestryWithoutAgentReferences() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/as-action-\(UUID().uuidString.prefix(8))")
        let cache = ObservationCache(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try observationFixture()
        _ = try cache.store(fixture)
        let action = try DeviceAction(operation: "type", request: ["reference": "o1:e27", "mode": "insert", "text": "hi"])
        let target = try cache.resolveTarget(for: action)
        XCTAssertEqual(target.path.first?["type"] as? Int, 2)
        XCTAssertEqual(target.path.last?["type"] as? Int, 49)
        XCTAssertEqual(target.path.last?["label"] as? String, "Web input")
        XCTAssertTrue(target.path.allSatisfy { $0["ref"] == nil && $0["index"] == nil && $0["parent"] == nil })
        XCTAssertGreaterThan(target.path.count, 3)
        let wrong = try DeviceAction(operation: "type", request: ["reference": "o1:e11", "mode": "insert", "text": "hi"])
        XCTAssertThrowsError(try cache.resolveTarget(for: wrong))
        let press = try DeviceAction(operation: "press", request: ["reference": "o1:e27", "key": "return"])
        XCTAssertNoThrow(try cache.resolveTarget(for: press))
        let wrongPress = try DeviceAction(operation: "press", request: ["reference": "o1:e11", "key": "return"])
        XCTAssertThrowsError(try cache.resolveTarget(for: wrongPress))
        _ = try cache.store(fixture)
        XCTAssertThrowsError(try cache.resolveTarget(for: action))
    }
}
