import Foundation
import Capacitor
import UIKit
import UserNotifications

enum PushNotificationError: Error {
    case tokenParsingFailed
    case tokenRegistrationFailed
}

enum PushNotificationsPermissions: String {
    case prompt
    case denied
    case granted
}

@objc(PushNotificationsPlugin)
public class PushNotificationsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PushNotificationsPlugin"
    public let jsName = "PushNotifications"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("register", PushNotificationsPlugin.register),
        .promise("unregister", PushNotificationsPlugin.unregister),
        .async("checkPermissions", PushNotificationsPlugin.checkNotificationPermissions),
        .async("requestPermissions", PushNotificationsPlugin.requestNotificationPermissions),
        .async("getDeliveredNotifications", PushNotificationsPlugin.getDeliveredNotifications),
        .promise("removeAllDeliveredNotifications", PushNotificationsPlugin.removeAllDeliveredNotifications),
        .promise("removeDeliveredNotifications", PushNotificationsPlugin.removeDeliveredNotifications),
        .promise("createChannel", PushNotificationsPlugin.createChannel),
        .promise("listChannels", PushNotificationsPlugin.listChannels),
        .promise("deleteChannel", PushNotificationsPlugin.deleteChannel)
    ]
    static let registrationNotCalledMessage = "event capacitorDidRegisterForRemoteNotifications not called.  Visit https://capacitorjs.com/docs/apis/push-notifications for more information"
    private let notificationDelegateHandler = PushNotificationsHandler()
    private var appDelegateRegistrationCalled: Bool = false

    override public func load() {
        self.bridge?.notificationRouter.pushNotificationHandler = self.notificationDelegateHandler
        self.notificationDelegateHandler.plugin = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didRegisterForRemoteNotificationsWithDeviceToken(notification:)),
                                               name: .capacitorDidRegisterForRemoteNotifications,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didFailToRegisterForRemoteNotificationsWithError(notification:)),
                                               name: .capacitorDidFailToRegisterForRemoteNotifications,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // register, unregister and the removals stay synchronous: the bridge queue runs them in the order of the calls
    // (register and unregister hand their UIKit call to the main queue in that order), which async methods would not
    // keep. The permission methods and getDeliveredNotifications only ask the notification center, and await it.

    /**
     * Register for push notifications
     */
    func register(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        call.resolve()
    }

    /**
     * Unregister for remote notifications
     */
    func unregister(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            UIApplication.shared.unregisterForRemoteNotifications()
            call.resolve()
        }
    }

    /**
     * Request notification permission
     */
    func requestNotificationPermissions(_ call: CAPPluginCall) async throws -> JSObject {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            throw CAPPluginError(error.localizedDescription, underlyingError: error)
        }
        let result: PushNotificationsPermissions = granted ? .granted : .denied
        return ["receive": result.rawValue]
    }

    /**
     * Check notification permission
     */
    func checkNotificationPermissions(_ call: CAPPluginCall) async -> JSObject {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return ["receive": PushNotificationsPlugin.permission(for: settings.authorizationStatus).rawValue]
    }

    /// The permission state JavaScript receives for an authorization status.
    static func permission(for status: UNAuthorizationStatus) -> PushNotificationsPermissions {
        switch status {
        case .notDetermined:
            return .prompt
        case .denied:
            return .denied
        case .ephemeral, .authorized, .provisional:
            return .granted
        @unknown default:
            return .prompt
        }
    }

    /**
     * Get notifications in Notification Center
     */
    func getDeliveredNotifications(_ call: CAPPluginCall) async throws -> JSObject {
        if !appDelegateRegistrationCalled {
            throw CAPPluginError(PushNotificationsPlugin.registrationNotCalledMessage)
        }
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        return [
            "notifications": notifications.map { notificationDelegateHandler.makeNotificationRequestJSObject($0.request) }
        ]
    }

    /**
     * Remove specified notifications from Notification Center
     */
    func removeDeliveredNotifications(_ call: CAPPluginCall) throws {
        if !appDelegateRegistrationCalled {
            throw CAPPluginError(PushNotificationsPlugin.registrationNotCalledMessage)
        }
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            throw CAPPluginError("Must supply notifications to remove")
        }

        let ids = notifications.map { $0["id"] as? String ?? "" }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        call.resolve()
    }

    /**
     * Remove all notifications from Notification Center
     */
    func removeAllDeliveredNotifications(_ call: CAPPluginCall) throws {
        if !appDelegateRegistrationCalled {
            throw CAPPluginError(PushNotificationsPlugin.registrationNotCalledMessage)
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        // applicationIconBadgeNumber is deprecated since iOS 17; the notification center sets the badge from any thread.
        center.setBadgeCount(0) { error in
            if let error {
                CAPLog.print("⚡️ ", self.pluginId, "-", "Unable to reset the badge count: \(error.localizedDescription)")
            }
            call.resolve()
        }
    }

    func createChannel(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented("Not available on iOS")
    }

    func deleteChannel(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented("Not available on iOS")
    }

    func listChannels(_ call: CAPPluginCall) throws {
        throw CAPPluginError.unimplemented("Not available on iOS")
    }

    @objc public func didRegisterForRemoteNotificationsWithDeviceToken(notification: NSNotification) {
        appDelegateRegistrationCalled = true
        if let deviceToken = notification.object as? Data {
            let deviceTokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
            notifyListeners("registration", data: [
                "value": deviceTokenString
            ])
        } else if let stringToken = notification.object as? String {
            notifyListeners("registration", data: [
                "value": stringToken
            ])
        } else {
            notifyListeners("registrationError", data: [
                "error": PushNotificationError.tokenParsingFailed.localizedDescription
            ])
        }
    }

    @objc public func didFailToRegisterForRemoteNotificationsWithError(notification: NSNotification) {
        appDelegateRegistrationCalled = true
        guard let error = notification.object as? Error else {
            return
        }
        notifyListeners("registrationError", data: [
            "error": error.localizedDescription
        ])
    }
}
