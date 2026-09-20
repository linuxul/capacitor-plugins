package com.capacitorjs.plugins.localnotifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.getcapacitor.Logger

/**
 * Receiver called when notification is dismissed by user
 */
public class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val intExtra = intent?.getIntExtra(LocalNotificationManager.NOTIFICATION_INTENT_KEY, Int.MIN_VALUE) ?: Int.MIN_VALUE
        if (intent == null || intExtra == Int.MIN_VALUE) {
            Logger.error(Logger.tags("LN"), "Invalid notification dismiss operation", null)
            return
        }
        val isRemovable = intent.getBooleanExtra(LocalNotificationManager.NOTIFICATION_IS_REMOVABLE_KEY, true)
        if (isRemovable) {
            val notificationStorage = NotificationStorage(context)
            notificationStorage.deleteNotification(intExtra.toString())
        }
    }
}
