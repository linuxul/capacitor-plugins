package com.capacitorjs.plugins.pushnotifications

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.getcapacitor.Bridge
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PermissionState
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import com.google.android.gms.tasks.Tasks
import com.google.firebase.messaging.CommonNotificationBuilder
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.ImageDownload
import com.google.firebase.messaging.NotificationParams
import com.google.firebase.messaging.RemoteMessage
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.json.JSONException
import org.json.JSONObject

@CapacitorPlugin(
    name = "PushNotifications",
    permissions = [Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = PushNotificationsPlugin.PUSH_NOTIFICATIONS)]
)
public class PushNotificationsPlugin : Plugin() {
    public lateinit var notificationManager: NotificationManager

    @JvmField
    public var firebaseMessagingService: MessagingService? = null
    private lateinit var notificationChannelManager: NotificationChannelManager

    override fun load() {
        notificationManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        firebaseMessagingService = MessagingService()

        staticBridge = bridge
        lastMessage?.let {
            fireNotification(it)
            lastMessage = null
        }

        notificationChannelManager = NotificationChannelManager(activity, notificationManager, config)
    }

    override fun handleOnNewIntent(intent: Intent?) {
        super.handleOnNewIntent(intent)
        val bundle = intent?.extras
        if (bundle != null && bundle.containsKey("google.message_id")) {
            val notificationJson = JSObject()
            val dataObject = JSObject()
            for (key in bundle.keySet()) {
                if (key == "google.message_id") {
                    notificationJson.put("id", bundle.getString(key))
                } else {
                    @Suppress("DEPRECATION")
                    dataObject.put(key, bundle.get(key))
                }
            }
            notificationJson.put("data", dataObject)
            val actionJson = JSObject()
            actionJson.put("actionId", "tap")
            actionJson.put("notification", notificationJson)
            notifyListeners("pushNotificationActionPerformed", actionJson, true)
        }
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        if (getPermissionState(PUSH_NOTIFICATIONS) == PermissionState.GRANTED) {
            val permissionsResultJSON = JSObject()
            permissionsResultJSON.put("receive", "granted")
            call.resolve(permissionsResultJSON)
        } else {
            requestPermissionForAlias(PUSH_NOTIFICATIONS, call, "permissionsCallback")
        }
    }

