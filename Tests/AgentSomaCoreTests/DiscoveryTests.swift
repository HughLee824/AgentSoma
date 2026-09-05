import XCTest
@testable import AgentSomaCore

final class DiscoveryTests: XCTestCase {
    func testDeviceIDsAndConnectionFactsDoNotInventReadiness() throws {
        let result = try DeviceDiscovery.devices(from: ["devices": [
            ["identifier": "core-z", "hardwareProperties": ["udid": "udid-z", "platform": "iOS", "deviceType": "iPhone"],
             "deviceProperties": ["name": "Phone", "osVersionNumber": "26.6"],
             "connectionProperties": ["transportType": "wired", "tunnelState": "disconnected", "pairingState": "paired"]],
            ["identifier": "core-a"]
        ]])
        XCTAssertEqual(result.map { $0["id"] as! String }, ["core-a", "udid-z"])
        XCTAssertTrue(result[0]["osVersion"] is NSNull)
        XCTAssertTrue((result[0]["connection"] as! [String: Any])["transport"] is NSNull)
        XCTAssertEqual((result[1]["connection"] as! [String: Any])["tunnelState"] as? String, "disconnected")
        XCTAssertNil(result[1]["ready"])
        XCTAssertNoThrow(try jsonData(["devices": result]))
    }

    func testMalformedDiscoveryIsNotAnEmptyInventory() throws {
        XCTAssertThrowsError(try DeviceDiscovery.devices(from: [:]))
        XCTAssertThrowsError(try DeviceDiscovery.devices(from: ["devices": [[:]]]))
        XCTAssertThrowsError(try AppCatalog([:]))
        XCTAssertThrowsError(try AppCatalog(["apps": [["name": "Missing ID"]]]))
        XCTAssertTrue(try DeviceDiscovery.devices(from: ["devices": []]).isEmpty)
        XCTAssertEqual(try AppCatalog(["apps": []]).page(query: nil, offset: 0)["total"] as? Int, 0)
    }

    func testAppPagesAreBoundedSortedAndFilteredWithoutLosingUnknownNames() throws {
        let rows: [[String: Any]] = (0..<53).reversed().map {
            ["bundleIdentifier": String(format: "com.example.app%02d", $0), "name": "示例 App \($0)"]
        } + [["bundleIdentifier": "org.example.unnamed"]]
        let catalog = try AppCatalog(["apps": rows])
        let first = try catalog.page(query: nil, offset: 0)
        let second = try catalog.page(query: nil, offset: first["nextOffset"] as! Int)
        let apps = (first["apps"] as! [[String: Any]]) + (second["apps"] as! [[String: Any]])
        XCTAssertEqual((first["apps"] as! [[String: Any]]).count, 50)
        XCTAssertEqual(first["total"] as? Int, 54)
        XCTAssertEqual(apps.map { $0["bundleId"] as! String }, rows.compactMap { $0["bundleIdentifier"] as? String }.sorted())
        XCTAssertTrue(apps.last?["name"] is NSNull)
        XCTAssertTrue(second["nextOffset"] is NSNull)
        XCTAssertEqual(try catalog.page(query: "COM.EXAMPLE.APP", offset: 0)["total"] as? Int, 53)
        XCTAssertEqual(try catalog.page(query: "示例 App 52", offset: 0)["total"] as? Int, 1)
        XCTAssertEqual(try catalog.page(query: "absent", offset: 0)["total"] as? Int, 0)
        XCTAssertEqual((try catalog.page(query: nil, offset: 54)["apps"] as! [[String: Any]]).count, 0)
        XCTAssertThrowsError(try catalog.page(query: nil, offset: 55))
        XCTAssertThrowsError(try catalog.page(query: nil, offset: -1))
    }

    func testInstalledCheckUsesExactBundleIDWithoutAnAppWhitelist() throws {
        let catalog = try AppCatalog(["apps": [["bundleIdentifier": "org.example.thirdparty", "name": "Third Party"]]])
        XCTAssertNoThrow(try catalog.requireInstalled("org.example.thirdparty"))
        for bundle in ["Third Party", "org.example", "ORG.EXAMPLE.THIRDPARTY", "com.apple.calculator"] {
            XCTAssertThrowsError(try catalog.requireInstalled(bundle)) {
                XCTAssertEqual(($0 as? SomaError)?.code, "app_not_installed")
            }
        }
    }
}
