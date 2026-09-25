import XCTest
import UserNotifications
import Capacitor
@testable import LocalNotificationsPlugin

// These tests never reach UNUserNotificationCenter.current(): the test runner has no app bundle, and the center traps
// without one. A test that passes therefore also shows that the plugin returned before scheduling anything.
final class LocalNotificationsPluginTests: XCTestCase {
    private let timeout: TimeInterval = 20
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAPastDateIsRejectedInsteadOfScheduledForNow() {
        let plugin = LocalNotificationsPlugin()
        XCTAssertThrowsError(try plugin.handleScheduledNotification(["at": now.addingTimeInterval(-5)], now: now)) { error in
            guard case LocalNotificationError.triggerDateNotInFuture = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testTheCurrentTimeCountsAsPast() {
        // A zero interval would raise an Objective-C exception in UNTimeIntervalNotificationTrigger.
        XCTAssertThrowsError(try LocalNotificationsPlugin().handleScheduledNotification(["at": now], now: now))
    }

    func testAFutureDateMakesATimeIntervalTrigger() throws {
        let trigger = try LocalNotificationsPlugin().handleScheduledNotification(["at": now.addingTimeInterval(90)], now: now)
        let interval = try XCTUnwrap(trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(interval.timeInterval, 90, accuracy: 0.001)
        XCTAssertFalse(interval.repeats)
    }

    func testARepeatingDateUnderAMinuteIsRejected() {
        let schedule: JSObject = ["at": now.addingTimeInterval(30), "repeats": true]
        XCTAssertThrowsError(try LocalNotificationsPlugin().handleScheduledNotification(schedule, now: now)) { error in
            guard case LocalNotificationError.triggerRepeatIntervalTooShort = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testOnMakesARepeatingCalendarTrigger() throws {
        let components: JSObject = ["hour": 8, "minute": 30, "weekday": 2]
        let schedule: JSObject = ["on": components]
        let trigger = try LocalNotificationsPlugin().handleScheduledNotification(schedule, now: now)
        let calendar = try XCTUnwrap(trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(calendar.repeats)
        XCTAssertEqual(calendar.dateComponents.hour, 8)
        XCTAssertEqual(calendar.dateComponents.minute, 30)
        XCTAssertEqual(calendar.dateComponents.weekday, 2)
        XCTAssertNil(calendar.dateComponents.day)
    }

    func testEveryMakesARepeatingIntervalTrigger() throws {
        let trigger = try LocalNotificationsPlugin().handleScheduledNotification(["every": "minute", "count": 5], now: now)
        let interval = try XCTUnwrap(trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(interval.timeInterval, 300, accuracy: 0.001)
        XCTAssertTrue(interval.repeats)
    }

    func testEveryUnderAMinuteIsRejectedInsteadOfCrashing() {
        XCTAssertThrowsError(try LocalNotificationsPlugin().handleScheduledNotification(["every": "second", "count": 10], now: now))
    }

    func testRepeatDateIntervalHandlesUnknownUnitsAndBackwardCounts() {
        let plugin = LocalNotificationsPlugin()
        XCTAssertNil(plugin.getRepeatDateInterval("fortnight", 1, from: now))
        XCTAssertNil(plugin.getRepeatDateInterval("day", -1, from: now), "an interval that ends before it starts traps")
        XCTAssertEqual(plugin.getRepeatDateInterval("hour", 2, from: now)?.duration ?? 0, 7200, accuracy: 0.001)
        XCTAssertEqual(plugin.getRepeatDateInterval("two-weeks", 1, from: now)?.end,
                       Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now))
    }

    func testScheduleWithAPastDateRejectsTheBatch() {
        let future: JSObject = ["at": Date().addingTimeInterval(3600)]
        let past: JSObject = ["at": Date().addingTimeInterval(-3600)]
        let first: JSObject = ["id": 1, "title": "Soon", "body": "In an hour", "schedule": future]
        let second: JSObject = ["id": 2, "title": "Late", "body": "An hour ago", "schedule": past]
        let notifications: JSArray = [first, second]
        XCTAssertEqual(settle(LocalNotificationsPlugin().schedule, "schedule", ["notifications": notifications]),
                       "Scheduled time must be *after* current time")
    }

    func testRegisterActionTypesWithoutTypesIsRejected() {
        XCTAssertEqual(settle(LocalNotificationsPlugin().registerActionTypes, "registerActionTypes", [:]),
                       "Must provide types array as types option")
    }

    func testStoredRequestsAreSafeToUseFromSeveralQueues() {
        let handler = LocalNotificationsHandler()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            handler.storeRequest(["id": index], forIdentifier: "\(index)")
            _ = handler.storedRequest(forIdentifier: "\(index / 2)")
        }
        for index in 0..<200 {
            XCTAssertEqual(handler.storedRequest(forIdentifier: "\(index)")?["id"] as? Int, index)
        }
        XCTAssertNil(handler.storedRequest(forIdentifier: "missing"))
    }

    func testAttachmentOptionsMapToTheUserNotificationsKeys() {
        let options = LocalNotificationsPlugin().makeAttachmentOptions([
            "iosUNNotificationAttachmentOptionsTypeHintKey": "public.jpeg",
            "iosUNNotificationAttachmentOptionsThumbnailHiddenKey": "true",
            "iosUNNotificationAttachmentOptionsThumbnailTimeKey": "2",
            "unrelated": "ignored"
        ])
        XCTAssertEqual(options[UNNotificationAttachmentOptionsTypeHintKey] as? String, "public.jpeg")
        XCTAssertEqual(options[UNNotificationAttachmentOptionsThumbnailHiddenKey] as? String, "true")
        XCTAssertEqual(options[UNNotificationAttachmentOptionsThumbnailTimeKey] as? String, "2")
        XCTAssertEqual(options.count, 3)
    }

    func testInterruptionLevels() {
        XCTAssertEqual(LocalNotificationsPlugin.interruptionLevel("active"), .active)
        XCTAssertEqual(LocalNotificationsPlugin.interruptionLevel("critical"), .critical)
        XCTAssertEqual(LocalNotificationsPlugin.interruptionLevel("passive"), .passive)
        XCTAssertEqual(LocalNotificationsPlugin.interruptionLevel("timeSensitive"), .timeSensitive)
        XCTAssertNil(LocalNotificationsPlugin.interruptionLevel("loud"))
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
