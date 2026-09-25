import XCTest
import UIKit
import Capacitor
@testable import DialogPlugin

final class DialogPluginTests: XCTestCase {
    // The bridge settles a call on the main queue in some paths; allow for a loaded machine.
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

    func testEveryDialogRejectsWhenThereIsNothingToPresentFrom() {
        let plugin = DialogPlugin()
        let methods: [(String, (CAPPluginCall) -> Void)] = [
            ("alert", plugin.alert),
            ("confirm", plugin.confirm),
            ("prompt", plugin.prompt)
        ]
        for (name, method) in methods {
            let recorder = CallRecorder(testCase: self, description: name)
            method(recorder.makeCall(name, ["message": "hello"]))
            wait(for: [recorder.settled], timeout: timeout)
            XCTAssertEqual(recorder.resolutions.count, 0, name)
            XCTAssertEqual(recorder.rejections, ["Unable to display the dialog: there is no view controller to present it from"], name)
        }
    }

    func testDialogWithoutAMessageIsRejected() {
        let recorder = CallRecorder(testCase: self, description: "alert")
        DialogPlugin().alert(recorder.makeCall("alert", [:]))
        wait(for: [recorder.settled], timeout: timeout)
        XCTAssertEqual(recorder.rejections, ["Please provide a message for the dialog"])
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

/// Records how a call settles.
private final class CallRecorder {
    let settled: XCTestExpectation
    private let lock = NSLock()
    private var recordedResolutions: [PluginCallResultData?] = []
    private var recordedRejections: [String] = []

    init(testCase: XCTestCase, description: String) {
        settled = testCase.expectation(description: "\(description) settles")
    }

    var resolutions: [PluginCallResultData?] {
        lock.withLock { recordedResolutions }
    }

    var rejections: [String] {
        lock.withLock { recordedRejections }
    }

    func makeCall(_ method: String, _ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test-\(method)", methodName: method, options: options, success: { [weak self] result, _ in
            self?.lock.withLock { self?.recordedResolutions.append(result.data) }
            self?.settled.fulfill()
        }, error: { [weak self] error in
            self?.lock.withLock { self?.recordedRejections.append(error.message) }
            self?.settled.fulfill()
        })
    }
}
