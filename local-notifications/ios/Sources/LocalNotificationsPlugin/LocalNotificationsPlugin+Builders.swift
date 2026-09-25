import Foundation
import Capacitor
import UserNotifications

/// Builds the UserNotifications objects that `schedule` and `registerActionTypes` hand to the notification center.
extension LocalNotificationsPlugin {
    /**
     * Build the content for a notification.
     */
    func makeNotificationContent(_ notification: JSObject) throws -> UNNotificationContent {
        guard let title = notification["title"] as? String else {
            throw LocalNotificationError.contentNoTitle
        }
        guard let body = notification["body"] as? String else {
            throw LocalNotificationError.contentNoBody
        }

        let extra = notification["extra"] as? JSObject ?? [:]
        let schedule = notification["schedule"] as? JSObject ?? [:]
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: title, arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: body,
                                                                arguments: nil)

        content.userInfo = [
            "cap_extra": extra,
            "cap_schedule": schedule
        ]

        if let actionTypeId = notification["actionTypeId"] as? String {
            content.categoryIdentifier = actionTypeId
        }

        if let threadIdentifier = notification["threadIdentifier"] as? String {
            content.threadIdentifier = threadIdentifier
        }

        if let relevanceScore = notification["relevanceScore"] as? Double {
            content.relevanceScore = relevanceScore
        }

        if let interruptionLevelString = notification["interruptionLevel"] as? String,
           let interruptionLevel = LocalNotificationsPlugin.interruptionLevel(interruptionLevelString) {
            content.interruptionLevel = interruptionLevel
        }

        if let sound = notification["sound"] as? String {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        }

        if let attachments = notification["attachments"] as? [JSObject] {
            content.attachments = try makeAttachments(attachments)
        }

