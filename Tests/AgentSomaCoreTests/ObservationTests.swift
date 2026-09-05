import XCTest
import Foundation
@testable import AgentSomaCore

// Recorded AX only; a synthetic one-pixel PNG keeps unit tests independent of ignored device artifacts.
func observationFixture(_ name: String = "spike-observe.json") throws -> CapturedObservation {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let response = try jsonObject(Data(contentsOf: root.appendingPathComponent("docs/examples/observe/\(name)")))
    var result = response["result"] as! [String: Any]
    result["screenshotBase64"] = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII="
    result["axStatus"] = "available"
    result["snapshotFinishedAt"] = result["screenshotCapturedAt"]
    result["screenFrame"] = ["x": 0, "y": 0, "width": 390, "height": 844]
    if result["scope"] as? String == "app" { result["foregroundBundleId"] = result["bundleId"] }
    return try XCTestCapture.decode(result)
}

final class ObservationTests: XCTestCase {
    private func cache() throws -> (ObservationCache, URL) {
        let directory = URL(fileURLWithPath: "/private/tmp/as-observe-\(UUID().uuidString.prefix(8))")
        try SessionPaths.secureDirectory(directory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (ObservationCache(directory: directory), directory)
    }

    func testRecordedWebViewPreservesControlsValuesAndDistinctTargets() throws {
        let capture = try observationFixture()
        let lines = CompactAX.render(capture.nodes)
        XCTAssertEqual(lines, CompactAX.render(capture.nodes))
        let text = lines.joined(separator: "\n")
        for content in ["button \"Done\"", "button \"Show dialog\"", "Request notification permission",
                        "Notifications: notDetermined", "text_field \"Web input\" ax_value=\"Web text\"", "Web increment", "Web count: 0"] {
            XCTAssertTrue(text.contains(content), content)
        }
        XCTAssertEqual(lines.filter { $0.contains("web_view") }.count, 1)
        XCTAssertLessThan(lines.count, capture.nodes.count / 2)
        var first = capture.nodes[10].attributes
        first["index"] = 0; first["parent"] = NSNull(); first["enabled"] = false
        var second = first
        second["index"] = 1; second["parent"] = 0; second["identifier"] = "another-done"
        let duplicates = CompactAX.render([
            AXNode(index: 0, parent: nil, role: "button", attributes: first),
            AXNode(index: 1, parent: 0, role: "button", attributes: second)])
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertTrue(duplicates.allSatisfy { $0.contains("disabled") && $0.contains("id=") })
    }

    func testSystemAlertScopeIsDistinctFromTargetAndKeepsBothChoices() throws {
        let capture = try observationFixture("spike-system-alert.json")
        let (cache, _) = try cache()
        let response = try cache.store(capture)
        let text = try XCTUnwrap(response["text"] as? String)
        XCTAssertTrue(text.contains("scope=systemAlert"))
        XCTAssertTrue(text.contains("foreground=null"))
        XCTAssertTrue(text.contains("Would Like to Send You Notifications"))
        XCTAssertTrue(text.contains("Don’t Allow"))
        XCTAssertTrue(text.contains("button \"Allow\""))
        XCTAssertEqual(capture.metadata["sourceBundleId"] as? String, "com.apple.springboard")
    }

    func testInspectUsesOriginalAttributesAndDoesNotReviveStaleReferences() throws {
        let (cache, _) = try cache()
        let capture = try observationFixture()
        let stored = try cache.store(capture)
        let reference = try ObservationReference("o1:e27")
        XCTAssertEqual(try cache.resolveCurrent(reference).label, "Web input")
        let before = cache.beginAction()
        XCTAssertThrowsError(try cache.resolveCurrent(reference))
        cache.finishAction(previous: before, dispatched: false)
        XCTAssertNoThrow(try cache.resolveCurrent(reference))
        cache.finishAction(previous: cache.beginAction(), dispatched: true)
        XCTAssertThrowsError(try cache.resolveCurrent(reference))
        let details = try cache.inspect(reference, offset: 0)
        XCTAssertEqual(details["refs"] as? String, "invalidated")
        XCTAssertTrue((details["text"] as? String ?? "").contains("\"identifier\":\"\""))
        XCTAssertThrowsError(try cache.resolveCurrent(reference))
        let snapshot = try jsonObject(Data(contentsOf: URL(fileURLWithPath: stored["snapshot"] as! String)))
        let nodes = snapshot["nodes"] as! [[String: Any]]
        for (index, node) in capture.nodes.enumerated() {
            var saved = nodes[index]
            saved.removeValue(forKey: "ref"); saved.removeValue(forKey: "role")
            XCTAssertEqual(try jsonData(saved), try jsonData(node.attributes))
        }
        _ = try cache.store(capture)
        XCTAssertEqual(try cache.inspect(reference, offset: 0)["observation"] as? String, "o1")
        _ = try cache.store(capture)
        XCTAssertThrowsError(try cache.inspect(reference, offset: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored["screenshot"] as! String))
        try cache.clear()
        XCTAssertThrowsError(try cache.resolveCurrent(ObservationReference("o3:e27")))
    }

    func testOutputBudgetPaginationAndMissingSourceAreSeparate() throws {
        let original = try observationFixture()
        var nodes: [AXNode] = []
        for index in 0..<200 {
            var attributes = original.nodes[26].attributes
            attributes["index"] = index
            attributes["parent"] = index == 0 ? NSNull() : 0
            attributes["label"] = "field \(index)\n\"quoted\""
            attributes["value"] = String(repeating: "北京", count: 2000)
            nodes.append(AXNode(index: index, parent: index == 0 ? nil : 0, role: "text_field", attributes: attributes))
        }
        var metadata = original.metadata
        metadata["sourceTruncated"] = true
        let (cache, _) = try cache()
        let response = try cache.store(CapturedObservation(nodes: nodes, metadata: metadata, screenshot: original.screenshot))
        let text = response["text"] as! String
        XCTAssertLessThanOrEqual(text.utf8.count, 8192)
        XCTAssertLessThanOrEqual(text.split(separator: "\n").count, 60)
        XCTAssertTrue(text.contains("unexpanded="))
        XCTAssertTrue(text.contains("source_missing=true"))
        XCTAssertTrue(text.contains("detail_clipped=true"))
        XCTAssertTrue(text.contains("\\n\\\"quoted\\\""))
        var offset = 0
        var visited = 0
        repeat {
            let page = try cache.inspect(ObservationReference("o1"), offset: offset)["text"] as! String
            XCTAssertLessThanOrEqual(page.utf8.count, 8192)
            visited += page.split(separator: "\n").filter { $0.hasPrefix("[e") }.count
            if let line = page.split(separator: "\n").first(where: { $0.hasPrefix("more:") }),
               let range = line.range(of: "--offset ") {
                offset = Int(line[range.upperBound...].split(separator: " ")[0])!
            } else { break }
        } while offset < 200
        XCTAssertEqual(visited, 200)
        XCTAssertThrowsError(try cache.inspect(ObservationReference("o1:e201"), offset: 0))
        XCTAssertThrowsError(try cache.inspect(ObservationReference("o1"), offset: 200))
    }

    func testInvalidReferencesAndMalformedCapturedParentsAreRejected() throws {
        for invalid in ["o0", "o1:e0", "o1:e9999999999999999999999", "o1/../o2", "e1", "o1:e2:extra"] {
            XCTAssertThrowsError(try ObservationReference(invalid))
        }
        let capture = try observationFixture()
        var result = capture.metadata
        result["screenshotBase64"] = capture.screenshot.base64EncodedString()
        result["truncated"] = false
        var nodes = capture.nodes.map(\.attributes)
        nodes[1]["parent"] = 1
        result["nodes"] = nodes
        XCTAssertThrowsError(try XCTestCapture.decode(result))
    }

    func testScreenshotStillReturnedWhenAXIsUnavailable() throws {
        let original = try observationFixture()
        let capture = try XCTestCapture.decode(["screenshotBase64": original.screenshot.base64EncodedString(),
            "axStatus": "unavailable", "axError": "foreground_app_unknown", "scope": "unknown"])
        XCTAssertTrue(capture.nodes.isEmpty)
        let (cache, _) = try cache()
        let response = try cache.store(capture)
        XCTAssertTrue((response["text"] as! String).contains("ax=unavailable"))
        XCTAssertTrue((response["text"] as! String).contains("foreground=null"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: response["screenshot"] as! String))
        XCTAssertThrowsError(try cache.resolveCurrent(ObservationReference("o1:e1")))
    }
}
