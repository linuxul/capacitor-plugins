import XCTest
import UIKit
import WebKit
import Capacitor
@testable import CameraPlugin

final class CameraPluginTests: XCTestCase {
    private let timeout: TimeInterval = 20

    func testASecondCallIsRefusedWhileOneIsActive() {
        let slot = ActiveCall()
        let first = makeCall("getPhoto")
        let second = makeCall("pickImages")
        let answers = Answers()

        XCTAssertTrue(slot.begin(first, answer: answers.record))
        XCTAssertFalse(slot.begin(second, answer: answers.record))
        XCTAssertTrue(slot.current === first, "a refused call must not replace the active one")
        XCTAssertTrue(answers.all.isEmpty, "a refused call must not answer the active one")
    }

    func testFinishingFreesTheSlotAndAnswersOnce() {
        let slot = ActiveCall()
        let answers = Answers()
        XCTAssertTrue(slot.begin(makeCall("getPhoto"), answer: answers.record))

        XCTAssertTrue(slot.finish(with: .success(["format": "jpeg"])))
        XCTAssertFalse(slot.finish(with: .failure(CAPPluginError("a second path must find no call"))))

        XCTAssertEqual(answers.all.count, 1)
        XCTAssertEqual(try answers.all.first?.get()["format"] as? String, "jpeg")
        XCTAssertNil(slot.current)
        XCTAssertTrue(slot.begin(makeCall("getPhoto"), answer: answers.record))
    }

    func testASlotReleasedWithAnActiveCallAnswersIt() {
        let answers = Answers()
        autoreleasepool {
            let slot = ActiveCall()
            XCTAssertTrue(slot.begin(makeCall("getPhoto"), answer: answers.record))
        }
        XCTAssertEqual(answers.messages, ["The camera plugin is no longer available"])
    }

    @MainActor
    func testPickImagesIsRejectedWhileAnotherCallIsInProgress() async {
        let plugin = CameraPlugin()
        let answers = Answers()
        XCTAssertTrue(plugin.activeCall.begin(makeCall("getPhoto"), answer: answers.record))

        let error = await thrownError { try await plugin.pickImages(self.makeCall("pickImages")) }

        XCTAssertEqual(error?.message, CameraPlugin.callInProgressMessage)
        XCTAssertNotNil(plugin.activeCall.current, "the call in progress keeps the slot")
        XCTAssertTrue(answers.all.isEmpty)
    }

    func testRejectingTheActiveCallLetsTheNextOneBegin() {
        let plugin = CameraPlugin()
        let answers = Answers()
        XCTAssertTrue(plugin.activeCall.begin(makeCall("getPhoto"), answer: answers.record))

        plugin.rejectActiveCall("User cancelled photos app")
        plugin.rejectActiveCall("a second path must not settle the call again")

        XCTAssertEqual(answers.messages, ["User cancelled photos app"])
        XCTAssertNil(plugin.activeCall.current)
    }

    @MainActor
    func testWhileActiveReturnsWhatThePickerPathAnswers() async throws {
        let plugin = CameraPlugin()
        // Numbers reach the plugin as NSNumbers, as the bridge decodes them from JSON.
        let call = makeCall("pickImages", ["quality": NSNumber(value: 50)])

        let result = try await plugin.whileActive(call, multiple: true) {
            XCTAssertTrue(plugin.activeCall.current === call)
            XCTAssertTrue(plugin.multiple)
            XCTAssertEqual(plugin.settings.jpegQuality, 0.5)
            plugin.resolveActiveCall(["photos": [JSObject]()])
            plugin.rejectActiveCall("a second path must not answer again")
        }

        XCTAssertNotNil(result["photos"] as? [JSObject])
        XCTAssertNil(plugin.activeCall.current)
    }

    @MainActor
    func testWhileActiveThrowsWhatThePickerPathRejectsWith() async {
        let plugin = CameraPlugin()
        let error = await thrownError {
            try await plugin.whileActive(self.makeCall("getPhoto"), multiple: false) {
                plugin.rejectActiveCall("User denied access to photos")
            }
        }
        XCTAssertEqual(error?.message, "User denied access to photos")
        XCTAssertNil(error?.code)
        XCTAssertNil(plugin.activeCall.current)
    }

    @MainActor
    func testGetPhotoWithoutUsageDescriptionsDoesNotHoldTheSlot() async {
        // The test runner's Info.plist has none of the camera usage descriptions, so getPhoto stops before the picker.
        let plugin = CameraPlugin()
        let first = await thrownError { try await plugin.getPhoto(self.makeCall("getPhoto")) }
        let second = await thrownError { try await plugin.getPhoto(self.makeCall("getPhoto")) }

        XCTAssertNotNil(first)
        XCTAssertEqual(first?.message, second?.message)
        XCTAssertNotEqual(second?.message, CameraPlugin.callInProgressMessage)
        XCTAssertNil(plugin.activeCall.current)
    }

