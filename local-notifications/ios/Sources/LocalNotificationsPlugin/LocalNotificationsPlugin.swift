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
        .promise("requestPermissions", LocalNotificationsPlugin.requestPermissions),
        .promise("checkPermissions", LocalNotificationsPlugin.checkPermissions),
        .promise("checkExactNotificationSetting", LocalNotificationsPlugin.checkExactNotificationSetting),
        .promise("changeExactNotificationSetting", LocalNotificationsPlugin.changeExactNotificationSetting),
        .promise("cancel", LocalNotificationsPlugin.cancel),
        .promise("getPending", LocalNotificationsPlugin.getPending),
        .promise("registerActionTypes", LocalNotificationsPlugin.registerActionTypes),
        .promise("areEnabled", LocalNotificationsPlugin.areEnabled),
        .promise("getDeliveredNotifications", LocalNotificationsPlugin.getDeliveredNotifications),
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

    /**
     * Schedule a notification.
     */
    func schedule(_ call: CAPPluginCall) {
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            call.reject("Must provide notifications array as notifications option")
            return
        }
        // Build every request before adding any, so a notification the plugin rejects schedules none of the batch.
        var requests = [(request: UNNotificationRequest, notification: JSObject)]()
        for notification in notifications {
            guard let identifier = notification["id"] as? Int else {
                call.reject("Notification missing identifier")
                return
            }

            let content: UNNotificationContent
            do {
                content = try makeNotificationContent(notification)
            } catch {
                CAPLog.print(error.localizedDescription)
                call.reject("Unable to make notification", nil, error)
                return
            }

            var trigger: UNNotificationTrigger?
            do {
                if let schedule = notification["schedule"] as? JSObject {
                    trigger = try handleScheduledNotification(schedule)
                }
            } catch LocalNotificationError.triggerDateNotInFuture {
                call.reject("Scheduled time must be *after* current time")
                return
            } catch {
                call.reject("Unable to create notification, trigger failed", nil, error)
                return
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
    override public func requestPermissions(_ call: CAPPluginCall) {
        self.notificationDelegationHandler.requestPermissions { granted, error in
            if let error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve(["display": granted ? "granted" : "denied"])
        }
    }

    override public func checkPermissions(_ call: CAPPluginCall) {
        self.notificationDelegationHandler.checkPermissions { status in
            let permission: String

            switch status {
            case .authorized, .ephemeral, .provisional:
                permission = "granted"
            case .denied:
                permission = "denied"
            case .notDetermined:
                permission = "prompt"
            @unknown default:
                permission = "prompt"
            }

            call.resolve(["display": permission])
        }
    }

    public func checkExactNotificationSetting(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    public func changeExactNotificationSetting(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    /**
     * Cancel notifications by id
     */
    func cancel(_ call: CAPPluginCall) {
        guard let notifications = call.getArray("notifications", JSObject.self), notifications.count > 0 else {
            call.reject("Must supply notifications to cancel")
            return
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
    func getPending(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: { (notifications) in
            CAPLog.print("num of pending notifications \(notifications.count)")
            CAPLog.print(notifications)

            let ret = notifications.compactMap({ [weak self] (notification) -> JSObject? in
                return self?.notificationDelegationHandler.makePendingNotificationRequestJSObject(notification)
            })

            call.resolve([
                "notifications": ret
            ])
        })
    }

    /**
     * Register allowed action types that a notification may present.
     */
    func registerActionTypes(_ call: CAPPluginCall) {
        guard let types = call.getArray("types", JSObject.self) else {
            call.reject("Must provide types array as types option")
            return
        }

        makeActionTypes(types)

        call.resolve()
    }

    /**
     * Check if Local Notifications are authorized and enabled
     */
    func areEnabled(_ call: CAPPluginCall) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { (settings) in
            let authorized = settings.authorizationStatus == UNAuthorizationStatus.authorized
            let enabled = settings.notificationCenterSetting == UNNotificationSetting.enabled
            call.resolve([
                "value": enabled && authorized
            ])
        }
    }

    /**
     * Get notifications in Notification Center
     */
    func getDeliveredNotifications(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { (notifications) in
            let ret = notifications.map({ (notification) -> [String: Any] in
                return self.notificationDelegationHandler.makeNotificationRequestJSObject(notification.request)
            })
            call.resolve([
                "notifications": ret
            ])
        })
    }

    /**
     * Remove specified notifications from Notification Center
     */
    func removeDeliveredNotifications(_ call: CAPPluginCall) {
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            call.reject("Must supply notifications to remove")
            return
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

    func createChannel(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    func deleteChannel(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    func listChannels(_ call: CAPPluginCall) {
        call.unimplemented()
    }
}
