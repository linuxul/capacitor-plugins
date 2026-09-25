import Foundation
import Capacitor
import UIKit
import UserNotifications

enum LocalNotificationError: LocalizedError {
    case contentNoId
    case contentNoTitle
    case contentNoBody
    case triggerConstructionFailed
    case triggerRepeatIntervalTooShort
    case triggerDateNotInFuture
    case attachmentNoId
    case attachmentNoUrl
    case attachmentFileNotFound(path: String)
    case attachmentUnableToCreate(String)

    var errorDescription: String? {
        switch self {
        case .attachmentFileNotFound(path: let path):
            return "Unable to find file \(path) for attachment"
        default:
            return ""
        }
    }
}

@objc(LocalNotificationsPlugin)
public class LocalNotificationsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LocalNotificationsPlugin"
    public let jsName = "LocalNotifications"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("schedule", LocalNotificationsPlugin.schedule),
        .async("requestPermissions", LocalNotificationsPlugin.requestNotificationPermissions),
        .async("checkPermissions", LocalNotificationsPlugin.checkNotificationPermissions),
        .promise("checkExactNotificationSetting", LocalNotificationsPlugin.checkExactNotificationSetting),
        .promise("changeExactNotificationSetting", LocalNotificationsPlugin.changeExactNotificationSetting),
        .promise("cancel", LocalNotificationsPlugin.cancel),
        .async("getPending", LocalNotificationsPlugin.getPending),
        .promise("registerActionTypes", LocalNotificationsPlugin.registerActionTypes),
        .async("areEnabled", LocalNotificationsPlugin.areEnabled),
        .async("getDeliveredNotifications", LocalNotificationsPlugin.getDeliveredNotifications),
        .promise("removeAllDeliveredNotifications", LocalNotificationsPlugin.removeAllDeliveredNotifications),
        .promise("removeDeliveredNotifications", LocalNotificationsPlugin.removeDeliveredNotifications),
        .promise("createChannel", LocalNotificationsPlugin.createChannel),
        .promise("deleteChannel", LocalNotificationsPlugin.deleteChannel),
        .promise("listChannels", LocalNotificationsPlugin.listChannels)
    ]
    private let notificationDelegationHandler = LocalNotificationsHandler()

    override public func load() {
        self.bridge?.notificationRouter.localNotificationHandler = self.notificationDelegationHandler
        self.notificationDelegationHandler.plugin = self
        self.shouldStringifyDatesInCalls = false
    }

    // The methods that change what is scheduled or delivered (schedule, cancel, registerActionTypes and the removals)
    // stay synchronous: the bridge queue runs them in the order of the calls, so a cancel after a schedule removes
    // what was scheduled. Async methods would not keep that order. The queries and the permission methods are async
    // and await the notification center.

    /**
     * Schedule a notification.
     */
    func schedule(_ call: CAPPluginCall) throws {
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            throw CAPPluginError("Must provide notifications array as notifications option")
        }
        // Build every request before adding any, so a notification the plugin rejects schedules none of the batch.
        var requests = [(request: UNNotificationRequest, notification: JSObject)]()
        for notification in notifications {
            guard let identifier = notification["id"] as? Int else {
                throw CAPPluginError("Notification missing identifier")
            }

            let content: UNNotificationContent
            do {
                content = try makeNotificationContent(notification)
            } catch {
                CAPLog.print(error.localizedDescription)
                throw CAPPluginError("Unable to make notification", underlyingError: error)
            }

            var trigger: UNNotificationTrigger?
            do {
                if let schedule = notification["schedule"] as? JSObject {
                    trigger = try handleScheduledNotification(schedule)
                }
            } catch LocalNotificationError.triggerDateNotInFuture {
                throw CAPPluginError("Scheduled time must be *after* current time")
            } catch {
                throw CAPPluginError("Unable to create notification, trigger failed", underlyingError: error)
            }

            let request = UNNotificationRequest(identifier: "\(identifier)", content: content, trigger: trigger)
            requests.append((request, notification))
        }
        add(requests, for: call)
    }

    /// Adds the requests and settles `call` once every addition has completed: rejected with the first error, or
    /// resolved with the identifiers. The call used to resolve before the additions completed and then reject again
    /// when one failed.
    private func add(_ requests: [(request: UNNotificationRequest, notification: JSObject)], for call: CAPPluginCall) {
        let center = UNUserNotificationCenter.current()
        let group = DispatchGroup()
        let errorLock = NSLock()
        var firstError: Error?
        for (request, notification) in requests {
            notificationDelegationHandler.storeRequest(notification, forIdentifier: request.identifier)
            group.enter()
            center.add(request) { (error: Error?) in
                if let error {
                    CAPLog.print(error.localizedDescription)
                    errorLock.withLock {
                        firstError = firstError ?? error
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) {
            if let error = errorLock.withLock({ firstError }) {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve([
                "notifications": requests.map { ["id": Int($0.request.identifier) ?? -1] }
            ])
        }
    }

    /**
     * Request notification permission
     */
    func requestNotificationPermissions(_ call: CAPPluginCall) async throws -> JSObject {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound])
        } catch {
            throw CAPPluginError(error.localizedDescription, underlyingError: error)
        }
        return ["display": granted ? "granted" : "denied"]
    }

    func checkNotificationPermissions(_ call: CAPPluginCall) async -> JSObject {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return ["display": LocalNotificationsPlugin.displayPermission(for: settings.authorizationStatus)]
    }

    /// The permission state JavaScript receives for an authorization status.
    static func displayPermission(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .ephemeral, .provisional:
            return "granted"
        case .denied:
            return "denied"
        case .notDetermined:
            return "prompt"
        @unknown default:
            return "prompt"
        }
    }

    public func checkExactNotificationSetting(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented()
    }

    public func changeExactNotificationSetting(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented()
    }

    /**
     * Cancel notifications by id
     */
    func cancel(_ call: CAPPluginCall) throws {
        guard let notifications = call.getArray("notifications", JSObject.self), notifications.count > 0 else {
            throw CAPPluginError("Must supply notifications to cancel")
        }

        let ids = notifications.map({ (value: JSObject) -> String in
            if let idString = value["id"] as? String {
                return idString
            } else if let idNum = value["id"] as? NSNumber {
                return idNum.stringValue
            }
            return ""
        })

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        call.resolve()
    }

    /**
     * Get all pending notifications.
     */
    func getPending(_ call: CAPPluginCall) async -> JSObject {
        let notifications = await UNUserNotificationCenter.current().pendingNotificationRequests()
        CAPLog.print("num of pending notifications \(notifications.count)")
        CAPLog.print(notifications)

        return [
            "notifications": notifications.map(notificationDelegationHandler.makePendingNotificationRequestJSObject)
        ]
    }

    /**
     * Register allowed action types that a notification may present.
     */
    func registerActionTypes(_ call: CAPPluginCall) throws {
        guard let types = call.getArray("types", JSObject.self) else {
            throw CAPPluginError("Must provide types array as types option")
        }

        makeActionTypes(types)

        call.resolve()
    }

    /**
     * Check if Local Notifications are authorized and enabled
     */
    func areEnabled(_ call: CAPPluginCall) async -> JSObject {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == UNAuthorizationStatus.authorized
        let enabled = settings.notificationCenterSetting == UNNotificationSetting.enabled
        return [
            "value": enabled && authorized
        ]
    }

    /**
     * Get notifications in Notification Center
     */
    func getDeliveredNotifications(_ call: CAPPluginCall) async -> JSObject {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        return [
            "notifications": notifications.map { notificationDelegationHandler.makeNotificationRequestJSObject($0.request) }
        ]
    }

    /**
     * Remove specified notifications from Notification Center
     */
    func removeDeliveredNotifications(_ call: CAPPluginCall) throws {
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            throw CAPPluginError("Must supply notifications to remove")
        }

        let ids = notifications.map { "\($0["id"] ?? "")" }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        call.resolve()
    }

    /**
     * Remove all notifications from Notification Center
     */
    func removeAllDeliveredNotifications(_ call: CAPPluginCall) {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { error in
            if let error {
                CAPLog.print("⚡️ ", self.pluginId, "-", "Unable to reset the badge count: \(error.localizedDescription)")
            }
            call.resolve()
        }
    }

    func createChannel(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented()
    }

    func deleteChannel(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented()
    }

    func listChannels(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented()
    }
}
