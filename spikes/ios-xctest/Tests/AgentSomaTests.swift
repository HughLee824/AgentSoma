import XCTest

final class AgentSomaTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func save(_ name: String, app: XCUIApplication) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentSomaEvidence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        try app.debugDescription.write(to: directory.appendingPathComponent(name + ".tree.txt"), atomically: true, encoding: .utf8)
        let elements = app.descendants(matching: .any).allElementsBoundByIndex.prefix(100).map { element in
            let frame = element.frame
            return [
                "type": element.elementType.rawValue,
                "identifier": element.identifier,
                "label": element.label,
                "value": element.value ?? NSNull(),
                "enabled": element.isEnabled,
                "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: ["appState": app.state.rawValue, "elements": elements], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name + ".json"))
        print("AGENTSOMA_EVIDENCE \(name) elements=\(elements.count)")
    }

    @MainActor
    func test01ObservationAndTap() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["increment"].waitForExistence(timeout: 5))
        app.buttons["increment"].tap()
        XCTAssertEqual(app.staticTexts["counter"].label, "Count: 1")
        try save("fixture-tap", app: app)
    }

    @MainActor
    func test02Text() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("AgentSoma hello")
        XCTAssertEqual(field.value as? String, "AgentSoma hello")
        field.typeText(" 你好")
        XCTAssertEqual(field.value as? String, "AgentSoma hello 你好")
        app.buttons["dismiss"].tap()
        try save("fixture-text", app: app)
    }

    @MainActor
    func test03Swipe() throws {
        let app = XCUIApplication()
        app.launch()
        let last = app.staticTexts["row-39"]
        XCTAssertFalse(last.isHittable)
        for _ in 0..<8 {
            if last.isHittable { break }
            app.scrollViews["scroll"].swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        try save("fixture-swipe", app: app)
    }

    @MainActor
    func test04Calculator() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        app.launch()
        for identifier in ["AllClear", "Two", "Add", "Three", "Equals"] {
            let key = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5), "Missing calculator key \(identifier)")
            key.tap()
        }
        try save("calculator-result", app: app)
    }

    @MainActor
    func test05TextEditingPrimitives() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let beforeFocus = field.hasFocus
        field.tap()
        let afterFocus = field.hasFocus
        print("AGENTSOMA_INPUT_FOCUS before=\(beforeFocus) after=\(afterFocus)")
        field.typeText("ABCDE")
        field.typeKey(.leftArrow, modifierFlags: [])
        field.typeKey(.leftArrow, modifierFlags: [])
        field.typeText("北京")
        XCTAssertEqual(field.value as? String, "ABC北京DE")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("👩‍💻e\u{301} replacement")
        XCTAssertEqual(field.value as? String, "👩‍💻e\u{301} replacement")
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText("Final")
        XCTAssertEqual(field.value as? String, "Final")
        try save("input-primitives", app: app)
    }
}
