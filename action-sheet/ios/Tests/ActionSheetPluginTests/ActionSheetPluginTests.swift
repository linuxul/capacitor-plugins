import XCTest
import UIKit
import WebKit
import Capacitor
@testable import ActionSheetPlugin

final class ActionSheetPluginTests: XCTestCase {
    // Presentation and the release of a dismissed sheet go through the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testTopmostPresenterIsTheRootWhenNothingIsPresented() {
        let root = FakePresentingController()
        XCTAssertTrue(ActionSheetPlugin.topmostPresenter(from: root) === root)
    }

    func testTopmostPresenterWalksToTheLastPresentedController() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        let sheet = FakePresentingController()
        root.fakePresented = modal
        modal.fakePresented = sheet
        XCTAssertTrue(ActionSheetPlugin.topmostPresenter(from: root) === sheet)
    }

    func testTopmostPresenterSkipsAControllerBeingDismissed() {
        let root = FakePresentingController()
        let dismissing = FakePresentingController()
        dismissing.fakeBeingDismissed = true
        root.fakePresented = dismissing
        XCTAssertTrue(ActionSheetPlugin.topmostPresenter(from: root) === root)
    }

    func testCenterPopoverAnchorsToThePresentersView() {
        let presenter = UIViewController()
        presenter.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let controller = UIViewController()
        controller.modalPresentationStyle = .popover

        ActionSheetPlugin.centerPopover(controller, on: presenter)

        let popover = controller.popoverPresentationController
        XCTAssertTrue(popover?.sourceView === presenter.view)
        XCTAssertEqual(popover?.sourceRect, CGRect(x: 100, y: 50, width: 0, height: 0))
        XCTAssertEqual(popover?.permittedArrowDirections, [])
    }

    @MainActor
    func testShowActionsRejectsWhenThereIsNothingToPresentFrom() async {
        let error = await thrownError(ActionSheetPlugin(), ["options": [["title": "One"]]])
        XCTAssertEqual(error?.message, "Unable to display the action sheet: there is no view controller to present it from")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testShowActionsRejectsWhenUIKitRefusesToPresent() async {
        // UIKit logs and does nothing when the presenter is mid-transition or not in a window; the call used to hang.
        let harness = makePlugin()
        let (plugin, root) = (harness.plugin, harness.root)
        root.refusesPresentations = true
        let error = await thrownError(plugin, ["options": [["title": "One"]]])
        XCTAssertEqual(error?.message, "Unable to display the action sheet: there is no view controller to present it from")
    }

    @MainActor
    func testASheetThatGoesAwayWithoutAChoiceIsCanceled() async throws {
        let harness = makePlugin()
        let (plugin, root) = (harness.plugin, harness.root)
        let options: JSArray = [["title": "One"], ["title": "Delete", "style": "DESTRUCTIVE"], ["title": "Cancel", "style": "CANCEL"]]
        let showing = Task { @MainActor in try await plugin.showActions(self.makeCall(["title": "Pick", "options": options])) }

        let shown = try await dismissPresentedSheet(of: root)
        let result = try await showing.value

        XCTAssertEqual(shown.title, "Pick")
        XCTAssertEqual(shown.actions.map(\.title), ["One", "Delete", "Cancel"])
        XCTAssertEqual(shown.actions.map(\.style), [.default, .destructive, .cancel])
        XCTAssertEqual(result["index"] as? Int, -1)
        XCTAssertEqual(result["canceled"] as? Bool, true)
    }

    @MainActor
    func testASheetWithoutOptionsIsCanceledWhenItGoesAway() async throws {
        // Nothing but the sheet itself keeps the answer: it must not be given before the sheet goes away.
        let harness = makePlugin()
        let (plugin, root) = (harness.plugin, harness.root)
        let answered = Flag()
        let showing = Task { @MainActor in
            defer { answered.isSet = true }
            return try await plugin.showActions(self.makeCall(["message": "Nothing to pick"]))
        }

        _ = try await presentedSheet(of: root)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(answered.isSet, "the call must wait while the sheet is on screen")
        try await dismissPresentedSheet(of: root)
        let result = try await showing.value

        XCTAssertEqual(result["index"] as? Int, -1)
        XCTAssertEqual(result["canceled"] as? Bool, true)
    }

    @MainActor
    func testADismissalReportedByUIKitCancelsTheSheet() async throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("the presentation controller delegate is only used on iOS 26")
        }
        let harness = makePlugin()
        let (plugin, root) = (harness.plugin, harness.root)
        let showing = Task { @MainActor in try await plugin.showActions(self.makeCall(["options": [["title": "One"]]])) }

        let sheet = try await presentedSheet(of: root)
        let presentationController = try XCTUnwrap(sheet.presentationController)
        XCTAssertTrue(presentationController.delegate === plugin)
        plugin.presentationControllerDidDismiss(presentationController)
        plugin.presentationControllerDidDismiss(presentationController)
        let result = try await showing.value

        XCTAssertEqual(result["index"] as? Int, -1)
        XCTAssertEqual(result["canceled"] as? Bool, true)
        root.fakePresented = nil
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

    // MARK: - Helpers

    @MainActor
    private func makePlugin() -> Harness {
        let bridge = FakeBridge()
        let root = FakePresentingController()
        bridge.viewController = root
        let plugin = ActionSheetPlugin()
        plugin.bridge = bridge
        return Harness(plugin: plugin, root: root, bridge: bridge)
    }

    /// Waits until `presenter` shows a sheet.
    @MainActor
    private func presentedSheet(of presenter: FakePresentingController) async throws -> UIAlertController {
        let deadline = Date().addingTimeInterval(timeout)
        while presenter.fakePresented == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(presenter.fakePresented as? UIAlertController)
    }

    /// Waits until `presenter` shows a sheet, then drops it the way a dismissal by other code would. Returns what the
    /// sheet showed, without keeping the sheet: its release is what answers the call.
    @MainActor
    @discardableResult
    private func dismissPresentedSheet(of presenter: FakePresentingController) async throws -> ShownSheet {
        let sheet = try await presentedSheet(of: presenter)
        presenter.fakePresented = nil
        return ShownSheet(title: sheet.title, actions: sheet.actions.map { ($0.title, $0.style) })
    }

    /// The error showActions throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func thrownError(_ plugin: ActionSheetPlugin, _ options: JSObject) async -> CAPPluginError? {
        do {
            _ = try await plugin.showActions(makeCall(options))
            XCTFail("showActions must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func makeCall(_ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: "showActions", options: options, success: { _, _ in
            XCTFail("showActions answers by returning or throwing")
        }, error: { _ in
            XCTFail("showActions answers by returning or throwing")
        })
    }
}

/// A plugin whose bridge shows `root`. The plugin's bridge is weak: the harness keeps it.
private struct Harness {
    let plugin: ActionSheetPlugin
    let root: FakePresentingController
    let bridge: FakeBridge
}

/// A flag a task sets.
private final class Flag: @unchecked Sendable {
    var isSet = false
}

/// What a sheet showed.
private struct ShownSheet {
    let title: String?
    let actions: [(title: String?, style: UIAlertAction.Style)]
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
