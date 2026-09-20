package com.capacitorjs.plugins.localnotifications

import android.content.Context
import android.content.SharedPreferences
import com.getcapacitor.JSObject
import java.text.ParseException
import org.json.JSONException

/**
 * Class used to abstract storage for notification data
 */
public class NotificationStorage(private val context: Context) {
    /**
     * Persist the id of currently scheduled notification
     */
    public fun appendNotifications(localNotifications: List<LocalNotification>) {
        val storage = getStorage(NOTIFICATION_STORE_ID)
        val editor = storage.edit()
        for (request in localNotifications) {
            if (request.isScheduled) {
                // A scheduled notification always has an id; one without was a NullPointerException before
                val id = request.id ?: continue
                editor.putString(id.toString(), request.source)
            }
        }
        editor.apply()
    }

    public fun getSavedNotificationIds(): List<String> {
        val storage = getStorage(NOTIFICATION_STORE_ID)
        val all = storage.all
        if (all != null) {
            return ArrayList(all.keys)
        }
        return ArrayList()
    }

    public fun getSavedNotifications(): List<LocalNotification> {
        val storage = getStorage(NOTIFICATION_STORE_ID)
        val all = storage.all
        if (all != null) {
            val notifications = ArrayList<LocalNotification>()
            for (key in all.keys) {
                val notificationString = all[key] as? String
                val jsNotification = getNotificationFromJSONString(notificationString)
                if (jsNotification != null) {
                    try {
                        val notification = LocalNotification.buildNotificationFromJSObject(jsNotification)
                        notifications.add(notification)
                    } catch (ex: ParseException) {
                    }
                }
            }

            return notifications
        }

        return ArrayList()
    }

    public fun getNotificationFromJSONString(notificationString: String?): JSObject? {
        if (notificationString == null) {
            return null
        }

        return try {
            JSObject(notificationString)
        } catch (ex: JSONException) {
            null
        }
    }

    public fun getSavedNotificationAsJSObject(key: String): JSObject? {
        val storage = getStorage(NOTIFICATION_STORE_ID)
        val notificationString =
            try {
                storage.getString(key, null)
            } catch (ex: ClassCastException) {
                return null
            }

        return getNotificationFromJSONString(notificationString)
    }

    public fun getSavedNotification(key: String): LocalNotification? {
        val jsNotification = getSavedNotificationAsJSObject(key) ?: return null

        return try {
            LocalNotification.buildNotificationFromJSObject(jsNotification)
        } catch (ex: ParseException) {
            null
        }
    }

    /**
     * Remove the stored notifications
     */
    public fun deleteNotification(id: String) {
        val editor = getStorage(NOTIFICATION_STORE_ID).edit()
        editor.remove(id)
        editor.apply()
    }

    /**
     * Shared private preferences for the application.
     */
    private fun getStorage(key: String): SharedPreferences = context.getSharedPreferences(key, Context.MODE_PRIVATE)

    /**
     * Writes new action types (actions that being displayed in notification) to storage.
     * Write will override previous data.
     *
     * @param typesMap - map with groupId and actionArray assigned to group
     */
    public fun writeActionGroup(typesMap: Map<String, Array<NotificationAction>>) {
        for ((id, notificationActions) in typesMap) {
            val editor = getStorage(ACTION_TYPES_ID + id).edit()
            editor.clear()
            editor.putInt("count", notificationActions.size)
            for (i in notificationActions.indices) {
                editor.putString("id$i", notificationActions[i].id)
                editor.putString("title$i", notificationActions[i].title)
                editor.putBoolean("input$i", notificationActions[i].isInput)
            }
            editor.apply()
        }
    }

    /**
     * Retrieve array of notification actions per ActionTypeId
     *
     * @param forId - id of the group
     */
    public fun getActionGroup(forId: String): Array<NotificationAction> {
        val storage = getStorage(ACTION_TYPES_ID + forId)
        val count = storage.getInt("count", 0)
        return Array(count) { i ->
            val id = storage.getString("id$i", "")
            val title = storage.getString("title$i", "")
            val input = storage.getBoolean("input$i", false)
            NotificationAction(id, title, input)
        }
    }

    private companion object {
        // Key for private preferences
        private const val NOTIFICATION_STORE_ID = "NOTIFICATION_STORE"

        // Key used to save action types
        private const val ACTION_TYPES_ID = "ACTION_TYPE_STORE"
    }
}
