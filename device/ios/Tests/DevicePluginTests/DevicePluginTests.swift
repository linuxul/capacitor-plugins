import XCTest
import UIKit
import Capacitor
@testable import DevicePlugin

final class DevicePluginTests: XCTestCase {
    @MainActor
    func testGetInfoReturnsTheDeviceInfo() async throws {
        let info = await DevicePlugin().getInfo(unansweredCall("getInfo"))

        XCTAssertEqual(info["operatingSystem"] as? String, "ios")
        XCTAssertEqual(info["platform"] as? String, "ios")
        XCTAssertEqual(info["manufacturer"] as? String, "Apple")
        XCTAssertEqual(info["osVersion"] as? String, UIDevice.current.systemVersion)
        XCTAssertEqual(info["webViewVersion"] as? String, UIDevice.current.systemVersion)
        XCTAssertEqual(info["name"] as? String, UIDevice.current.name)
        XCTAssertEqual(info["isVirtual"] as? Bool, true, "the tests run in the simulator")
        XCTAssertNotNil(info["model"] as? String)
        XCTAssertGreaterThan(try XCTUnwrap(info["iOSVersion"] as? Int), 170000)
        let memUsed = try XCTUnwrap(info["memUsed"] as? NSNumber)
        XCTAssertGreaterThan(memUsed.uint64Value, 0)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(info as [String: Any]), "the bridge sends the result as JSON")
    }

    @MainActor
    func testGetBatteryInfoLeavesBatteryMonitoringOff() async {
        let info = await DevicePlugin().getBatteryInfo(unansweredCall("getBatteryInfo"))

        XCTAssertNotNil(info["batteryLevel"] as? Float)
        XCTAssertNotNil(info["isCharging"] as? Bool)
        XCTAssertFalse(UIDevice.current.isBatteryMonitoringEnabled)
    }

    @MainActor
    func testGetIdReturnsTheVendorIdentifierOrThrows() async {
        do {
            let result = try await DevicePlugin().getId(unansweredCall("getId"))
            XCTAssertEqual(result["identifier"] as? String, UIDevice.current.identifierForVendor?.uuidString)
        } catch let error as CAPPluginError {
            // The test runner may have no vendor identifier: the bridge then rejects with this error.
            XCTAssertNil(UIDevice.current.identifierForVendor)
            XCTAssertEqual(error.message, "Id not available")
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    private func unansweredCall(_ method: String) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: method, options: [:], success: { _, _ in
            XCTFail("\(method) answers by returning or throwing")
        }, error: { _ in
            XCTFail("\(method) answers by returning or throwing")
        })
    }
}
