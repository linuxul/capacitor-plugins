import XCTest
import UIKit
import Capacitor
@testable import CameraPlugin

final class CameraPluginTests: XCTestCase {
    private let timeout: TimeInterval = 20

    func testASecondCallIsRefusedWhileOneIsActive() {
        let slot = ActiveCall()
        let first = makeCall("getPhoto")
        let second = makeCall("pickImages")

        XCTAssertTrue(slot.begin(first))
        XCTAssertFalse(slot.begin(second))
        XCTAssertTrue(slot.current === first, "a refused call must not replace the active one")
    }

    func testSettlingFreesTheSlotOnce() {
        let slot = ActiveCall()
        let first = makeCall("getPhoto")
        XCTAssertTrue(slot.begin(first))

        XCTAssertTrue(slot.take() === first)
        XCTAssertNil(slot.take(), "a second settle path must find no call")
        XCTAssertTrue(slot.begin(makeCall("getPhoto")))
    }

    func testPickImagesIsRejectedWhileAnotherCallIsInProgress() {
        let plugin = CameraPlugin()
        XCTAssertTrue(plugin.activeCall.begin(makeCall("getPhoto")))

        XCTAssertEqual(settle(plugin.pickImages, "pickImages"), CameraPlugin.callInProgressMessage)
    }

    func testRejectingTheActiveCallLetsTheNextOneBegin() {
        let plugin = CameraPlugin()
        let settled = expectation(description: "the active call settles")
        var rejection: String?
        let call = CAPPluginCall(callbackId: "active", methodName: "getPhoto", options: [:], success: { _, _ in
            settled.fulfill()
        }, error: { error in
            rejection = error.message
            settled.fulfill()
        })
        XCTAssertTrue(plugin.activeCall.begin(call))

        plugin.rejectActiveCall("User cancelled photos app")
        plugin.rejectActiveCall("a second path must not settle the call again")

        wait(for: [settled], timeout: timeout)
        XCTAssertEqual(rejection, "User cancelled photos app")
        XCTAssertNil(plugin.activeCall.current)
    }

    func testGetPhotoWithoutUsageDescriptionsDoesNotHoldTheSlot() {
        // The test runner's Info.plist has none of the camera usage descriptions, so getPhoto stops before the picker.
        let plugin = CameraPlugin()
        let first = settle(plugin.getPhoto, "getPhoto")
        let second = settle(plugin.getPhoto, "getPhoto")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(second, CameraPlugin.callInProgressMessage)
        XCTAssertNil(plugin.activeCall.current)
    }

    func testTopmostPresenterWalksToTheLastPresentedControllerNotBeingDismissed() {
        let root = FakePresentingController()
        let modal = FakePresentingController()
        let prompt = FakePresentingController()
        root.fakePresented = modal
        modal.fakePresented = prompt
        XCTAssertTrue(CameraPlugin.topmostPresenter(from: root) === prompt)

        prompt.fakeBeingDismissed = true
        XCTAssertTrue(CameraPlugin.topmostPresenter(from: root) === modal)
        XCTAssertNil(CameraPlugin.topmostPresenter(from: nil))
    }

    func testCenterPopoverAnchorsToThePresentersView() {
        let presenter = UIViewController()
        presenter.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let picker = UIViewController()
        picker.modalPresentationStyle = .popover

        CameraPlugin.centerPopover(picker, on: presenter)

        XCTAssertTrue(picker.popoverPresentationController?.sourceView === presenter.view)
        XCTAssertEqual(picker.popoverPresentationController?.sourceRect, CGRect(x: 200, y: 150, width: 0, height: 0))
    }

    func testReformatResizesPreservingTheAspectRatioAtScaleOne() {
        let image = makeImage(width: 400, height: 200, orientation: .up)

        let resized = image.reformat(to: CGSize(width: 100, height: 0))

        XCTAssertEqual(resized.size, CGSize(width: 100, height: 50))
        XCTAssertEqual(resized.scale, 1)
        XCTAssertEqual(resized.cgImage?.width, 100)
        XCTAssertEqual(resized.cgImage?.height, 50)
        XCTAssertEqual(resized.cgImage?.bitsPerComponent, 8, "the renderer must keep the 8-bit standard range")
    }

    func testReformatAppliesTheOrientation() {
        // 400x200 pixels displayed rotated: the image is 200 points wide and 400 high.
        let rotated = makeImage(width: 400, height: 200, orientation: .right)
        XCTAssertEqual(rotated.size, CGSize(width: 200, height: 400))

        let upright = rotated.reformat()

        XCTAssertEqual(upright.imageOrientation, .up)
        XCTAssertEqual(upright.cgImage?.width, 200)
        XCTAssertEqual(upright.cgImage?.height, 400)
    }

    func testReformatOfAnEmptyImageReturnsItUnchanged() {
        let empty = UIImage()
        XCTAssertTrue(empty.reformat(to: CGSize(width: 100, height: 100)) === empty)
    }

    private func makeImage(width: Int, height: Int, orientation: UIImage.Orientation) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // swiftlint:disable:next force_unwrapping
        return UIImage(cgImage: source.cgImage!, scale: 1, orientation: orientation)
    }

    private func makeCall(_ method: String) -> CAPPluginCall {
        return CAPPluginCall(callbackId: method, methodName: method, options: [:], success: { _, _ in }, error: { _ in })
    }

    /// Calls `method` and waits for it to settle. Returns the rejection message, or nil when the call resolved.
    private func settle(_ method: (CAPPluginCall) -> Void, _ name: String) -> String? {
        let settled = expectation(description: "\(name) settles")
        var rejection: String?
        method(CAPPluginCall(callbackId: "test", methodName: name, options: [:], success: { _, _ in
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
