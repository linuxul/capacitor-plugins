import XCTest
import Capacitor
@testable import AppLauncherPlugin

final class AppLauncherPluginTests: XCTestCase {
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

    @MainActor
    func testOpenUrlWithoutAUrlIsRejected() async {
        let error = await openUrlError(options: [:])
        XCTAssertEqual(error?.message, "Must supply a URL")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testOpenUrlWithAnInvalidUrlIsRejected() async {
        let error = await openUrlError(options: ["url": ""])
        XCTAssertEqual(error?.message, "Invalid URL")
        XCTAssertNil(error?.code)
    }

    /// The error openUrl throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func openUrlError(options: JSObject) async -> CAPPluginError? {
        let call = CAPPluginCall(callbackId: "test", methodName: "openUrl", options: options, success: { _, _ in
            XCTFail("openUrl answers by returning or throwing")
        }, error: { _ in
            XCTFail("openUrl answers by returning or throwing")
        })
        do {
            _ = try await AppLauncherPlugin().openUrl(call)
            XCTFail("openUrl must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
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
