import XCTest
import UIKit
import Capacitor
@testable import AppPlugin

final class AppPluginTests: XCTestCase {
    private let timeout: TimeInterval = 20

    func testLaunchUrlResultCarriesTheUrl() throws {
        let url = try XCTUnwrap(URL(string: "myapp://open/page?id=1"))
        XCTAssertEqual(AppPlugin.launchUrlResult(url)?["url"] as? String, "myapp://open/page?id=1")
    }

    func testLaunchUrlResultIsEmptyWithoutAUrl() {
        XCTAssertNil(AppPlugin.launchUrlResult(nil))
    }

    func testUrlOpenObjectReadsTheOptionsAsTheRuntimePostsThem() throws {
        // The application and scene delegate proxies post the options keyed by UIApplication.OpenURLOptionsKey.
        let url = try XCTUnwrap(URL(string: "myapp://open/page"))
        let options: [UIApplication.OpenURLOptionsKey: Any] = [.sourceApplication: "com.example.source", .openInPlace: true]
        let object = try postedObject(Notification(name: .capacitorOpenURL, object: ["url": url, "options": options]))

        let result = AppPlugin().makeUrlOpenObject(object)

        XCTAssertEqual(result["url"] as? String, "myapp://open/page")
        XCTAssertEqual(result["iosSourceApplication"] as? String, "com.example.source")
        XCTAssertEqual(result["iosOpenInPlace"] as? Bool, true)
    }

    func testUrlOpenObjectFromTheApplicationDelegateReadsABridgedOpenInPlace() throws {
        // UIKit hands the application delegate an Obj-C dictionary, whose Boolean values are NSNumbers.
        let url = try XCTUnwrap(URL(string: "myapp://open"))
        let options: [UIApplication.OpenURLOptionsKey: Any] = [.openInPlace: NSNumber(value: true)]
        let object = try postedObject(Notification(name: .capacitorOpenURL, object: ["url": url, "options": options]))

        XCTAssertEqual(AppPlugin().makeUrlOpenObject(object)["iosOpenInPlace"] as? Bool, true)
    }

    func testUniversalLinkObjectHasTheUrlAndDefaultOptions() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let object = try postedObject(Notification(name: .capacitorOpenUniversalLink, object: ["url": url]))

        let result = AppPlugin().makeUrlOpenObject(object)

        XCTAssertEqual(result["url"] as? String, "https://example.com/page")
        XCTAssertEqual(result["iosSourceApplication"] as? String, "")
        XCTAssertEqual(result["iosOpenInPlace"] as? Bool, false)
    }

    /// The notification object as the plugin's observers read it.
    private func postedObject(_ notification: Notification) throws -> [String: Any?] {
        return try XCTUnwrap(notification.object as? [String: Any?])
    }

    func testGetLaunchUrlSettlesOnce() {
        let settled = expectation(description: "getLaunchUrl settles")
        settled.assertForOverFulfill = true
        let call = CAPPluginCall(callbackId: "test", methodName: "getLaunchUrl", options: [:], success: { _, _ in
            settled.fulfill()
        }, error: { _ in
            XCTFail("getLaunchUrl must not reject")
        })

        AppPlugin().getLaunchUrl(call)

        wait(for: [settled], timeout: timeout)
    }

    func testGetAppLanguageResolvesWithAString() {
        let settled = expectation(description: "getAppLanguage settles")
        var value: Any?
        let call = CAPPluginCall(callbackId: "test", methodName: "getAppLanguage", options: [:], success: { result, _ in
            value = result.data?["value"]
            settled.fulfill()
        }, error: { _ in
            XCTFail("getAppLanguage must not reject")
        })

        AppPlugin().getAppLanguage(call)

        wait(for: [settled], timeout: timeout)
        XCTAssertNotNil(value as? String)
    }
}
