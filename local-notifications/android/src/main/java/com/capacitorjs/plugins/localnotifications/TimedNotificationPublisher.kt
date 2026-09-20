package com.capacitorjs.plugins.localnotifications

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.getcapacitor.Logger
import java.text.SimpleDateFormat
import java.util.Date

/**
 * Class used to create notification from timer event
 * Note: Class is being registered in Android manifest as broadcast receiver
 */
public class TimedNotificationPublisher : BroadcastReceiver() {
    /**
     * Restore and present notification
     */
    override fun onReceive(context: Context, intent: Intent?) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val notification = intent?.getParcelableExtra(NOTIFICATION_KEY, Notification::class.java)
        if (intent == null || notification == null) {
            // Without the notification there is nothing to present. This used to be a NullPointerException.
            Logger.error(Logger.tags("LN"), "No notification supplied", null)
            return
        }

        notification.`when` = System.currentTimeMillis()

        val id = intent.getIntExtra(LocalNotificationManager.NOTIFICATION_INTENT_KEY, Int.MIN_VALUE)
        if (id == Int.MIN_VALUE) {
            Logger.error(Logger.tags("LN"), "No valid id supplied", null)
        }
        val storage = NotificationStorage(context)
        val notificationJson = storage.getSavedNotificationAsJSObject(id.toString())
        LocalNotificationsPlugin.fireReceived(notificationJson)
        notificationManager.notify(id, notification)
        if (!rescheduleNotificationIfNeeded(context, intent, id)) {
            storage.deleteNotification(id.toString())
        }
    }

    private fun rescheduleNotificationIfNeeded(context: Context, intent: Intent, id: Int): Boolean {
        val dateString = intent.getStringExtra(CRON_KEY) ?: return false

        val date = DateMatch.fromMatchString(dateString)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val trigger = date.nextTrigger(Date())
        val clone = intent.clone() as Intent
        val flags = PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE
        val pendingIntent = PendingIntent.getBroadcast(context, id, clone, flags)
        if (!alarmManager.canScheduleExactAlarms()) {
            Logger.warn(
                "Capacitor/LocalNotification",
                "Exact alarms not allowed in user settings.  Notification scheduled with non-exact alarm."
            )
            alarmManager.set(AlarmManager.RTC, trigger, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC, trigger, pendingIntent)
        }
        val sdf = SimpleDateFormat("yyyy/MM/dd HH:mm:ss")
        Logger.debug(Logger.tags("LN"), "notification " + id + " will next fire at " + sdf.format(Date(trigger)))
        return true
    }

    public companion object {
        public const val NOTIFICATION_KEY: String = "NotificationPublisher.notification"
        public const val CRON_KEY: String = "NotificationPublisher.cron"
    }
}
