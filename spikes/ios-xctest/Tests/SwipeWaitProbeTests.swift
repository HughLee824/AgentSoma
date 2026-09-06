import XCTest
import Darwin
import MachO

final class SwipeWaitProbeTests: XCTestCase {
    private var expectedIssues: [String]?

    override func record(_ issue: XCTIssue) {
        if expectedIssues != nil { expectedIssues?.append(issue.compactDescription) }
        else { super.record(issue) }
    }

    @MainActor
    func test01Baseline() throws { try probe(disableSpindump: false) }

    @MainActor
    func test02Disabled() throws { try probe(disableSpindump: true) }

    @MainActor
    func test03XCTestErrorRestoresConfiguration() throws {
        continueAfterFailure = true
        let symbols = UnsafeMutableRawPointer(bitPattern: -2)
        typealias Getter = @convention(c) () -> Double
        typealias Setter = @convention(c) (Double) -> Void
        let get = unsafeBitCast(try XCTUnwrap(dlsym(symbols, "_XCTApplicationStateTimeout")), to: Getter.self)
        let set = unsafeBitCast(try XCTUnwrap(dlsym(symbols, "_XCTSetApplicationStateTimeout")), to: Setter.self)
        let app = XCUIApplication(bundleIdentifier: "com.somnus.agentsoma.spike.fixture")
        app.launch()
        let previousTimeout = get()
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        expectedIssues = []
        XCTestDiagnostics.withoutAutomaticSpindump {
            set(1)
            defer { set(previousTimeout) }
            app.buttons["deliberately-missing-swipe-wait-probe"].tap()
        }
        let issues = expectedIssues ?? []
        expectedIssues = nil // All following assertions and recovery input must fail normally.
        XCTAssertFalse(issues.isEmpty, "The input API must still report its XCTest error")
        XCTAssertEqual(get(), previousTimeout)
        XCTAssertEqual(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain) as NSDictionary,
                       previousArguments as NSDictionary)
        app.buttons["increment"].tap()
        XCTAssertEqual(app.staticTexts["counter"].label, "Count: 1")
        let data = try JSONSerialization.data(withJSONObject: ["issues": issues,
            "runtimeImages": runtimeImages(), "recoveryCounter": app.staticTexts["counter"].label], options: [.sortedKeys])
        print("AGENTSOMA_XCTEST_ERROR_PROBE \(String(decoding: data, as: UTF8.self))")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "xctest-error-recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func probe(disableSpindump: Bool) throws {
        continueAfterFailure = true
        let symbols = UnsafeMutableRawPointer(bitPattern: -2)
        typealias Getter = @convention(c) () -> Double
        typealias Setter = @convention(c) (Double) -> Void
        let get = unsafeBitCast(try XCTUnwrap(dlsym(symbols, "_XCTApplicationStateTimeout")), to: Getter.self)
        let set = unsafeBitCast(try XCTUnwrap(dlsym(symbols, "_XCTSetApplicationStateTimeout")), to: Setter.self)
        let app = XCUIApplication(bundleIdentifier: "com.somnus.agentsoma.spike.fixture")
        app.launchArguments = ["--scroll-wait-probe"]
        app.launch()
        let frame = app.scrollViews["scroll"].frame
        XCTAssertGreaterThan(frame.height, 250)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.60))
        let end = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.60 - 130))
        let previousTimeout = get()
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let began = ProcessInfo.processInfo.systemUptime
        func input() {
            set(1)
            defer { set(previousTimeout) }
            start.press(forDuration: 0, thenDragTo: end)
        }
        if disableSpindump { XCTestDiagnostics.withoutAutomaticSpindump { input() } }
        else { input() }
        let finished = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(get(), previousTimeout)
        XCTAssertEqual(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain) as NSDictionary,
                       previousArguments as NSDictionary)
        var stability = FrameStability(startedAt: ProcessInfo.processInfo.systemUptime)
        while stability.remaining(at: ProcessInfo.processInfo.systemUptime) > 0 {
            let screenshot = XCUIScreen.main.screenshot()
            let captured = ProcessInfo.processInfo.systemUptime
            let hash = try FrameFingerprint(png: screenshot.pngRepresentation).hash
            stability.record(hash: hash, capturedAt: captured, processedAt: ProcessInfo.processInfo.systemUptime)
            if stability.stable { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        XCTAssertTrue(stability.stable)
        let result: [String: Any] = ["disableSpindump": disableSpindump, "inputBegan": began,
            "inputFinished": finished, "inputMs": (finished - began) * 1000,
            "stability": stability.result, "runtimeImages": runtimeImages()]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("AGENTSOMA_SWIPE_PROBE \(String(decoding: data, as: UTF8.self))")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = disableSpindump ? "swipe-disabled" : "swipe-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runtimeImages() -> [[String: String]] {
        (0..<_dyld_image_count()).compactMap { index in
            guard let name = _dyld_get_image_name(index), let header = _dyld_get_image_header(index) else { return nil }
            let path = String(cString: name)
            guard path.contains("/XCUIAutomation.framework/") || path.contains("/XCTestCore.framework/") else { return nil }
            var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == LC_UUID {
                    let uuid = command.load(as: uuid_command.self).uuid
                    return ["path": path, "uuid": UUID(uuid: uuid).uuidString]
                }
                command = command.advanced(by: Int(load.cmdsize))
            }
            return ["path": path]
        }
    }
}
