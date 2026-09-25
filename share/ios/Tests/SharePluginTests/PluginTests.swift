import XCTest
import UIKit
import Capacitor
@testable import SharePlugin

class ShareTests: XCTestCase {
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

    func testShareWithNothingToShareIsRejected() {
        XCTAssertEqual(settle(["title": "Only a title"]), "Must provide at least url, text or files")
    }

    func testShareRejectsWhenThereIsNothingToPresentFrom() {
        XCTAssertEqual(settle(["text": "Hello"]), "Unable to display the share sheet: there is no view controller to present it from")
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

    private func makeCall(_ options: JSObject, success: @escaping CAPPluginCallSuccessHandler = { _, _ in },
                          error: @escaping CAPPluginCallErrorHandler = { _ in }) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: "share", options: options, success: success, error: error)
    }

    /// Calls share and waits for it to settle. Returns the rejection message, or nil when the call resolved.
    private func settle(_ options: JSObject) -> String? {
        let settled = expectation(description: "share settles")
        var rejection: String?
        SharePlugin().share(makeCall(options, success: { _, _ in
            settled.fulfill()
        }, error: { error in
            rejection = error.message
            settled.fulfill()
        }))
        wait(for: [settled], timeout: timeout)
        return rejection
    }
}

/// A controller whose presentation state the test sets, since real presentation needs a window and an app.
private final class FakePresentingController: UIViewController {
    var fakePresented: UIViewController?
    var fakeBeingDismissed = false

    override var presentedViewController: UIViewController? {
        return fakePresented
    }

    override var isBeingDismissed: Bool {
        return fakeBeingDismissed
    }
}
