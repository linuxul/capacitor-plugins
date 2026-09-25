import XCTest
import UIKit
import Capacitor
@testable import ScreenReaderPlugin

class ScreenReaderTests: XCTestCase {
    private let timeout: TimeInterval = 20

    @MainActor
    func testIsEnabledReturnsWhetherVoiceOverRuns() async {
        let call = CAPPluginCall(callbackId: "test", methodName: "isEnabled", options: [:], success: { _, _ in
            XCTFail("isEnabled answers by returning")
        }, error: { _ in
            XCTFail("isEnabled must not reject")
        })

        let result = await ScreenReaderPlugin().isEnabled(call)

        XCTAssertEqual(result["value"] as? Bool, UIAccessibility.isVoiceOverRunning)
    }

    func testSpeakWithoutAValueIsRejected() {
        let call = CAPPluginCall(callbackId: "test", methodName: "speak", options: [:], success: { _, _ in
            XCTFail("speak must not resolve")
        }, error: { _ in
            XCTFail("speak answers by throwing")
        })
        XCTAssertThrowsError(try ScreenReaderPlugin().speak(call)) { error in
            XCTAssertEqual((error as? CAPPluginError)?.message, "No value provided")
            XCTAssertNil((error as? CAPPluginError)?.code)
        }
    }

    func testSpeakResolvesRightAway() {
        let resolved = expectation(description: "speak resolves")
        let call = CAPPluginCall(callbackId: "test", methodName: "speak", options: ["value": "Hello"], success: { _, _ in
            resolved.fulfill()
        }, error: { _ in
            XCTFail("speak must not reject")
        })

        // The bridge calls speak on its queue, not the main one.
        DispatchQueue.global().async {
            do {
                try ScreenReaderPlugin().speak(call)
            } catch {
                XCTFail("speak must not throw: \(error)")
            }
        }

        wait(for: [resolved], timeout: timeout)
    }
}
