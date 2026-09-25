import XCTest
import UIKit
import Capacitor
@testable import ActionSheetPlugin

final class ActionSheetPluginTests: XCTestCase {
    // The call settles from the main queue; allow for a loaded machine.
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

    func testShowActionsRejectsWhenThereIsNothingToPresentFrom() {
        let settled = expectation(description: "showActions settles")
        var rejection: String?
        let call = CAPPluginCall(callbackId: "test", methodName: "showActions", options: ["options": [["title": "One"]]], success: { _, _ in
            settled.fulfill()
        }, error: { error in
            rejection = error.message
            settled.fulfill()
        })

        ActionSheetPlugin().showActions(call)

        wait(for: [settled], timeout: timeout)
        XCTAssertEqual(rejection, "Unable to display the action sheet: there is no view controller to present it from")
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
