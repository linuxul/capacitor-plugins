import XCTest
import UIKit
import Capacitor
@testable import SplashScreenPlugin

class SplashScreenTests: XCTestCase {
    // Showing and hiding go through the main queue and UIKit transitions; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testShowWithoutASplashScreenIsRejected() {
        // A plugin that was not loaded by a bridge has no splash screen.
        XCTAssertEqual(thrownError(SplashScreenPlugin().show, "show")?.message, "Unable to show Splash Screen")
    }

    func testHideWithoutASplashScreenIsRejected() {
        XCTAssertEqual(thrownError(SplashScreenPlugin().hide, "hide")?.message, "Unable to hide Splash Screen")
    }

    /// The error `method` throws, which the bridge rejects the call with; nil when it does not throw.
    private func thrownError(_ method: (CAPPluginCall) throws -> Void, _ name: String) -> CAPPluginError? {
        let call = CAPPluginCall(callbackId: "test", methodName: name, options: [:], success: { _, _ in
            XCTFail("\(name) must not resolve")
        }, error: { _ in
            XCTFail("\(name) answers by throwing")
        })
        do {
            try method(call)
            XCTFail("\(name) must throw")
            return nil
        } catch let error as CAPPluginError {
            XCTAssertNil(error.code)
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    func testPreferredSceneIsTheForegroundActiveOne() {
        let scenes: [(String, UIScene.ActivationState)] = [
            ("background", .background),
            ("inactive", .foregroundInactive),
            ("active", .foregroundActive)
        ]
        XCTAssertEqual(SplashScreen.preferredScene(scenes, activationState: { $0.1 })?.0, "active")
    }

    func testPreferredSceneFallsBackToALaunchingSceneThenAnyScene() {
        let launching: [(String, UIScene.ActivationState)] = [("background", .background), ("inactive", .foregroundInactive)]
        XCTAssertEqual(SplashScreen.preferredScene(launching, activationState: { $0.1 })?.0, "inactive")

        let background: [(String, UIScene.ActivationState)] = [("background", .background)]
        XCTAssertEqual(SplashScreen.preferredScene(background, activationState: { $0.1 })?.0, "background")

        let none: [(String, UIScene.ActivationState)] = []
        XCTAssertNil(SplashScreen.preferredScene(none, activationState: { $0.1 }))
    }

    func testTheParentViewIsObservedOnlyWhileTheSplashIsShown() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let parentView = UIView(frame: window.bounds)
        window.addSubview(parentView)
        let splash = SplashScreen(parentView: parentView, config: SplashScreenConfig())
        XCTAssertFalse(splash.isObservingParentView)

        var settings = SplashScreenSettings()
        settings.fadeInDuration = 0
        settings.fadeOutDuration = 0
        settings.autoHide = false
        let shown = expectation(description: "the splash is shown")
        splash.show(settings: settings) {
            shown.fulfill()
        }
        wait(for: [shown], timeout: timeout)
        XCTAssertTrue(splash.isVisible)
        XCTAssertTrue(splash.isObservingParentView)
        XCTAssertEqual(splash.viewController.view.frame.size, window.bounds.size)

        // A rotation resizes the window and the parent view; the splash follows the window.
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 320)
        parentView.frame = window.bounds
        XCTAssertEqual(splash.viewController.view.frame.size, CGSize(width: 640, height: 320))

        splash.hide(settings: settings)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !splash.isVisible }, object: nil)
        wait(for: [hidden], timeout: timeout)
        XCTAssertFalse(splash.isObservingParentView, "the observations must end with the splash")
        XCTAssertNil(splash.viewController.view.superview)
    }
}