        return content
    }

    /// The interruption level named `name`, or nil for a name the plugin does not know.
    static func interruptionLevel(_ name: String) -> UNNotificationInterruptionLevel? {
        switch name {
        case "active":
            return .active
        case "critical":
            return .critical
        case "passive":
            return .passive
        case "timeSensitive":
            return .timeSensitive
        default:
            return nil
        }
    }

    /**
     * Build a notification trigger, such as triggering each N seconds, or
     * on a certain date "shape" (such as every first of the month)
     *
     * Throws `triggerDateNotInFuture` for an `at` date that is not after `now`: the caller rejects the call and
     * schedules nothing, where it used to reject and then deliver the notification immediately.
     */
    func handleScheduledNotification(_ schedule: JSObject, now: Date = Date()) throws -> UNNotificationTrigger? {
        let every = schedule["every"] as? String
        let count = schedule["count"] as? Int ?? 1
        let repeats = schedule["repeats"] as? Bool ?? false

        // If there's a specific date for this notification
        if let scheduleDate = schedule["at"] as? Date {
            guard scheduleDate > now else {
                throw LocalNotificationError.triggerDateNotInFuture
            }
            let interval = scheduleDate.timeIntervalSince(now)

            // Notifications that repeat have to be at least a minute between each other
            if repeats && interval < 60 {
                throw LocalNotificationError.triggerRepeatIntervalTooShort
            }

            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
        }

        // If this notification should repeat every count of day/month/week/etc. or on a certain
        // matching set of date components
        if let components = schedule["on"] as? JSObject {
            let dateComponents = getDateComponents(components)
            return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        }

        if let every, let repeatDateInterval = getRepeatDateInterval(every, count, from: now) {
            // A repeating trigger under a minute raises an Objective-C exception, which crashed the app.
            guard repeatDateInterval.duration >= 60 else {
                throw LocalNotificationError.triggerRepeatIntervalTooShort
            }
            return UNTimeIntervalNotificationTrigger(timeInterval: repeatDateInterval.duration, repeats: true)
        }

        return nil
    }

    /**
     * Given our schedule format, return a DateComponents object
     * that only contains the components passed in.
     */
    func getDateComponents(_ components: JSObject) -> DateComponents {
        var dateInfo = DateComponents()

        if let year = components["year"] as? Int {
            dateInfo.year = year
        }
        if let month = components["month"] as? Int {
            dateInfo.month = month
        }
        if let day = components["day"] as? Int {
            dateInfo.day = day
        }
        if let hour = components["hour"] as? Int {
            dateInfo.hour = hour
        }
        if let minute = components["minute"] as? Int {
            dateInfo.minute = minute
        }
        if let second = components["second"] as? Int {
            dateInfo.second = second
        }
        if let weekday = components["weekday"] as? Int {
            dateInfo.weekday = weekday
        }
        return dateInfo
    }

    /**
     * Compute the difference between the string representation of a date
     * interval and today. For example, if every is "month", then we
     * return the interval between today and a month from today.
     *
     * Returns nil for an unknown unit, and for a count that does not move forward in time (a DateInterval that ends
     * before it starts traps).
     */
    func getRepeatDateInterval(_ every: String, _ count: Int, from now: Date = Date()) -> DateInterval? {
        let component: Calendar.Component
        var value = count
        switch every {
        case "year":
            component = .year
        case "month":
            component = .month
        case "two-weeks":
            component = .weekOfYear
            value = 2 * count
        case "week":
            component = .weekOfYear
        case "day":
            component = .day
        case "hour":
            component = .hour
        case "minute":
            component = .minute
        case "second":
            component = .second
        default:
            return nil
        }
        guard let newDate = Calendar.current.date(byAdding: component, value: value, to: now), newDate >= now else {
            return nil
        }
        return DateInterval(start: now, end: newDate)
    }

    /**
     * Make required UNNotificationCategory entries for action types
     */
    func makeActionTypes(_ actionTypes: [JSObject]) {
        var createdCategories = [UNNotificationCategory]()

        let generalCategory = UNNotificationCategory(identifier: "GENERAL",
                                                     actions: [],
                                                     intentIdentifiers: [],
                                                     options: .customDismissAction)

        createdCategories.append(generalCategory)
        for type in actionTypes {
            guard let id = type["id"] as? String else {
                CAPLog.print("⚡️ ", self.pluginId, "-", "Action type must have an id field")
                continue
            }
            let hiddenBodyPlaceholder = type["iosHiddenPreviewsBodyPlaceholder"] as? String ?? ""
            let actions = type["actions"] as? [JSObject] ?? []

            let newActions = makeActions(actions)

            let newCategory = UNNotificationCategory(identifier: id,
                                                     actions: newActions,
                                                     intentIdentifiers: [],
                                                     hiddenPreviewsBodyPlaceholder: hiddenBodyPlaceholder,
                                                     options: makeCategoryOptions(type))

            createdCategories.append(newCategory)
        }

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(Set(createdCategories))
    }

    /**
     * Build the required UNNotificationAction objects for each action type registered.
     */
    func makeActions(_ actions: [JSObject]) -> [UNNotificationAction] {
        var createdActions = [UNNotificationAction]()

        for action in actions {
            guard let id = action["id"] as? String else {
                CAPLog.print("⚡️ ", self.pluginId, "-", "Action must have an id field")
                continue
            }
            let title = action["title"] as? String ?? ""
            let input = action["input"] as? Bool ?? false

            var newAction: UNNotificationAction
            if input {
                let inputPlaceholder = action["inputPlaceholder"] as? String ?? ""

                if let inputButtonTitle = action["inputButtonTitle"] as? String {
                    newAction = UNTextInputNotificationAction(identifier: id,
                                                              title: title,
                                                              options: makeActionOptions(action),
                                                              textInputButtonTitle: inputButtonTitle,
                                                              textInputPlaceholder: inputPlaceholder)
                } else {
                    newAction = UNTextInputNotificationAction(identifier: id, title: title, options: makeActionOptions(action))
                }
            } else {
                newAction = UNNotificationAction(identifier: id,
                                                 title: title,
                                                 options: makeActionOptions(action))
            }
            createdActions.append(newAction)
        }

        return createdActions
    }

    /**
     * Make options for UNNotificationActions
     */
    func makeActionOptions(_ action: JSObject) -> UNNotificationActionOptions {
        let foreground = action["foreground"] as? Bool ?? false
        let destructive = action["destructive"] as? Bool ?? false
        let requiresAuthentication = action["requiresAuthentication"] as? Bool ?? false

        if foreground {
            return .foreground
        }
        if destructive {
            return .destructive
        }
        if requiresAuthentication {
            return .authenticationRequired
        }
        return UNNotificationActionOptions(rawValue: 0)
    }

    /**
     * Make options for UNNotificationCategoryActions
     */
    func makeCategoryOptions(_ type: JSObject) -> UNNotificationCategoryOptions {
        let customDismiss = type["iosCustomDismissAction"] as? Bool ?? false
        let carPlay = type["iosAllowInCarPlay"] as? Bool ?? false
        let hiddenPreviewsShowTitle = type["iosHiddenPreviewsShowTitle"] as? Bool ?? false
        let hiddenPreviewsShowSubtitle = type["iosHiddenPreviewsShowSubtitle"] as? Bool ?? false

        if customDismiss {
            return .customDismissAction
        }
        if carPlay {
            return .allowInCarPlay
        }

        if hiddenPreviewsShowTitle {
            return .hiddenPreviewsShowTitle
        }
        if hiddenPreviewsShowSubtitle {
            return .hiddenPreviewsShowSubtitle
        }

        return UNNotificationCategoryOptions(rawValue: 0)
    }

    /**
     * Build the UNNotificationAttachment object for each attachment supplied.
     */
    func makeAttachments(_ attachments: [JSObject]) throws -> [UNNotificationAttachment] {
        var createdAttachments = [UNNotificationAttachment]()

        for attachment in attachments {
            guard let id = attachment["id"] as? String else {
                throw LocalNotificationError.attachmentNoId
            }
            guard let url = attachment["url"] as? String else {
                throw LocalNotificationError.attachmentNoUrl
            }
            guard let urlObject = makeAttachmentUrl(url) else {
                throw LocalNotificationError.attachmentFileNotFound(path: url)
            }

            let options = attachment["options"] as? JSObject ?? [:]

            do {
                let newAttachment = try UNNotificationAttachment(identifier: id, url: urlObject, options: makeAttachmentOptions(options))
                createdAttachments.append(newAttachment)
            } catch {
                throw LocalNotificationError.attachmentUnableToCreate(error.localizedDescription)
            }
        }

        return createdAttachments
    }

    /**
     * Get the internal URL for the attachment URL
     */
    func makeAttachmentUrl(_ path: String) -> URL? {
        guard let webURL = URL(string: path) else {
            return nil
        }

        return bridge?.localURL(fromWebURL: webURL)
    }

    /**
     * Build the options for the attachment, if any. (For example: the clipping rectangle to use
     * for image attachments)
     */
    func makeAttachmentOptions(_ options: JSObject) -> JSObject {
        // The JavaScript option name, and the UNNotificationAttachment option it sets.
        let attachmentKeys = [
            ("iosUNNotificationAttachmentOptionsTypeHintKey", UNNotificationAttachmentOptionsTypeHintKey),
            ("iosUNNotificationAttachmentOptionsThumbnailHiddenKey", UNNotificationAttachmentOptionsThumbnailHiddenKey),
            ("iosUNNotificationAttachmentOptionsThumbnailClippingRectKey", UNNotificationAttachmentOptionsThumbnailClippingRectKey),
            ("iosUNNotificationAttachmentOptionsThumbnailTimeKey", UNNotificationAttachmentOptionsThumbnailTimeKey)
        ]
        var opts: JSObject = [:]
        for (optionName, attachmentKey) in attachmentKeys {
            if let value = options[optionName] as? String {
                opts[attachmentKey] = value
            }
        }
        return opts
    }
}
