import XCTest
import Capacitor
@testable import AppLauncherPlugin

final class AppLauncherPluginTests: XCTestCase {
    private let timeout: TimeInterval = 20

    @MainActor
    func testCanOpenUrlWithoutAUrlIsRejected() async {
        let error = await canOpenUrlError(options: [:])
        XCTAssertEqual(error?.message, "Must supply a URL")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testCanOpenUrlWithAnInvalidUrlIsRejected() async {
        let error = await canOpenUrlError(options: ["url": ""])
        XCTAssertEqual(error?.message, "Invalid URL")
        XCTAssertNil(error?.code)
    }

    func testOpenUrlWithoutAUrlIsRejected() {
        let settled = expectation(description: "openUrl settles")
        var rejection: String?
        AppLauncherPlugin().openUrl(CAPPluginCall(callbackId: "test", methodName: "openUrl", options: [:], success: { _, _ in
            settled.fulfill()
        }, error: { error in
            rejection = error.message
            settled.fulfill()
        }))
        wait(for: [settled], timeout: timeout)
        XCTAssertEqual(rejection, "Must supply a URL")
    }

    /// The error canOpenUrl throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func canOpenUrlError(options: JSObject) async -> CAPPluginError? {
        let call = CAPPluginCall(callbackId: "test", methodName: "canOpenUrl", options: options, success: { _, _ in
            XCTFail("canOpenUrl answers by returning or throwing")
        }, error: { _ in
            XCTFail("canOpenUrl answers by returning or throwing")
        })
        do {
            _ = try await AppLauncherPlugin().canOpenUrl(call)
            XCTFail("canOpenUrl must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }
}
