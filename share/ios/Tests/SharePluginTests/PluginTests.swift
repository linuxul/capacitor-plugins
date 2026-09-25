import XCTest
import UIKit
import WebKit
import Capacitor
@testable import SharePlugin

class ShareTests: XCTestCase {
    // Presentation and the release of a dismissed sheet go through the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testActivityItemsCollectTextUrlAndFiles() {
        let files: JSArray = ["file:///tmp/a.txt", "file:///tmp/b.png", 42]
        let call = makeCall(["text": "Hello", "url": "https://capacitorjs.com", "files": files])

        let items = SharePlugin.activityItems(from: call)

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.first as? String, "Hello")
        XCTAssertEqual((items[1] as? URL)?.absoluteString, "https://capacitorjs.com")
        XCTAssertEqual((items[2] as? URL)?.absoluteString, "file:///tmp/a.txt")
        XCTAssertEqual((items[3] as? URL)?.absoluteString, "file:///tmp/b.png")
    }

    @MainActor
    func testShareWithNothingToShareIsRejected() async {
        let error = await shareError(SharePlugin(), ["title": "Only a title"])
        XCTAssertEqual(error?.message, "Must provide at least url, text or files")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testShareRejectsWhenThereIsNothingToPresentFrom() async {
        let error = await shareError(SharePlugin(), ["text": "Hello"])
        XCTAssertEqual(error?.message, "Unable to display the share sheet: there is no view controller to present it from")
        XCTAssertNil(error?.code)
    }

    @MainActor
    func testShareRejectsWhileASheetIsShown() async {
        let harness = Harness()
        harness.root.fakePresented = UIActivityViewController(activityItems: ["Busy"], applicationActivities: nil)
        let error = await shareError(harness.plugin, ["text": "Hello"])
        XCTAssertEqual(error?.message, "Can't share while sharing is in progress")
    }

    @MainActor
    func testShareRejectsWhenUIKitRefusesToPresent() async {
        let harness = Harness()
        harness.root.refusesPresentations = true
        let error = await shareError(harness.plugin, ["text": "Hello"])
        XCTAssertEqual(error?.message, "Unable to display the share sheet: there is no view controller to present it from")
    }

    @MainActor
    func testShareResolvesWithTheFirstReportOfTheSheet() async throws {
        let harness = Harness()
        let sharing = Task { @MainActor in try await harness.plugin.share(self.makeCall(["text": "Hello"])) }

        let sheet = try await presentedSheet(of: harness.root)
        sheet.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)
        sheet.completionWithItemsHandler?(nil, false, nil, nil)
        let result = try await sharing.value

        XCTAssertEqual(result["activityType"] as? String, UIActivity.ActivityType.copyToPasteboard.rawValue)
        harness.root.fakePresented = nil
    }

    @MainActor
    func testASheetClosedWithoutSharingIsCanceled() async throws {
        let harness = Harness()
        let sharing = Task { @MainActor in try await harness.plugin.share(self.makeCall(["text": "Hello"])) }

        let sheet = try await presentedSheet(of: harness.root)
        sheet.completionWithItemsHandler?(nil, false, nil, nil)

        let error = await thrownError { try await sharing.value }
        XCTAssertEqual(error?.message, "Share canceled")
        harness.root.fakePresented = nil
    }

    @MainActor
    func testAFailedShareIsRejected() async throws {
        let harness = Harness()
        let sharing = Task { @MainActor in try await harness.plugin.share(self.makeCall(["text": "Hello"])) }

        let sheet = try await presentedSheet(of: harness.root)
        sheet.completionWithItemsHandler?(.mail, false, nil, NSError(domain: "test", code: 1))

        let error = await thrownError { try await sharing.value }
        XCTAssertEqual(error?.message, "Error sharing item")
        XCTAssertNil(error?.code)
        harness.root.fakePresented = nil
    }

    @MainActor
    func testASheetThatGoesAwayWithoutReportingIsCanceled() async throws {
        // The app dismissed the sheet: UIKit released it without calling its completion handler.
        let harness = Harness()
        let sharing = Task { @MainActor in try await harness.plugin.share(self.makeCall(["text": "Hello"])) }

        _ = try await presentedSheet(of: harness.root)
        harness.root.fakePresented = nil

        let error = await thrownError { try await sharing.value }
        XCTAssertEqual(error?.message, "Share canceled")
    }

    func testTopmostPresenterSkipsAControllerBeingDismissed() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        let dismissing = FakePresentingController()
        root.fakePresented = modal
        modal.fakePresented = dismissing
        XCTAssertTrue(SharePlugin.topmostPresenter(from: root) === dismissing)

        dismissing.fakeBeingDismissed = true
        XCTAssertTrue(SharePlugin.topmostPresenter(from: root) === modal)
        XCTAssertFalse(SharePlugin.isSharing(over: root))
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

    /// Waits until `presenter` shows a share sheet. The caller must not keep it longer than the test needs it: its
    /// release is what answers a sheet that never reported.
    @MainActor
    private func presentedSheet(of presenter: FakePresentingController) async throws -> UIActivityViewController {
        let deadline = Date().addingTimeInterval(timeout)
        while presenter.fakePresented == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(presenter.fakePresented as? UIActivityViewController)
    }

    /// The CAPPluginError `body` throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func thrownError(_ body: () async throws -> JSObject) async -> CAPPluginError? {
        do {
            _ = try await body()
            XCTFail("share must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    @MainActor
    private func shareError(_ plugin: SharePlugin, _ options: JSObject) async -> CAPPluginError? {
        return await thrownError { try await plugin.share(makeCall(options)) }
    }

    private func makeCall(_ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: "share", options: options, success: { _, _ in
            XCTFail("share answers by returning or throwing")
        }, error: { _ in
            XCTFail("share answers by returning or throwing")
        })
    }
}

/// A plugin whose bridge shows `root`. The plugin's bridge is weak: the harness keeps it.
private struct Harness {
    let plugin = SharePlugin()
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
