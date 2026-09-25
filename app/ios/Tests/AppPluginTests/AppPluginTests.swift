import XCTest
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
