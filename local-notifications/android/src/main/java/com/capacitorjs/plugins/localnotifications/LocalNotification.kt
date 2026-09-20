package com.capacitorjs.plugins.localnotifications

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PluginCall
import com.getcapacitor.plugin.util.AssetUtil
import java.text.ParseException
import org.json.JSONException
import org.json.JSONObject

/**
 * Local notification object mapped from json plugin
 */
public class LocalNotification {
    public var title: String? = null
    public var body: String? = null
    public var largeBody: String? = null
    public var summaryText: String? = null
    public var id: Int? = null
    private var sound: String? = null
    private var smallIcon: String? = null
    private var largeIcon: String? = null
    private var iconColor: String? = null
    public var actionTypeId: String? = null
    public var group: String? = null
    public var inboxList: List<String>? = null
    public var isGroupSummary: Boolean = false
    public var isOngoing: Boolean = false
    public var isAutoCancel: Boolean = false
    public var extra: JSObject? = null
    public var attachments: List<LocalNotificationAttachment>? = null
    public var schedule: LocalNotificationSchedule? = null
    public var channelId: String? = null
    public var source: String? = null

    public fun getSound(context: Context, defaultSound: Int): String? {
        var soundPath: String? = null
        var resId = AssetUtil.RESOURCE_ID_ZERO_VALUE
        val name = AssetUtil.getResourceBaseName(sound)
        if (name != null) {
            resId = AssetUtil.getResourceID(context, name, "raw")
        }
        if (resId == AssetUtil.RESOURCE_ID_ZERO_VALUE) {
            resId = defaultSound
        }
        if (resId != AssetUtil.RESOURCE_ID_ZERO_VALUE) {
            soundPath = ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + context.packageName + "/" + resId
        }
        return soundPath
    }

    public fun setSound(sound: String?) {
        this.sound = sound
    }

    public fun setSmallIcon(smallIcon: String?) {
        this.smallIcon = AssetUtil.getResourceBaseName(smallIcon)
    }

    public fun setLargeIcon(largeIcon: String?) {
        this.largeIcon = AssetUtil.getResourceBaseName(largeIcon)
    }

    // use the one defined local before trying for a globally defined color
    public fun getIconColor(globalColor: String?): String? = iconColor ?: globalColor

    public fun setIconColor(iconColor: String?) {
        this.iconColor = iconColor
    }

    public fun getSmallIcon(context: Context, defaultIcon: Int): Int {
        var resId = AssetUtil.RESOURCE_ID_ZERO_VALUE

        if (smallIcon != null) {
            resId = AssetUtil.getResourceID(context, smallIcon, "drawable")
        }

        if (resId == AssetUtil.RESOURCE_ID_ZERO_VALUE) {
            resId = defaultIcon
        }

        return resId
    }

    public fun getLargeIcon(context: Context): Bitmap? {
        if (largeIcon != null) {
            val resId = AssetUtil.getResourceID(context, largeIcon, "drawable")
            return BitmapFactory.decodeResource(context.resources, resId)
        }

        return null
    }

    public val isScheduled: Boolean
        get() = schedule?.let { it.on != null || it.at != null || it.every != null } ?: false

    override fun toString(): String = "LocalNotification{" +
        "title='" + title + '\'' +
        ", body='" + body + '\'' +
        ", id=" + id +
        ", sound='" + sound + '\'' +
        ", smallIcon='" + smallIcon + '\'' +
        ", iconColor='" + iconColor + '\'' +
        ", actionTypeId='" + actionTypeId + '\'' +
        ", group='" + group + '\'' +
        ", extra=" + extra +
        ", attachments=" + attachments +
        ", schedule=" + schedule +
        ", groupSummary=" + isGroupSummary +
        ", ongoing=" + isOngoing +
        ", autoCancel=" + isAutoCancel +
        '}'

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false

        other as LocalNotification

