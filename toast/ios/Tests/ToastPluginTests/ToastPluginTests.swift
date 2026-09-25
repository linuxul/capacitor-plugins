import XCTest
import UIKit
import WebKit
import Capacitor
@testable import ToastPlugin

final class ToastTests: XCTestCase {
    @MainActor
    func testShowWithoutTextIsRejected() async {
        let error = await showError(ToastPlugin(), options: [:])
        XCTAssertEqual(error?.message, "text must be provided and must be a string.")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testShowWithoutAViewControllerIsRejected() async {
        let error = await showError(ToastPlugin(), options: ["text": "Hello"])
        XCTAssertEqual(error?.message, "Unable to display toast!")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testShowReturnsOnceTheToastIsGone() async throws {
        let bridge = FakeBridge()
        let viewController = UIViewController()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        bridge.viewController = viewController
        let plugin = ToastPlugin()
        plugin.bridge = bridge

        // The method answers by returning: the call's own handlers must stay unused.
        try await plugin.show(makeCall(["text": "Hello", "position": "top"]))

        XCTAssertTrue(viewController.view.subviews.isEmpty, "the toast must have been removed when show returns")
    }

    /// The error `show` throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func showError(_ plugin: ToastPlugin, options: JSObject) async -> CAPPluginError? {
        do {
            try await plugin.show(makeCall(options))
            XCTFail("show must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func makeCall(_ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: "show", options: options, success: { _, _ in
            XCTFail("show answers by returning or throwing")
        }, error: { _ in
            XCTFail("show answers by returning or throwing")
        })
    }
}

/// A bridge with just enough behaviour for the plugin to find its view controller. Members it never uses trap.
private final class FakeBridge: CAPBridgeProtocol {
    var viewController: UIViewController?
    var webView: WKWebView?
    var isSimEnvironment = true
    var isDevEnvironment = true
    var userInterfaceStyle = UIUserInterfaceStyle.unspecified
    var autoRegisterPlugins = false
    var statusBarVisible = true
    var statusBarStyle = UIStatusBarStyle.default
    var statusBarAnimation = UIStatusBarAnimation.fade
    var config: InstanceConfiguration { fatalError("unused") }
    var notificationRouter: NotificationRouter { fatalError("unused") }

    func plugin(withName: String) -> CAPPlugin? { nil }
    func saveCall(_ call: CAPPluginCall) {}
    func savedCall(withID: String) -> CAPPluginCall? { nil }
    func releaseCall(_ call: CAPPluginCall) {}
    func releaseCall(withID: String) {}
    // swiftlint:disable identifier_name
    func evalWithPlugin(_ plugin: CAPPlugin, js: String) {}
    func eval(js: String) {}
    // swiftlint:enable identifier_name
    func triggerJSEvent(eventName: String, target: String) {}
    func triggerJSEvent(eventName: String, target: String, data: String) {}
    func triggerWindowJSEvent(eventName: String) {}
    func triggerWindowJSEvent(eventName: String, data: String) {}
    func triggerDocumentJSEvent(eventName: String) {}
    func triggerDocumentJSEvent(eventName: String, data: String) {}
    func localURL(fromWebURL webURL: URL?) -> URL? { webURL }
    func portablePath(fromLocalURL localURL: URL?) -> URL? { localURL }
    func setServerBasePath(_ path: String) {}
    func registerPluginType(_ pluginType: CAPPlugin.Type) {}
    func registerPluginInstance(_ pluginInstance: CAPPlugin) {}
    func showAlertWith(title: String, message: String, buttonTitle: String) {}
}
