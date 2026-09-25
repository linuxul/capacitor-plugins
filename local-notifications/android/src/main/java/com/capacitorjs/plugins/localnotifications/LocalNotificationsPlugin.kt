package com.capacitorjs.plugins.localnotifications

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
import androidx.activity.result.ActivityResult
import com.getcapacitor.Bridge
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.PermissionState
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import org.json.JSONException
import org.json.JSONObject

@CapacitorPlugin(
    name = "LocalNotifications",
    permissions = [Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = LocalNotificationsPlugin.LOCAL_NOTIFICATIONS)]
)
public class LocalNotificationsPlugin : Plugin() {
    private lateinit var manager: LocalNotificationManager
    public lateinit var notificationManager: NotificationManager
    private lateinit var notificationStorage: NotificationStorage
    private lateinit var notificationChannelManager: NotificationChannelManager

    override fun load() {
        super.load()
        notificationStorage = NotificationStorage(context)
        manager = LocalNotificationManager(notificationStorage, activity, context, bridge.config)
        manager.createNotificationChannel()
        notificationChannelManager = NotificationChannelManager(activity)
        notificationManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        staticBridge = bridge
    }

    override fun handleOnDestroy() {
        // The receivers reach the plugin through the bridge. Keeping it would keep the destroyed activity as well.
        if (staticBridge === bridge) {
            staticBridge = null
        }
    }

    override fun handleOnNewIntent(intent: Intent?) {
        super.handleOnNewIntent(intent)
        if (intent == null || Intent.ACTION_MAIN != intent.action) {
            return
        }
        val dataJson = manager.handleNotificationActionPerformed(intent, notificationStorage)
        if (dataJson != null) {
            notifyListeners("localNotificationActionPerformed", dataJson, true)
        }
    }

    /**
     * Schedule a notification call from JavaScript
     * Creates local notification in system.
     */
    @PluginMethod
    public fun schedule(call: PluginCall) {
        val localNotifications = LocalNotification.buildNotificationList(call) ?: return
        val ids = manager.schedule(call, localNotifications)
        if (ids != null) {
            notificationStorage.appendNotifications(localNotifications)
            val result = JSObject()
            val jsArray = JSArray()
            for (i in 0 until ids.length()) {
                try {
                    val notification = JSObject().put("id", ids.getInt(i))
                    jsArray.put(notification)
                } catch (ex: Exception) {
                }
            }
            result.put("notifications", jsArray)
            call.resolve(result)
        }
    }

    @PluginMethod
    public fun cancel(call: PluginCall) {
        manager.cancel(call)
    }

    @PluginMethod
    public fun getPending(call: PluginCall) {
        val notifications = notificationStorage.getSavedNotifications()
        val result = LocalNotification.buildLocalNotificationPendingList(notifications)
        call.resolve(result)
    }

    @PluginMethod
    public fun registerActionTypes(call: PluginCall) {
        val types = call.getArray("types")
        val typesArray = NotificationAction.buildTypes(types)
        if (typesArray == null) {
            // A type without an id used to end in a NullPointerException
            call.reject("Action type missing identifier")
            return
        }
        notificationStorage.writeActionGroup(typesArray)
        call.resolve()
    }

    @PluginMethod
    public fun areEnabled(call: PluginCall) {
        val data = JSObject()
        data.put("value", manager.areNotificationsEnabled())
        call.resolve(data)
    }

    @PluginMethod
    public fun getDeliveredNotifications(call: PluginCall) {
        val notifications = JSArray()
        val activeNotifications = notificationManager.activeNotifications

        for (notif in activeNotifications) {
            val jsNotif = JSObject()

            jsNotif.put("id", notif.id)
            jsNotif.put("tag", notif.tag)

            val notification: Notification? = notif.notification
            if (notification != null) {
                jsNotif.put("title", notification.extras.getCharSequence(Notification.EXTRA_TITLE))
                jsNotif.put("body", notification.extras.getCharSequence(Notification.EXTRA_TEXT))
                jsNotif.put("group", notification.group)
                jsNotif.put("groupSummary", 0 != (notification.flags and Notification.FLAG_GROUP_SUMMARY))

                val extras = JSObject()

                for (key in notification.extras.keySet()) {
                    @Suppress("DEPRECATION")
                    extras.put(key, notification.extras.get(key))
                }

                jsNotif.put("data", extras)
            }

            notifications.put(jsNotif)
        }

        val result = JSObject()
        result.put("notifications", notifications)
        call.resolve(result)
    }

