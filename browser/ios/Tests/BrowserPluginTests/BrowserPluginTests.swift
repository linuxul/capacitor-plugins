import XCTest
import UIKit
import SafariServices
import WebKit
import Capacitor
@testable import BrowserPlugin

final class BrowserPluginTests: XCTestCase {
    func testTopmostPresenterWalksToTheLastPresentedController() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        root.fakePresented = modal
        XCTAssertTrue(CAPBrowserPlugin.topmostPresenter(from: root) === modal)
        XCTAssertNil(CAPBrowserPlugin.topmostPresenter(from: nil))
    }

    func testTopmostPresenterSkipsAControllerBeingDismissed() {
        let root = FakePresentingController()
        let dismissing = FakePresentingController()
        dismissing.fakeBeingDismissed = true
        root.fakePresented = dismissing
        XCTAssertTrue(CAPBrowserPlugin.topmostPresenter(from: root) === root)
    }

    func testCenterPopoverAnchorsToThePresentersViewAndAppliesTheSize() {
        let presenter = UIViewController()
        presenter.view.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let controller = UIViewController()
        controller.modalPresentationStyle = .popover

        CAPBrowserPlugin.centerPopover(controller, on: presenter, size: CGSize(width: 120, height: 80))

        let popover = controller.popoverPresentationController
        XCTAssertTrue(popover?.sourceView === presenter.view)
        XCTAssertEqual(popover?.sourceRect, CGRect(x: 150, y: 200, width: 0, height: 0))
        XCTAssertEqual(popover?.permittedArrowDirections, [])
        XCTAssertEqual(controller.preferredContentSize, CGSize(width: 120, height: 80))
    }

    func testPrepareAcceptsOnlyOneHttpBrowserAtATime() throws {
        let browser = Browser()
        let url = try XCTUnwrap(URL(string: "https://capacitorjs.com"))
        XCTAssertFalse(browser.prepare(for: try XCTUnwrap(URL(string: "file:///tmp/page.html"))))
        XCTAssertTrue(browser.prepare(for: url))
        XCTAssertNotNil(browser.viewController)
        XCTAssertFalse(browser.prepare(for: url))
        browser.cleanup()
        XCTAssertNil(browser.viewController)
    }

    func testFinishIsReportedOnceForAPopoverDismissedThroughBothDelegateMethods() throws {
        let browser = Browser()
        var events: [BrowserEvent] = []
        browser.browserEventDidOccur = { events.append($0) }
        XCTAssertTrue(browser.prepare(for: try XCTUnwrap(URL(string: "https://capacitorjs.com")), modalPresentation: .popover))
        let popover = try XCTUnwrap(browser.viewController?.popoverPresentationController)

        browser.presentationControllerDidDismiss(popover)
        browser.popoverPresentationControllerDidDismissPopover(popover)

        XCTAssertEqual(events, [.finished])
        XCTAssertNil(browser.viewController)
    }

    @MainActor
    func testOpenRejectsWhenThereIsNothingToPresentFrom() async {
        let error = await thrownError { try await CAPBrowserPlugin().open(self.makeCall("open", ["url": "https://capacitorjs.com"])) }
        XCTAssertEqual(error?.message, "Unable to display URL: there is no view controller to present it from")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testOpenRejectsAnInvalidUrl() async {
        let error = await thrownError { try await CAPBrowserPlugin().open(self.makeCall("open", [:])) }
        XCTAssertEqual(error?.message, "Must provide a valid URL to open")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testOpenRejectsAUrlTheBrowserCannotShow() async {
        let harness = Harness()
        let error = await thrownError { try await harness.plugin.open(self.makeCall("open", ["url": "file:///tmp/page.html"])) }
        XCTAssertEqual(error?.message, "Unable to display URL")
    }

    @MainActor
    func testCloseRejectsWhenNoBrowserIsOpen() async {
        let error = await thrownError { try await CAPBrowserPlugin().close(self.makeCall("close", [:])) }
        XCTAssertEqual(error?.message, "No active window to close!")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testOpenReturnsOnceTheBrowserIsShownAndCloseForgetsIt() async throws {
        let harness = Harness()
        try await harness.plugin.open(makeCall("open", ["url": "https://capacitorjs.com"]))
        XCTAssertTrue(harness.root.fakePresented is SFSafariViewController)

        let second = await thrownError { try await harness.plugin.open(self.makeCall("open", ["url": "https://capacitorjs.com"])) }
        XCTAssertEqual(second?.message, "Unable to display URL", "only one browser at a time")

        try await harness.plugin.close(makeCall("close", [:]))
        let again = await thrownError { try await harness.plugin.close(self.makeCall("close", [:])) }
        XCTAssertEqual(again?.message, "No active window to close!")
    }

    @MainActor
    func testARefusedPresentationRejectsAndDoesNotBlockTheNextOpen() async throws {
        // UIKit logs and does nothing when the presenter is mid-transition or not in a window. The call used to hang,
        // and the browser it had prepared made every later open fail.
        let harness = Harness()
        harness.root.refusesPresentations = true
        let error = await thrownError { try await harness.plugin.open(self.makeCall("open", ["url": "https://capacitorjs.com"])) }
        XCTAssertEqual(error?.message, "Unable to display URL: there is no view controller to present it from")

        harness.root.refusesPresentations = false
        try await harness.plugin.open(makeCall("open", ["url": "https://capacitorjs.com"]))
        XCTAssertTrue(harness.root.fakePresented is SFSafariViewController)
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

    /// The CAPPluginError `body` throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func thrownError(_ body: () async throws -> Void) async -> CAPPluginError? {
        do {
            try await body()
            XCTFail("the method must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func makeCall(_ method: String, _ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: method, options: options, success: { _, _ in
            XCTFail("\(method) answers by returning or throwing")
        }, error: { _ in
            XCTFail("\(method) answers by returning or throwing")
        })
    }
}

/// A plugin whose bridge shows `root`. The plugin's bridge is weak: the harness keeps it.
private struct Harness {
    let plugin = CAPBrowserPlugin()
    let root = FakePresentingController()
    let bridge = FakeBridge()

    init() {
        bridge.viewController = root
        plugin.bridge = bridge
    }
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
