import XCTest
import UIKit
import WebKit
import Capacitor
@testable import StatusBarPlugin

final class StatusBarPluginTests: XCTestCase {
    // Some calls settle from the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testStatusBarDoesNotKeepTheBridgeAlive() {
        weak var weakBridge: FakeBridge?
        var statusBar: StatusBar?
        autoreleasepool {
            let bridge = FakeBridge()
            weakBridge = bridge
            statusBar = StatusBar(bridge: bridge, config: StatusBarConfig())
        }
        XCTAssertNotNil(statusBar)
        XCTAssertNil(weakBridge, "StatusBar must not retain the bridge that owns its plugin")
    }

    func testSetBackgroundColorWithoutAColorIsRejected() {
        XCTAssertEqual(settle(StatusBarPlugin().setBackgroundColor, "setBackgroundColor", [:]), .rejected("Color must be provided"))
    }

    func testSetBackgroundColorWithAnInvalidColorIsRejected() {
        XCTAssertEqual(settle(StatusBarPlugin().setBackgroundColor, "setBackgroundColor", ["color": "blue"]),
                       .rejected("Invalid color provided. Must be a hex string (ex: #ff0000)"))
    }

    func testSetBackgroundColorWithAValidColorResolves() {
        XCTAssertEqual(settle(StatusBarPlugin().setBackgroundColor, "setBackgroundColor", ["color": "#FF0000"]), .resolved)
    }

    func testSetOverlaysWebViewWithoutOverlayResolvesLikeAndroid() {
        XCTAssertEqual(settle(StatusBarPlugin().setOverlaysWebView, "setOverlaysWebView", [:]), .resolved)
    }

    func testGetInfoWithoutAStatusBarIsRejected() {
        XCTAssertEqual(settle(StatusBarPlugin().getInfo, "getInfo", [:]),
                       .rejected("Unable to get the status bar info: the status bar is not available"))
    }

    func testInfoWithMissingFieldsFallsBackInsteadOfCrashing() {
        let dict = StatusBarPlugin.toDict(StatusBarInfo())
        XCTAssertEqual(dict["visible"] as? Bool, true)
        XCTAssertEqual(dict["style"] as? String, "DEFAULT")
        XCTAssertEqual(dict["color"] as? String, "")
        XCTAssertEqual(dict["overlays"] as? Bool, true)
        XCTAssertEqual(dict["height"] as? CGFloat, 0)
    }

    func testInfoKeepsTheFieldsThatArePresent() {
        let info = StatusBarInfo(overlays: false, visible: false, style: "DARK", color: "#112233", height: 47)
        let dict = StatusBarPlugin.toDict(info)
        XCTAssertEqual(dict["visible"] as? Bool, false)
        XCTAssertEqual(dict["style"] as? String, "DARK")
        XCTAssertEqual(dict["color"] as? String, "#112233")
        XCTAssertEqual(dict["overlays"] as? Bool, false)
        XCTAssertEqual(dict["height"] as? CGFloat, 47)
    }

    private enum Outcome: Equatable {
        case resolved
        case rejected(String)
    }

    private func settle(_ method: (CAPPluginCall) -> Void, _ name: String, _ options: JSObject) -> Outcome? {
        let settled = expectation(description: "\(name) settles")
        var outcome: Outcome?
        method(CAPPluginCall(callbackId: "test", methodName: name, options: options, success: { _, _ in
            outcome = .resolved
            settled.fulfill()
        }, error: { error in
            outcome = .rejected(error.message)
            settled.fulfill()
        }))
        wait(for: [settled], timeout: timeout)
        return outcome
    }
}

/// A bridge with just enough behaviour for StatusBar to be created. Members StatusBar never uses trap.
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