    @PluginMethod
    public fun removeDeliveredNotifications(call: PluginCall) {
        val notifications = call.getArray("notifications")
        if (notifications == null) {
            // Used to end in a NullPointerException
            call.reject("Must provide notifications array as notifications option")
            return
        }

        var hasInvalidEntry = false
        try {
            for (o in notifications.toList<Any>()) {
                val notif = if (o is JSONObject) JSObject.fromJSONObject(o) else null
                val id = notif?.getInteger("id")
                if (notif == null || id == null) {
                    // A notification without an id used to end in a NullPointerException
                    hasInvalidEntry = true
                    continue
                }

                val tag = notif.getString("tag")
                if (tag == null) {
                    notificationManager.cancel(id)
                } else {
                    notificationManager.cancel(tag, id)
                }
            }
        } catch (e: JSONException) {
            call.reject(e.message, ex = e)
            return
        }

        // The valid entries are cancelled either way. Rejecting inside the loop and resolving here settled the call twice.
        if (hasInvalidEntry) {
            call.reject("Expected notifications to be a list of notification objects")
        } else {
            call.resolve()
        }
    }

    @PluginMethod
    public fun removeAllDeliveredNotifications(call: PluginCall) {
        notificationManager.cancelAll()
        call.resolve()
    }

    @PluginMethod
    public fun createChannel(call: PluginCall) {
        notificationChannelManager.createChannel(call)
    }

    @PluginMethod
    public fun deleteChannel(call: PluginCall) {
        notificationChannelManager.deleteChannel(call)
    }

    @PluginMethod
    public fun listChannels(call: PluginCall) {
        notificationChannelManager.listChannels(call)
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        if (getPermissionState(LOCAL_NOTIFICATIONS) == PermissionState.GRANTED) {
            val permissionsResultJSON = JSObject()
            permissionsResultJSON.put("display", getNotificationPermissionText())
            call.resolve(permissionsResultJSON)
        } else {
            requestPermissionForAlias(LOCAL_NOTIFICATIONS, call, "permissionsCallback")
        }
    }

    @PluginMethod
    public fun changeExactNotificationSetting(call: PluginCall) {
        startActivityForResult(
            call,
            Intent(ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + activity.packageName)),
            "alarmPermissionsCallback"
        )
    }

    @PluginMethod
    public fun checkExactNotificationSetting(call: PluginCall) {
        val permissionsResultJSON = JSObject()
        permissionsResultJSON.put("exact_alarm", getExactAlarmPermissionText())

        call.resolve(permissionsResultJSON)
    }

    @PermissionCallback
    private fun permissionsCallback(call: PluginCall) {
        val permissionsResultJSON = JSObject()
        permissionsResultJSON.put("display", getNotificationPermissionText())

        call.resolve(permissionsResultJSON)
    }

    @ActivityCallback
    private fun alarmPermissionsCallback(call: PluginCall?, result: ActivityResult?) {
        if (call == null) {
            return
        }
        checkExactNotificationSetting(call)
    }

    private fun getNotificationPermissionText(): String = if (manager.areNotificationsEnabled()) "granted" else "denied"

    private fun getExactAlarmPermissionText(): String {
        val alarmManager = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (alarmManager.canScheduleExactAlarms()) "granted" else "denied"
    }

    public companion object {
        internal const val LOCAL_NOTIFICATIONS: String = "display"

        @Volatile
        private var staticBridge: Bridge? = null

        public fun fireReceived(notification: JSObject?) {
            getLocalNotificationsInstance()?.notifyListeners("localNotificationReceived", notification, true)
        }

        public fun getLocalNotificationsInstance(): LocalNotificationsPlugin? {
            val handle = staticBridge?.getPlugin("LocalNotifications") ?: return null
            return handle.instance as LocalNotificationsPlugin
        }
    }
}