    @PluginMethod
    public fun register(call: PluginCall) {
        FirebaseMessaging.getInstance().isAutoInitEnabled = true
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                sendError(task.exception?.localizedMessage)
                return@addOnCompleteListener
            }
            sendToken(task.result)
        }
        call.resolve()
    }

    @PluginMethod
    public fun unregister(call: PluginCall) {
        FirebaseMessaging.getInstance().isAutoInitEnabled = false
        FirebaseMessaging.getInstance().deleteToken()
        call.resolve()
    }

    @PluginMethod
    public fun getDeliveredNotifications(call: PluginCall) {
        val notifications = JSArray()

        for (notif in notificationManager.activeNotifications) {
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
            // The Java implementation threw a NullPointerException here
            call.reject("Expected notifications to be a list of notification objects")
            return
        }

        try {
            for (o in notifications.toList<Any?>()) {
                // The Java implementation threw a NullPointerException for an object without an id
                val notif = (o as? JSONObject)?.let { JSObject.fromJSONObject(it) }
                val id = notif?.getInteger("id")
                if (notif == null || id == null) {
                    call.reject("Expected notifications to be a list of notification objects")
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
            call.reject(e.message)
        }

        call.resolve()
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

    public fun sendToken(token: String?) {
        val data = JSObject()
        data.put("value", token)
        notifyListeners(EVENT_TOKEN_CHANGE, data, true)
    }

    public fun sendError(error: String?) {
        val data = JSObject()
        data.put("error", error)
        notifyListeners(EVENT_TOKEN_ERROR, data, true)
    }

    public fun fireNotification(remoteMessage: RemoteMessage) {
        val remoteMessageData = JSObject()

        val data = JSObject()
        remoteMessageData.put("id", remoteMessage.messageId)
        for ((key, value) in remoteMessage.data) {
            data.put(key, value)
        }
        remoteMessageData.put("data", data)

        val notification = remoteMessage.notification
        if (notification != null) {
            val presentation = config.getArray("presentationOptions")
            if (presentation != null && ("alert" in presentation || "banner" in presentation || "list" in presentation)) {
                val bundle = applicationMetaData()
                if (bundle != null) {
                    val params = NotificationParams(remoteMessage.toIntent().extras ?: Bundle())

                    val channelId = CommonNotificationBuilder.getOrCreateChannel(context, params.notificationChannelId, bundle)

                    val notificationInfo = CommonNotificationBuilder.createNotificationInfo(context, context, params, channelId, bundle)

                    showForegroundNotification(notificationInfo, notification.imageUrl)
                }
            }
            remoteMessageData.put("title", notification.title)
            remoteMessageData.put("body", notification.body)
            remoteMessageData.put("click_action", notification.clickAction)

            val link = notification.link
            if (link != null) {
                remoteMessageData.put("link", link.toString())
            }
        }

        notifyListeners("pushNotificationReceived", remoteMessageData, true)
    }

    private fun applicationMetaData(): Bundle? = try {
        context.packageManager
            .getApplicationInfo(
                context.packageName,
                PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
            ).metaData
    } catch (e: PackageManager.NameNotFoundException) {
        e.printStackTrace()
        null
    }

    private fun showForegroundNotification(notificationInfo: CommonNotificationBuilder.DisplayNotificationInfo, imageUrl: Uri?) {
        val showNotification =
            Runnable {
                try {
                    applyNotificationImage(notificationInfo.notificationBuilder, imageUrl)
                } catch (e: RuntimeException) {
                    Logger.error("Unexpected error while applying notification image", e)
                } finally {
                    notificationManager.notify(notificationInfo.tag, notificationInfo.id, notificationInfo.notificationBuilder.build())
                }
            }

        if (Looper.myLooper() != Looper.getMainLooper()) {
            showNotification.run()
            return
        }

        val displayExecutor = Executors.newSingleThreadExecutor()
        displayExecutor.execute {
            try {
                showNotification.run()
            } finally {
                displayExecutor.shutdown()
            }
        }
    }

    private fun applyNotificationImage(notificationBuilder: NotificationCompat.Builder, imageUrl: Uri?) {
        if (imageUrl == null) {
            return
        }

        val imageDownload = ImageDownload.create(imageUrl.toString()) ?: return

        val imageExecutor = Executors.newSingleThreadExecutor()
        try {
            imageDownload.start(imageExecutor)
            val bitmap = Tasks.await(imageDownload.task, IMAGE_DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            notificationBuilder.setLargeIcon(bitmap)
            notificationBuilder.setStyle(NotificationCompat.BigPictureStyle().bigPicture(bitmap).bigLargeIcon(null as Bitmap?))
        } catch (e: ExecutionException) {
            Logger.warn("Failed to download notification image: " + e.cause)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            Logger.warn("Notification image download was interrupted")
        } catch (e: TimeoutException) {
            Logger.warn("Notification image download timed out")
        } finally {
            imageDownload.close()
            imageExecutor.shutdownNow()
        }
    }

    @PermissionCallback
    private fun permissionsCallback(call: PluginCall) {
        checkPermissions(call)
    }

    public companion object {
        private const val IMAGE_DOWNLOAD_TIMEOUT_SECONDS = 5L
        internal const val PUSH_NOTIFICATIONS: String = "receive"

        private const val EVENT_TOKEN_CHANGE = "registration"
        private const val EVENT_TOKEN_ERROR = "registrationError"

        @JvmField
        public var staticBridge: Bridge? = null

        @JvmField
        public var lastMessage: RemoteMessage? = null

        @JvmStatic
        public fun onNewToken(newToken: String?) {
            getPushNotificationsInstance()?.sendToken(newToken)
        }

        @JvmStatic
        public fun sendRemoteMessage(remoteMessage: RemoteMessage) {
            val pushPlugin = getPushNotificationsInstance()
            if (pushPlugin != null) {
                pushPlugin.fireNotification(remoteMessage)
            } else {
                lastMessage = remoteMessage
            }
        }

        @JvmStatic
        public fun getPushNotificationsInstance(): PushNotificationsPlugin? =
            staticBridge?.getPlugin("PushNotifications")?.instance as? PushNotificationsPlugin
    }
}
