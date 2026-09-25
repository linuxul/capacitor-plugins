import XCTest
import UserNotifications
import Capacitor
@testable import PushNotificationsPlugin

// These tests never reach UNUserNotificationCenter.current(), which traps in the test runner: every call below stops
// at a check before it.
class PushNotificationsTests: XCTestCase {
    private let registrationNotCalled = "event capacitorDidRegisterForRemoteNotifications not called.  " +
        "Visit https://capacitorjs.com/docs/apis/push-notifications for more information"

    func testAuthorizationStatusesMapToPermissionStates() {
        XCTAssertEqual(PushNotificationsPlugin.permission(for: .authorized), .granted)
        XCTAssertEqual(PushNotificationsPlugin.permission(for: .provisional), .granted)
        XCTAssertEqual(PushNotificationsPlugin.permission(for: .ephemeral), .granted)
        XCTAssertEqual(PushNotificationsPlugin.permission(for: .denied), .denied)
        XCTAssertEqual(PushNotificationsPlugin.permission(for: .notDetermined), .prompt)
    }

    func testChannelMethodsThrowUnimplemented() {
        let plugin = PushNotificationsPlugin()
        let methods: [(String, (CAPPluginCall) throws -> Void)] = [
            ("createChannel", plugin.createChannel),
            ("deleteChannel", plugin.deleteChannel),
            ("listChannels", plugin.listChannels)
        ]
        for (name, method) in methods {
            let error = thrownError(method, name)
            XCTAssertEqual(error?.message, "Not available on iOS", name)
            XCTAssertEqual(error?.code, "UNIMPLEMENTED", name)
        }
    }

    func testRemovalsBeforeRegistrationAreRejected() {
        let plugin = PushNotificationsPlugin()
        XCTAssertEqual(thrownError(plugin.removeDeliveredNotifications, "removeDeliveredNotifications")?.message, registrationNotCalled)
        XCTAssertEqual(thrownError(plugin.removeAllDeliveredNotifications, "removeAllDeliveredNotifications")?.message, registrationNotCalled)
    }

    func testGetDeliveredNotificationsBeforeRegistrationIsRejected() async {
        do {
            _ = try await PushNotificationsPlugin().getDeliveredNotifications(unansweredCall("getDeliveredNotifications"))
            XCTFail("getDeliveredNotifications must throw")
        } catch let error as CAPPluginError {
            XCTAssertEqual(error.message, registrationNotCalled)
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The error `method` throws, which the bridge rejects the call with; nil when it does not throw.
    private func thrownError(_ method: (CAPPluginCall) throws -> Void, _ name: String) -> CAPPluginError? {
        do {
            try method(unansweredCall(name))
            XCTFail("\(name) must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func unansweredCall(_ method: String) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: method, options: [:], success: { _, _ in
            XCTFail("\(method) answers by returning or throwing")
        }, error: { _ in
            XCTFail("\(method) answers by returning or throwing")
        })
    }
}
