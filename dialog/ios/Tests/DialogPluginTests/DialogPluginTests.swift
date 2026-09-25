import XCTest
import UIKit
import WebKit
import Capacitor
@testable import DialogPlugin

final class DialogPluginTests: XCTestCase {
    // Presentation and the release of a dismissed alert go through the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testTopmostPresenterIsTheRootWhenNothingIsPresented() {
        let root = FakePresentingController()
        XCTAssertTrue(DialogPlugin.topmostPresenter(from: root) === root)
    }

    func testTopmostPresenterWalksToTheLastPresentedController() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        let sheet = FakePresentingController()
        root.fakePresented = modal
        modal.fakePresented = sheet
        XCTAssertTrue(DialogPlugin.topmostPresenter(from: root) === sheet)
    }

    func testTopmostPresenterSkipsAControllerBeingDismissed() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        let dismissing = FakePresentingController()
        dismissing.fakeBeingDismissed = true
        root.fakePresented = modal
        modal.fakePresented = dismissing
        XCTAssertTrue(DialogPlugin.topmostPresenter(from: root) === modal)
    }

    func testTopmostPresenterOfNoRootIsNil() {
        XCTAssertNil(DialogPlugin.topmostPresenter(from: nil))
    }

    @MainActor
    func testEveryDialogRejectsWhenThereIsNothingToPresentFrom() async {
        for name in ["alert", "confirm", "prompt"] {
            let error = await thrownError(name, from: DialogPlugin(), ["message": "hello"])
            XCTAssertEqual(error?.message, "Unable to display the dialog: there is no view controller to present it from", name)
            XCTAssertNil(error?.code, name)
        }
    }

    @MainActor
    func testDialogWithoutAMessageIsRejected() async {
        for name in ["alert", "confirm", "prompt"] {
            let error = await thrownError(name, from: DialogPlugin(), [:])
            XCTAssertEqual(error?.message, "Please provide a message for the dialog", name)
            XCTAssertNil(error?.code, name)
        }
    }

    @MainActor
    func testEveryDialogRejectsWhenUIKitRefusesToPresent() async {
        // UIKit logs and does nothing when the presenter is mid-transition or not in a window; the call used to hang.
        let bridge = FakeBridge()
        let root = FakePresentingController()
        root.refusesPresentations = true
        bridge.viewController = root
        let plugin = DialogPlugin()
        plugin.bridge = bridge
        for name in ["alert", "confirm", "prompt"] {
            let error = await thrownError(name, from: plugin, ["message": "hello"])
            XCTAssertEqual(error?.message, "Unable to display the dialog: there is no view controller to present it from", name)
        }
    }

    @MainActor
    func testTheFirstAnswerCountsAndLaterOnesAreIgnored() async throws {
        let presenter = FakePresentingController()
        let answer = try await DialogPlugin.ask(over: presenter, dismissed: "dismissed") { answer in
            answer("first")
            answer("second")
            return UIAlertController(title: nil, message: "hello", preferredStyle: .alert)
        }
        XCTAssertEqual(answer, "first")
    }

    @MainActor
    func testAnAlertThatGoesAwayWithoutAnActionAnswersDismissed() async throws {
        let presenter = FakePresentingController()
        let asking = Task { @MainActor in
            try await DialogPlugin.ask(over: presenter, dismissed: "dismissed") { answer in
                let alert = UIAlertController(title: nil, message: "hello", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in answer("tapped") })
                return alert
            }
        }
        try await dismissPresentedAlert(of: presenter)
        let answer = try await asking.value
        XCTAssertEqual(answer, "dismissed")
    }

    @MainActor
    func testDismissedDialogsResolveWithTheCancelAnswer() async throws {
        let bridge = FakeBridge()
        let root = FakePresentingController()
        bridge.viewController = root
        let plugin = DialogPlugin()
        plugin.bridge = bridge

        let alerting = Task { @MainActor in try await plugin.alert(self.makeCall("alert", ["message": "hello"])) }
        let alert = try await dismissPresentedAlert(of: root)
        try await alerting.value
        XCTAssertEqual(alert.actionTitles, ["OK"])

        let confirming = Task { @MainActor in try await plugin.confirm(self.makeCall("confirm", ["message": "hello"])) }
        let confirm = try await dismissPresentedAlert(of: root)
        let confirmed = try await confirming.value
        XCTAssertEqual(confirm.actionTitles, ["Cancel", "OK"])
        XCTAssertEqual(confirmed["value"] as? Bool, false)

        let prompting = Task { @MainActor in
            try await plugin.prompt(self.makeCall("prompt", ["message": "hello", "inputText": "typed"]))
        }
        let prompt = try await dismissPresentedAlert(of: root)
        let prompted = try await prompting.value
        XCTAssertEqual(prompt.textFields, ["typed"])
        XCTAssertEqual(prompted["value"] as? String, "")
        XCTAssertEqual(prompted["cancelled"] as? Bool, true)
    }

    func testOnceContinuationResumesOnlyWithTheFirstValue() async {
        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            let once = OnceContinuation(continuation, fallback: 0)
            XCTAssertTrue(once.resume(returning: 1))
            XCTAssertFalse(once.resume(returning: 2))
        }
        XCTAssertEqual(value, 1)
    }

    func testOnceContinuationReleasedWithoutAnswerResumesWithTheFallback() async {
        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            _ = OnceContinuation(continuation, fallback: 7)
        }
        XCTAssertEqual(value, 7)
    }

    /// Waits until `presenter` shows an alert, then drops it the way a dismissal by other code would. Returns what the
    /// alert showed, without keeping the alert: its release is what answers the dialog.
    @MainActor
    @discardableResult
    private func dismissPresentedAlert(of presenter: FakePresentingController) async throws -> ShownAlert {
        let deadline = Date().addingTimeInterval(timeout)
        while presenter.fakePresented == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let alert = try XCTUnwrap(presenter.fakePresented as? UIAlertController)
        presenter.fakePresented = nil
        return ShownAlert(actionTitles: alert.actions.map(\.title), textFields: alert.textFields?.map(\.text) ?? [])
    }

    /// The error the dialog method `name` throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func thrownError(_ name: String, from plugin: DialogPlugin, _ options: JSObject) async -> CAPPluginError? {
        let call = makeCall(name, options)
        do {
            switch name {
            case "alert":
                try await plugin.alert(call)
            case "confirm":
                _ = try await plugin.confirm(call)
            default:
                _ = try await plugin.prompt(call)
            }
            XCTFail("\(name) must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func makeCall(_ method: String, _ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test-\(method)", methodName: method, options: options, success: { _, _ in
            XCTFail("\(method) answers by returning or throwing")
        }, error: { _ in
            XCTFail("\(method) answers by returning or throwing")
        })
    }
}

/// What an alert showed.
private struct ShownAlert {
    let actionTitles: [String?]
    let textFields: [String?]
}

/// A controller whose presentation state the test sets, since real presentation needs a window and an app. It keeps
/// what it is asked to present, the way UIKit does while a controller is on screen, unless it refuses presentations.
private final class FakePresentingController: UIViewController {
    var fakePresented: UIViewController?
    var fakeBeingDismissed = false
    var refusesPresentations = false

    override var presentedViewController: UIViewController? {
        return fakePresented
    }

    override var isBeingDismissed: Bool {
        return fakeBeingDismissed
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        guard !refusesPresentations else {
            return
        }
        fakePresented = viewControllerToPresent
        completion?()
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
