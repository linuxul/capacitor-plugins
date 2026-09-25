import XCTest
import UIKit
import Capacitor
@testable import ScreenOrientationPlugin

class ScreenOrientationTests: XCTestCase {

    private struct TestError: Error {}

    func testCompletionOnceCallsTheHandlerOnlyForTheFirstResult() {
        var results: [Bool] = []
        let once = CompletionOnce { error in results.append(error == nil) }

        XCTAssertTrue(once.complete(TestError()))
        XCTAssertFalse(once.complete(nil))
        XCTAssertFalse(once.complete(TestError()))

        XCTAssertEqual(results, [false], "a failed request must not also resolve")
    }

    func testCompletionOnceIsSafeAcrossThreads() {
        let counter = NSLock()
        var calls = 0
        let once = CompletionOnce { _ in counter.withLock { calls += 1 } }

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            once.complete(nil)
        }

        XCTAssertEqual(calls, 1)
    }

    func testPreferredSceneIsTheForegroundActiveOne() {
        let scenes: [(String, UIScene.ActivationState)] = [
            ("background", .background),
            ("inactive", .foregroundInactive),
            ("active", .foregroundActive)
        ]
        XCTAssertEqual(ScreenOrientation.preferredScene(scenes, activationState: { $0.1 })?.0, "active")
    }

    func testPreferredSceneFallsBackToAForegroundInactiveThenAnyScene() {
        let launching: [(String, UIScene.ActivationState)] = [("background", .background), ("inactive", .foregroundInactive)]
        XCTAssertEqual(ScreenOrientation.preferredScene(launching, activationState: { $0.1 })?.0, "inactive")

        let background: [(String, UIScene.ActivationState)] = [("unattached", .unattached), ("background", .background)]
        XCTAssertEqual(ScreenOrientation.preferredScene(background, activationState: { $0.1 })?.0, "unattached")

        let none: [(String, UIScene.ActivationState)] = []
        XCTAssertNil(ScreenOrientation.preferredScene(none, activationState: { $0.1 }))
    }

    func testDoesNotKeepTheViewControllerAlive() {
        let implementation = ScreenOrientation()
        weak var weakViewController: CAPBridgeViewController?
        autoreleasepool {
            let viewController = CAPBridgeViewController()
            weakViewController = viewController
            implementation.setCapacitorViewController(viewController)
        }
        XCTAssertNil(weakViewController, "ScreenOrientation must not retain the bridge view controller")
    }

    func testOrientationTypesMapToMasks() {
        let implementation = ScreenOrientation()
        XCTAssertEqual(implementation.fromOrientationTypeToMask("any"), .all)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("landscape"), .landscapeRight)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("landscape-primary"), .landscapeRight)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("landscape-secondary"), .landscapeLeft)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("portrait-secondary"), .portraitUpsideDown)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("portrait-primary"), .portrait)
        XCTAssertEqual(implementation.fromOrientationTypeToMask("portrait"), .portrait)
    }

    func testOrientationTypesMapToInterfaceOrientations() {
        let implementation = ScreenOrientation()
        XCTAssertEqual(implementation.fromOrientationTypeToInt("any"), UIInterfaceOrientation.unknown.rawValue)
        XCTAssertEqual(implementation.fromOrientationTypeToInt("landscape"), UIInterfaceOrientation.landscapeRight.rawValue)
        XCTAssertEqual(implementation.fromOrientationTypeToInt("landscape-secondary"), UIInterfaceOrientation.landscapeLeft.rawValue)
        XCTAssertEqual(implementation.fromOrientationTypeToInt("portrait-secondary"), UIInterfaceOrientation.portraitUpsideDown.rawValue)
        XCTAssertEqual(implementation.fromOrientationTypeToInt("portrait-primary"), UIInterfaceOrientation.portrait.rawValue)
    }

    func testDeviceOrientationsMapToOrientationTypes() {
        let implementation = ScreenOrientation()
        XCTAssertEqual(implementation.fromDeviceOrientationToOrientationType(.landscapeLeft), "landscape-primary")
        XCTAssertEqual(implementation.fromDeviceOrientationToOrientationType(.landscapeRight), "landscape-secondary")
        XCTAssertEqual(implementation.fromDeviceOrientationToOrientationType(.portraitUpsideDown), "portrait-secondary")
        XCTAssertEqual(implementation.fromDeviceOrientationToOrientationType(.portrait), "portrait-primary")
        XCTAssertEqual(implementation.fromDeviceOrientationToOrientationType(.faceUp), "portrait-primary")
    }

    func testLockWithoutAnOrientationIsRejected() {
        let call = CAPPluginCall(callbackId: "test", methodName: "lock", options: [:], success: { _, _ in
            XCTFail("lock must not resolve")
        }, error: { _ in
            XCTFail("lock answers by throwing")
        })
        XCTAssertThrowsError(try ScreenOrientationPlugin().lock(call)) { error in
            // The bridge rejects the call with this error.
            XCTAssertEqual((error as? CAPPluginError)?.message, "Input option 'orientation' must be provided.")
            XCTAssertNil((error as? CAPPluginError)?.code)
        }
    }

    @MainActor
    func testOrientationReturnsAType() async {
        // The bridge resolves the call with what the async method returns.
        let call = CAPPluginCall(callbackId: "test", methodName: "orientation", options: [:], success: { _, _ in
            XCTFail("orientation answers by returning")
        }, error: { _ in
            XCTFail("orientation must not reject")
        })

        let result = await ScreenOrientationPlugin().orientation(call)

        XCTAssertNotNil(result["type"] as? String)
    }
}
