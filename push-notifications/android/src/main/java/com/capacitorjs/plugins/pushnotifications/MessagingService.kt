package com.capacitorjs.plugins.pushnotifications

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

public class MessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        PushNotificationsPlugin.sendRemoteMessage(remoteMessage)
    }

    override fun onNewToken(s: String) {
        super.onNewToken(s)
        PushNotificationsPlugin.onNewToken(s)
    }
}
