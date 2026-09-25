package com.capacitorjs.plugins.localnotifications

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import com.getcapacitor.CapConfig
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginConfig
import com.getcapacitor.plugin.util.AssetUtil
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Contains implementations for all notification actions
 */
public class LocalNotificationManager(
    private val storage: NotificationStorage,
    private val activity: Activity?,
    private val context: Context,
    config: CapConfig
) {
    private val config: PluginConfig = config.getPluginConfiguration("LocalNotifications")

    /**
     * Method extecuted when notification is launched by user from the notification bar.
     */
    public fun handleNotificationActionPerformed(data: Intent, notificationStorage: NotificationStorage): JSObject? {
        Logger.debug(Logger.tags("LN"), "LocalNotification received: " + data.dataString)
        val notificationId = data.getIntExtra(NOTIFICATION_INTENT_KEY, Int.MIN_VALUE)
        if (notificationId == Int.MIN_VALUE) {
            Logger.debug(Logger.tags("LN"), "Activity started without notification attached")
            return null
        }
        val isRemovable = data.getBooleanExtra(NOTIFICATION_IS_REMOVABLE_KEY, true)
        if (isRemovable) {
            notificationStorage.deleteNotification(notificationId.toString())
        }
        val dataJson = JSObject()

        val results = RemoteInput.getResultsFromIntent(data)
        if (results != null) {
            val input = results.getCharSequence(REMOTE_INPUT_KEY)
            dataJson.put("inputValue", input?.toString())
        }
        val menuAction = data.getStringExtra(ACTION_INTENT_KEY)

        dismissVisibleNotification(notificationId)

        dataJson.put("actionId", menuAction)
        var request: JSONObject? = null
        try {
            val notificationJsonString = data.getStringExtra(NOTIFICATION_OBJ_INTENT_KEY)
            if (notificationJsonString != null) {
                request = JSObject(notificationJsonString)
            }
        } catch (e: JSONException) {
        }
        dataJson.put("notification", request)
        return dataJson
    }

    /**
     * Create notification channel
     */
    public fun createNotificationChannel() {
        val name: CharSequence = "Default"
        val description = "Default"
        val importance = NotificationManager.IMPORTANCE_DEFAULT
        val channel = NotificationChannel(DEFAULT_NOTIFICATION_CHANNEL_ID, name, importance)
        channel.description = description
        val audioAttributes =
            AudioAttributes
                .Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
        val soundUri = getDefaultSoundUrl(context)
        if (soundUri != null) {
            channel.setSound(soundUri, audioAttributes)
        }
        // Register the channel with the system; you can't change the importance
        // or other notification behaviors after this
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    public fun schedule(call: PluginCall?, localNotifications: List<LocalNotification>): JSONArray? {
        val ids = JSONArray()
        val notificationManager = NotificationManagerCompat.from(context)

        val notificationsEnabled = notificationManager.areNotificationsEnabled()
        if (!notificationsEnabled) {
            call?.reject("Notifications not enabled on this device")
            return null
        }
        // Check every notification before scheduling any. Rejecting halfway through used to leave the notifications
        // before the bad one scheduled, and the plugin then resolved the rejected call too. Without a call, when the
        // notifications are restored after a reboot, a bad one is skipped and the others are still scheduled.
        val valid = ArrayList<LocalNotification>(localNotifications.size)
        for (localNotification in localNotifications) {
            val error = checkNotification(localNotification)
            if (error == null) {
                valid.add(localNotification)
            } else if (call != null) {
                call.reject(error)
                return null
            } else {
                Logger.error(Logger.tags("LN"), "Not scheduling notification ${localNotification.id}: $error", null)
            }
        }
        for (localNotification in valid) {
            val id = checkNotNull(localNotification.id)
            dismissVisibleNotification(id)
            cancelTimerForNotification(id)
            buildNotification(notificationManager, localNotification, id)
            ids.put(id)
        }
        return ids
    }

    /**
     * Why [localNotification] cannot be scheduled, or null when it can
     */
    private fun checkNotification(localNotification: LocalNotification): String? {
        val iconColor = getIconColor(localNotification)
        return when {
            localNotification.id == null -> "LocalNotification missing identifier"
            iconColor != null && parseIconColor(iconColor) == null -> "Invalid color provided. Must be a hex string (ex: #ff0000"
            else -> null
        }
    }

    private fun getIconColor(localNotification: LocalNotification): String? = localNotification.getIconColor(config.getString("iconColor"))

    private fun parseIconColor(color: String): Int? = try {
        Color.parseColor(color)
    } catch (ex: IllegalArgumentException) {
        null
    }

    // TODO Progressbar support
    // TODO System categories (DO_NOT_DISTURB etc.)
    // TODO control visibility by flag Notification.VISIBILITY_PRIVATE
    // TODO Group notifications (setGroup, setGroupSummary, setNumber)
    // TODO use NotificationCompat.MessagingStyle for latest API
    // TODO expandable notification NotificationCompat.MessagingStyle
    // TODO media style notification support NotificationCompat.MediaStyle
    // TODO custom small/large icons
    private fun buildNotification(notificationManager: NotificationManagerCompat, localNotification: LocalNotification, id: Int) {
        val channelId = localNotification.channelId ?: DEFAULT_NOTIFICATION_CHANNEL_ID
        val mBuilder =
            NotificationCompat
                .Builder(context, channelId)
                .setContentTitle(localNotification.title)
                .setContentText(localNotification.body)
                .setAutoCancel(localNotification.isAutoCancel)
                .setOngoing(localNotification.isOngoing)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setGroupSummary(localNotification.isGroupSummary)

        if (localNotification.largeBody != null) {
            // support multiline text
            mBuilder.setStyle(
                NotificationCompat
                    .BigTextStyle()
                    .bigText(localNotification.largeBody)
                    .setSummaryText(localNotification.summaryText)
            )
        }

        localNotification.inboxList?.let { inboxList ->
            val inboxStyle = NotificationCompat.InboxStyle()
            for (line in inboxList) {
                inboxStyle.addLine(line)
            }
            inboxStyle.setBigContentTitle(localNotification.title)
            inboxStyle.setSummaryText(localNotification.summaryText)
            mBuilder.setStyle(inboxStyle)
        }

        val sound = localNotification.getSound(context, getDefaultSound(context))
        if (sound != null) {
            val soundUri = Uri.parse(sound)
            // Grant permission to use sound
            context.grantUriPermission("com.android.systemui", soundUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            mBuilder.setSound(soundUri)
            mBuilder.setDefaults(Notification.DEFAULT_VIBRATE or Notification.DEFAULT_LIGHTS)
        } else {
            mBuilder.setDefaults(Notification.DEFAULT_ALL)
        }

        val group = localNotification.group
        if (group != null) {
            mBuilder.setGroup(group)
            if (localNotification.isGroupSummary) {
                mBuilder.setSubText(localNotification.summaryText)
            }
        }

        mBuilder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        mBuilder.setOnlyAlertOnce(true)

        mBuilder.setSmallIcon(localNotification.getSmallIcon(context, getDefaultSmallIcon(context)))
        mBuilder.setLargeIcon(localNotification.getLargeIcon(context))

        // schedule has checked that the color parses
        val iconColor = getIconColor(localNotification)?.let { parseIconColor(it) }
        if (iconColor != null) {
            mBuilder.setColor(iconColor)
        }

        createActionIntents(localNotification, id, mBuilder)
        // notificationId is a unique int for each localNotification that you must define
        val buildNotification = mBuilder.build()
        val schedule = localNotification.schedule
        if (schedule != null && localNotification.isScheduled) {
            triggerScheduledNotification(buildNotification, id, schedule)
        } else {
            try {
                localNotification.source?.let { LocalNotificationsPlugin.fireReceived(JSObject(it)) }
            } catch (e: JSONException) {
            }
            // schedule() stops when areNotificationsEnabled() is false, as it is without POST_NOTIFICATIONS, and
            // the system would drop the notification anyway. Checking here keeps this path safe on its own.
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                notificationManager.notify(id, buildNotification)
            }
        }
    }

    // Create intents for open/dissmis actions
    private fun createActionIntents(localNotification: LocalNotification, id: Int, mBuilder: NotificationCompat.Builder) {
        // Open intent
        val intent = buildIntent(localNotification, id, DEFAULT_PRESS_ACTION)
        val flags = PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE
        val pendingIntent = PendingIntent.getActivity(context, id, intent, flags)
        mBuilder.setContentIntent(pendingIntent)

        // Build action types
        val actionTypeId = localNotification.actionTypeId
        if (actionTypeId != null) {
            val actionGroup = storage.getActionGroup(actionTypeId)
            for (notificationAction in actionGroup) {
                // TODO Add custom icons to actions
                val actionIntent = buildIntent(localNotification, id, notificationAction.id)
                val actionPendingIntent = PendingIntent.getActivity(context, id + notificationAction.id.hashCode(), actionIntent, flags)
                val actionBuilder = NotificationCompat.Action.Builder(
                    R.drawable.ic_transparent,
                    notificationAction.title,
                    actionPendingIntent
                )
                if (notificationAction.isInput) {
                    val remoteInput = RemoteInput.Builder(REMOTE_INPUT_KEY).setLabel(notificationAction.title).build()
                    actionBuilder.addRemoteInput(remoteInput)
                }
                mBuilder.addAction(actionBuilder.build())
            }
        }

        // Dismiss intent
        val dissmissIntent = Intent(context, NotificationDismissReceiver::class.java)
        dissmissIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        dissmissIntent.putExtra(NOTIFICATION_INTENT_KEY, id)
        dissmissIntent.putExtra(ACTION_INTENT_KEY, "dismiss")
        val schedule = localNotification.schedule
        dissmissIntent.putExtra(NOTIFICATION_IS_REMOVABLE_KEY, schedule == null || schedule.isRemovable)
        val deleteIntent = PendingIntent.getBroadcast(context, id, dissmissIntent, PendingIntent.FLAG_MUTABLE)
        mBuilder.setDeleteIntent(deleteIntent)
    }

    private fun buildIntent(localNotification: LocalNotification, id: Int, action: String?): Intent {
        val intent =
            if (activity != null) {
                Intent(context, activity.javaClass)
            } else {
                // An app without a launcher activity is a NullPointerException here, as it always was
                context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            }
        intent.action = Intent.ACTION_MAIN
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        intent.putExtra(NOTIFICATION_INTENT_KEY, id)
        intent.putExtra(ACTION_INTENT_KEY, action)
        intent.putExtra(NOTIFICATION_OBJ_INTENT_KEY, localNotification.source)
        val schedule = localNotification.schedule
        intent.putExtra(NOTIFICATION_IS_REMOVABLE_KEY, schedule == null || schedule.isRemovable)
        return intent
    }

    /**
     * Build a notification trigger, such as triggering each N seconds, or
     * on a certain date "shape" (such as every first of the month)
     */
    // TODO support different AlarmManager.RTC modes depending on priority
    private fun triggerScheduledNotification(notification: Notification, id: Int, schedule: LocalNotificationSchedule) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val notificationIntent = Intent(context, TimedNotificationPublisher::class.java)
        notificationIntent.putExtra(NOTIFICATION_INTENT_KEY, id)
        notificationIntent.putExtra(TimedNotificationPublisher.NOTIFICATION_KEY, notification)
        val flags = PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE
        var pendingIntent = PendingIntent.getBroadcast(context, id, notificationIntent, flags)

        // Schedule at specific time (with repeating support)
        val at = schedule.at
        if (at != null) {
            if (at.time < Date().time) {
                Logger.error(Logger.tags("LN"), "Scheduled time must be *after* current time", null)
                return
            }
            if (schedule.isRepeating) {
                val interval = at.time - Date().time
                alarmManager.setRepeating(AlarmManager.RTC, at.time, interval, pendingIntent)
            } else {
                setExactIfPossible(alarmManager, schedule, at.time, pendingIntent)
            }
            return
        }

        // Schedule at specific intervals
        if (schedule.every != null) {
            val everyInterval = schedule.everyInterval
            if (everyInterval != null) {
                val startTime = Date().time + everyInterval
                alarmManager.setRepeating(AlarmManager.RTC, startTime, everyInterval, pendingIntent)
            }
            return
        }

        // Cron like scheduler
        val on = schedule.on
        if (on != null) {
            val trigger = on.nextTrigger(Date())
            notificationIntent.putExtra(TimedNotificationPublisher.CRON_KEY, on.toMatchString())
            pendingIntent = PendingIntent.getBroadcast(context, id, notificationIntent, flags)
            setExactIfPossible(alarmManager, schedule, trigger, pendingIntent)
            val sdf = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US)
            Logger.debug(Logger.tags("LN"), "notification " + id + " will next fire at " + sdf.format(Date(trigger)))
        }
    }

    private fun setExactIfPossible(
        alarmManager: AlarmManager,
        schedule: LocalNotificationSchedule,
        trigger: Long,
        pendingIntent: PendingIntent
    ) {
        if (!alarmManager.canScheduleExactAlarms()) {
            Logger.warn(
                "Capacitor/LocalNotification",
                "Exact alarms not allowed in user settings.  Notification scheduled with non-exact alarm."
            )
            if (schedule.allowWhileIdle()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC, trigger, pendingIntent)
            }
        } else {
            if (schedule.allowWhileIdle()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC, trigger, pendingIntent)
            }
        }
    }

    public fun cancel(call: PluginCall) {
        val notificationsToCancel = LocalNotification.getLocalNotificationPendingList(call)
        if (notificationsToCancel != null) {
            for (id in notificationsToCancel) {
                dismissVisibleNotification(id)
                cancelTimerForNotification(id)
                storage.deleteNotification(id.toString())
            }
        }
        call.resolve()
    }

    private fun cancelTimerForNotification(notificationId: Int) {
        val intent = Intent(context, TimedNotificationPublisher::class.java)
        val pi = PendingIntent.getBroadcast(context, notificationId, intent, PendingIntent.FLAG_MUTABLE)
        if (pi != null) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pi)
        }
    }

    private fun dismissVisibleNotification(notificationId: Int) {
        val notificationManager = NotificationManagerCompat.from(context)
        notificationManager.cancel(notificationId)
    }

    public fun areNotificationsEnabled(): Boolean {
        val notificationManager = NotificationManagerCompat.from(context)
        return notificationManager.areNotificationsEnabled()
    }

    public fun getDefaultSoundUrl(context: Context): Uri? {
        val soundId = getDefaultSound(context)
        if (soundId != AssetUtil.RESOURCE_ID_ZERO_VALUE) {
            return Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + context.packageName + "/" + soundId)
        }
        return null
    }

    private fun getDefaultSound(context: Context): Int {
        if (defaultSoundID != AssetUtil.RESOURCE_ID_ZERO_VALUE) return defaultSoundID

        var resId = AssetUtil.RESOURCE_ID_ZERO_VALUE
        val soundConfigResourceName = AssetUtil.getResourceBaseName(config.getString("sound"))

        if (soundConfigResourceName != null) {
            resId = AssetUtil.getResourceID(context, soundConfigResourceName, "raw")
        }

        defaultSoundID = resId
        return resId
    }

    private fun getDefaultSmallIcon(context: Context): Int {
        if (defaultSmallIconID != AssetUtil.RESOURCE_ID_ZERO_VALUE) return defaultSmallIconID

        var resId = AssetUtil.RESOURCE_ID_ZERO_VALUE
        val smallIconConfigResourceName = AssetUtil.getResourceBaseName(config.getString("smallIcon"))

        if (smallIconConfigResourceName != null) {
            resId = AssetUtil.getResourceID(context, smallIconConfigResourceName, "drawable")
        }

        if (resId == AssetUtil.RESOURCE_ID_ZERO_VALUE) {
            resId = android.R.drawable.ic_dialog_info
        }

        defaultSmallIconID = resId
        return resId
    }

    public companion object {
        private var defaultSoundID = AssetUtil.RESOURCE_ID_ZERO_VALUE
        private var defaultSmallIconID = AssetUtil.RESOURCE_ID_ZERO_VALUE

        // Action constants
        public const val NOTIFICATION_INTENT_KEY: String = "LocalNotificationId"
        public const val NOTIFICATION_OBJ_INTENT_KEY: String = "LocalNotficationObject"
        public const val ACTION_INTENT_KEY: String = "LocalNotificationUserAction"
        public const val NOTIFICATION_IS_REMOVABLE_KEY: String = "LocalNotificationRepeating"
        public const val REMOTE_INPUT_KEY: String = "LocalNotificationRemoteInput"

        public const val DEFAULT_NOTIFICATION_CHANNEL_ID: String = "default"
        private const val DEFAULT_PRESS_ACTION = "tap"
    }
}