    @MainActor
    func testAPromptThatGoesAwayWithoutAChoiceCancelsTheCall() async throws {
        // On iPad a tap outside the popover dismisses the prompt without calling an action. The call used to keep the
        // slot, and every later call was rejected as in progress.
        let harness = Harness()
        let answers = Answers()
        XCTAssertTrue(harness.plugin.activeCall.begin(makeCall("getPhoto"), answer: answers.record))

        harness.plugin.showPrompt()
        // Only the titles are kept: the prompt's release is what cancels the call.
        XCTAssertEqual((harness.root.fakePresented as? UIAlertController)?.actions.map(\.title), ["From Photos", "Take Picture", "Cancel"])
        harness.root.fakePresented = nil

        let deadline = Date().addingTimeInterval(timeout)
        while answers.all.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(answers.messages, ["User cancelled photos app"])
        XCTAssertNil(harness.plugin.activeCall.current)
    }

    @MainActor
    func testARefusedPromptRejectsOnceWithTheNoPresenterMessage() async throws {
        let harness = Harness()
        harness.root.refusesPresentations = true
        let answers = Answers()
        XCTAssertTrue(harness.plugin.activeCall.begin(makeCall("getPhoto"), answer: answers.record))

        harness.plugin.showPrompt()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(answers.messages, [CameraPlugin.noPresenterMessage])
        XCTAssertNil(harness.plugin.activeCall.current)
    }

    func testImageResultHasTheRequestedTypeAndTheExif() throws {
        let plugin = CameraPlugin()
        plugin.settings.resultType = .dataURL
        let metadata: [String: Any] = ["{Exif}": ["ExposureTime": 0.01, "ISOSpeedRatings": [100]], "Orientation": 1]
        let processed = ProcessedImage(image: makeImage(width: 4, height: 4, orientation: .up), metadata: metadata)

        let result = try plugin.imageResult(processed, isSaved: false)

        XCTAssertTrue((result["dataUrl"] as? String)?.hasPrefix("data:image/jpeg;base64,") ?? false)
        XCTAssertEqual(result["format"] as? String, "jpeg")
        XCTAssertEqual(result["saved"] as? Bool, false)
        let exif = try XCTUnwrap(result["exif"] as? JSObject)
        XCTAssertEqual((exif["ExposureTime"] as? NSNumber)?.doubleValue, 0.01)
        XCTAssertEqual((exif["Orientation"] as? NSNumber)?.intValue, 1)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result as [String: Any]), "the bridge sends the result as JSON")
    }

    func testPhotosResultSavesEachImageAsATemporaryFile() throws {
        let harness = Harness()
        let images = [makeImage(width: 2, height: 2, orientation: .up), makeImage(width: 3, height: 3, orientation: .up)]
            .map { ProcessedImage(image: $0, metadata: [:]) }

        let result = try harness.plugin.photosResult(images, jpegQuality: 0.8)

        let photos = try XCTUnwrap(result["photos"] as? [JSObject])
        XCTAssertEqual(photos.count, 2)
        for photo in photos {
            let path = try XCTUnwrap(photo["path"] as? String)
            let url = try XCTUnwrap(URL(string: path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(photo["webPath"] as? String, path, "the fake bridge maps a local URL to itself")
            XCTAssertEqual(photo["format"] as? String, "jpeg")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testPhotosResultWithoutABridgeIsRejected() {
        let image = ProcessedImage(image: makeImage(width: 2, height: 2, orientation: .up), metadata: [:])
        XCTAssertThrowsError(try CameraPlugin().photosResult([image], jpegQuality: 1)) { error in
            XCTAssertEqual((error as? CAPPluginError)?.message, "Unable to get portable path to file")
        }
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

    private func makeCall(_ method: String, _ options: JSObject = [:]) -> CAPPluginCall {
        return CAPPluginCall(callbackId: method, methodName: method, options: options, success: { _, _ in
            XCTFail("\(method) answers by returning or throwing")
        }, error: { _ in
            XCTFail("\(method) answers by returning or throwing")
        })
    }

    /// The CAPPluginError `body` throws, which the bridge rejects the call with; nil when it returns.
    @MainActor
    private func thrownError(_ body: () async throws -> JSObject) async -> CAPPluginError? {
        do {
            _ = try await body()
            XCTFail("the method must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }
}

/// Records the answers of the active call.
private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Result<JSObject, Error>] = []

    var all: [Result<JSObject, Error>] {
        lock.withLock { recorded }
    }

    /// The messages of the errors recorded.
    var messages: [String] {
        return all.compactMap { answer in
            guard case .failure(let error) = answer else {
                return nil
            }
            return (error as? CAPPluginError)?.message ?? error.localizedDescription
        }
    }

    func record(_ answer: Result<JSObject, Error>) {
        lock.withLock { recorded.append(answer) }
    }
}

/// A plugin whose bridge shows `root`. The plugin's bridge is weak: the harness keeps it.
private struct Harness {
    let plugin = CameraPlugin()
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

/// A bridge with just enough behaviour for the plugin to find its view controller and map file URLs. Members it never
/// uses trap.
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
