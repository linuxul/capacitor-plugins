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

    func testSetBackgroundColorThrowsWithoutCode() {
        let call = CAPPluginCall(callbackId: "test", methodName: "setBackgroundColor", options: [:], success: { _, _ in
            XCTFail("setBackgroundColor must not resolve")
        }, error: { _ in
            XCTFail("setBackgroundColor answers by throwing")
        })
        XCTAssertThrowsError(try StatusBarPlugin().setBackgroundColor(call)) { error in
            XCTAssertEqual((error as? CAPPluginError)?.message, "Color must be provided")
            XCTAssertNil((error as? CAPPluginError)?.code)
        }
    }

    func testSetOverlaysWebViewWithoutOverlayResolvesLikeAndroid() {
        XCTAssertEqual(settle(StatusBarPlugin().setOverlaysWebView, "setOverlaysWebView", [:]), .resolved)
    }

    @MainActor
    func testGetInfoWithoutAStatusBarIsRejected() async {
        // getInfo is an async method: the bridge rejects the call with the error it throws.
        let call = CAPPluginCall(callbackId: "test", methodName: "getInfo", options: [:], success: { _, _ in
            XCTFail("getInfo must not resolve")
        }, error: { _ in
            XCTFail("getInfo answers by throwing")
        })
        do {
            _ = try await StatusBarPlugin().getInfo(call)
            XCTFail("getInfo must throw")
        } catch let error as CAPPluginError {
            XCTAssertEqual(error.message, "Unable to get the status bar info: the status bar is not available")
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testInfoWithMissingFieldsFallsBackInsteadOfCrashing() {
        let dict = StatusBarPlugin.toDict(StatusBarInfo())
        XCTAssertEqual(dict["visible"] as? Bool, true)
        XCTAssertEqual(dict["style"] as? String, "DEFAULT")
        XCTAssertEqual(dict["color"] as? String, "")
        XCTAssertEqual(dict["overlays"] as? Bool, true)
        XCTAssertEqual(dict["height"] as? CGFloat, 0)
    }

    func testGetInfoResultHasTheFieldsOfTheEvents() throws {
        let info = StatusBarInfo(overlays: false, visible: true, style: "LIGHT", color: "#AABBCC", height: 54)
        let object = StatusBarPlugin.toJSObject(info)
        XCTAssertEqual(object["visible"] as? Bool, true)
        XCTAssertEqual(object["style"] as? String, "LIGHT")
        XCTAssertEqual(object["color"] as? String, "#AABBCC")
        XCTAssertEqual(object["overlays"] as? Bool, false)
        XCTAssertEqual((object["height"] as? NSNumber)?.doubleValue, 54)
        let json = try JSONSerialization.data(withJSONObject: object as [String: Any])
        let eventJson = try JSONSerialization.data(withJSONObject: StatusBarPlugin.toDict(info))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: json) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: eventJson) as? NSDictionary)
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

    /// Calls `method` as the bridge does: an error it throws rejects the call.
    private func settle(_ method: (CAPPluginCall) throws -> Void, _ name: String, _ options: JSObject) -> Outcome? {
        let settled = expectation(description: "\(name) settles")
        var outcome: Outcome?
        let call = CAPPluginCall(callbackId: "test", methodName: name, options: options, success: { _, _ in
            outcome = .resolved
            settled.fulfill()
        }, error: { error in
            outcome = .rejected(error.message)
            settled.fulfill()
        })
        do {
            try method(call)
        } catch {
            call.reject(error)
        }
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
