import XCTest
import UIKit
import SafariServices
import Capacitor
@testable import BrowserPlugin

final class BrowserPluginTests: XCTestCase {
    // The calls settle from the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

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

    func testOpenRejectsWhenThereIsNothingToPresentFrom() {
        let rejection = settle(CAPBrowserPlugin().open, "open", ["url": "https://capacitorjs.com"])
        XCTAssertEqual(rejection, "Unable to display URL: there is no view controller to present it from")
    }

    func testOpenRejectsAnInvalidUrl() {
        XCTAssertEqual(settle(CAPBrowserPlugin().open, "open", [:]), "Must provide a valid URL to open")
    }

    func testCloseRejectsWhenNoBrowserIsOpen() {
        XCTAssertEqual(settle(CAPBrowserPlugin().close, "close", [:]), "No active window to close!")
    }

    /// Calls `method` and waits for it to settle. Returns the rejection message, or nil when the call resolved.
    private func settle(_ method: (CAPPluginCall) -> Void, _ name: String, _ options: JSObject) -> String? {
        let settled = expectation(description: "\(name) settles")
        var rejection: String?
        method(CAPPluginCall(callbackId: "test", methodName: name, options: options, success: { _, _ in
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