        return title == other.title &&
            body == other.body &&
            largeBody == other.largeBody &&
            id == other.id &&
            sound == other.sound &&
            smallIcon == other.smallIcon &&
            largeIcon == other.largeIcon &&
            iconColor == other.iconColor &&
            actionTypeId == other.actionTypeId &&
            group == other.group &&
            extra == other.extra &&
            attachments == other.attachments &&
            inboxList == other.inboxList &&
            isGroupSummary == other.isGroupSummary &&
            isOngoing == other.isOngoing &&
            isAutoCancel == other.isAutoCancel &&
            schedule == other.schedule
    }

    override fun hashCode(): Int {
        var result = title?.hashCode() ?: 0
        result = 31 * result + (body?.hashCode() ?: 0)
        result = 31 * result + (id?.hashCode() ?: 0)
        result = 31 * result + (sound?.hashCode() ?: 0)
        result = 31 * result + (smallIcon?.hashCode() ?: 0)
        result = 31 * result + (iconColor?.hashCode() ?: 0)
        result = 31 * result + (actionTypeId?.hashCode() ?: 0)
        result = 31 * result + (group?.hashCode() ?: 0)
        result = 31 * result + isGroupSummary.hashCode()
        result = 31 * result + isOngoing.hashCode()
        result = 31 * result + isAutoCancel.hashCode()
        result = 31 * result + (extra?.hashCode() ?: 0)
        result = 31 * result + (attachments?.hashCode() ?: 0)
        result = 31 * result + (schedule?.hashCode() ?: 0)
        return result
    }

    public fun setExtraFromString(extraFromString: String) {
        try {
            val jsonObject = JSONObject(extraFromString)
            extra = JSObject.fromJSONObject(jsonObject)
        } catch (e: JSONException) {
            Logger.error(Logger.tags("LN"), "Cannot rebuild extra data", e)
        }
    }

    public companion object {
        /**
         * Build list of the notifications from remote plugin call
         */
        public fun buildNotificationList(call: PluginCall): List<LocalNotification>? {
            val notificationArray = call.getArray("notifications")
            if (notificationArray == null) {
                call.reject("Must provide notifications array as notifications option")
                return null
            }
            val resultLocalNotifications = ArrayList<LocalNotification>(notificationArray.length())
            val notificationsJson: List<JSONObject> =
                try {
                    notificationArray.toList()
                } catch (e: JSONException) {
                    call.reject("Provided notification format is invalid")
                    return null
                }

            for (jsonNotification in notificationsJson) {
                val notification: JSObject
                try {
                    val identifier = jsonNotification.getLong("id")
                    if (identifier > Int.MAX_VALUE || identifier < Int.MIN_VALUE) {
                        call.reject("The identifier should be a Java int")
                        return null
                    }
                    notification = JSObject.fromJSONObject(jsonNotification)
                } catch (e: JSONException) {
                    call.reject("Invalid JSON object sent to NotificationPlugin", ex = e)
                    return null
                }

                try {
                    resultLocalNotifications.add(buildNotificationFromJSObject(notification))
                } catch (e: ParseException) {
                    call.reject("Invalid date format sent to Notification plugin", ex = e)
                    return null
                }
            }
            return resultLocalNotifications
        }

        @Throws(ParseException::class)
        public fun buildNotificationFromJSObject(jsonObject: JSObject): LocalNotification {
            val localNotification = LocalNotification()
            localNotification.source = jsonObject.toString()
            localNotification.id = jsonObject.getInteger("id")
            localNotification.body = jsonObject.getString("body")
            localNotification.largeBody = jsonObject.getString("largeBody")
            localNotification.summaryText = jsonObject.getString("summaryText")
            localNotification.actionTypeId = jsonObject.getString("actionTypeId")
            localNotification.group = jsonObject.getString("group")
            localNotification.setSound(jsonObject.getString("sound"))
            localNotification.title = jsonObject.getString("title")
            localNotification.setSmallIcon(jsonObject.getString("smallIcon"))
            localNotification.setLargeIcon(jsonObject.getString("largeIcon"))
            localNotification.setIconColor(jsonObject.getString("iconColor"))
            localNotification.attachments = LocalNotificationAttachment.getAttachments(jsonObject)
            localNotification.isGroupSummary = jsonObject.getBoolean("groupSummary", false) ?: false
            localNotification.channelId = jsonObject.getString("channelId")
            val schedule = jsonObject.getJSObject("schedule")
            if (schedule != null) {
                localNotification.schedule = LocalNotificationSchedule(schedule)
            }
            localNotification.extra = jsonObject.getJSObject("extra")
            localNotification.isOngoing = jsonObject.getBoolean("ongoing", false) ?: false
            localNotification.isAutoCancel = jsonObject.getBoolean("autoCancel", true) ?: true

            try {
                val inboxList = jsonObject.getJSONArray("inboxList")
                if (inboxList != null) {
                    val inboxStringList = ArrayList<String>()
                    for (i in 0 until inboxList.length()) {
                        inboxStringList.add(inboxList.getString(i))
                    }
                    localNotification.inboxList = inboxStringList
                }
            } catch (ex: Exception) {
            }

            return localNotification
        }

        public fun getLocalNotificationPendingList(call: PluginCall): List<Int>? {
            var notifications: List<JSONObject>? = null
            try {
                notifications = call.getArray("notifications")?.toList()
            } catch (e: JSONException) {
            }
            if (notifications.isNullOrEmpty()) {
                call.reject("Must provide notifications array as notifications option")
                return null
            }
            val notificationsList = ArrayList<Int>(notifications.size)
            for (notificationToCancel in notifications) {
                try {
                    notificationsList.add(notificationToCancel.getInt("id"))
                } catch (e: JSONException) {
                }
            }
            return notificationsList
        }

        public fun buildLocalNotificationPendingList(notifications: List<LocalNotification>): JSObject {
            val result = JSObject()
            val jsArray = JSArray()
            for (notification in notifications) {
                val jsNotification = JSObject()
                jsNotification.put("id", notification.id)
                jsNotification.put("title", notification.title)
                jsNotification.put("body", notification.body)
                val schedule = notification.schedule
                if (schedule != null) {
                    val jsSchedule = JSObject()
                    jsSchedule.put("at", schedule.at)
                    jsSchedule.put("every", schedule.every)
                    jsSchedule.put("count", schedule.count)
                    jsSchedule.put("on", schedule.onObj)
                    jsSchedule.put("repeats", schedule.isRepeating)
                    jsNotification.put("schedule", jsSchedule)
                }

                jsNotification.put("extra", notification.extra)

                jsArray.put(jsNotification)
            }
            result.put("notifications", jsArray)
            return result
        }
    }
}
