package com.capacitorjs.plugins.pushnotifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginConfig

public class NotificationChannelManager(
    private val context: Context,
    private val notificationManager: NotificationManager,
    @Suppress("unused") private val config: PluginConfig
) {
    public fun createChannel(call: PluginCall) {
        val channel = JSObject()
        val id = call.getString(CHANNEL_ID)
        if (id == null) {
            call.reject("Channel missing identifier")
            return
        }
        channel.put(CHANNEL_ID, id)
        val name = call.getString(CHANNEL_NAME)
        if (name == null) {
            call.reject("Channel missing name")
            return
        }
        channel.put(CHANNEL_NAME, name)

        channel.put(CHANNEL_IMPORTANCE, call.getInt(CHANNEL_IMPORTANCE, NotificationManager.IMPORTANCE_DEFAULT))
        channel.put(CHANNEL_DESCRIPTION, call.getString(CHANNEL_DESCRIPTION, ""))
        channel.put(CHANNEL_VISIBILITY, call.getInt(CHANNEL_VISIBILITY, NotificationCompat.VISIBILITY_PUBLIC))
        channel.put(CHANNEL_SOUND, call.getString(CHANNEL_SOUND))
        channel.put(CHANNEL_VIBRATE, call.getBoolean(CHANNEL_VIBRATE, false))
        channel.put(CHANNEL_USE_LIGHTS, call.getBoolean(CHANNEL_USE_LIGHTS, false))
        channel.put(CHANNEL_LIGHT_COLOR, call.getString(CHANNEL_LIGHT_COLOR))
        createChannel(channel)
        call.resolve()
    }

    public fun createChannel(channel: JSObject) {
        // The Java implementation unboxed these values and threw when one was missing. Fall back to the
        // defaults createChannel(PluginCall) uses instead.
        val notificationChannel =
            NotificationChannel(
                channel.getString(CHANNEL_ID),
                channel.getString(CHANNEL_NAME),
                channel.getInteger(CHANNEL_IMPORTANCE) ?: NotificationManager.IMPORTANCE_DEFAULT
            )
        notificationChannel.description = channel.getString(CHANNEL_DESCRIPTION)
        notificationChannel.lockscreenVisibility = channel.getInteger(CHANNEL_VISIBILITY) ?: NotificationCompat.VISIBILITY_PUBLIC
        notificationChannel.enableVibration(channel.getBool(CHANNEL_VIBRATE) ?: false)
        notificationChannel.enableLights(channel.getBool(CHANNEL_USE_LIGHTS) ?: false)
        val lightColor = channel.getString(CHANNEL_LIGHT_COLOR)
        if (lightColor != null) {
            try {
                notificationChannel.lightColor = parseLightColor(lightColor)
            } catch (ex: IllegalArgumentException) {
                Logger.error(Logger.tags("NotificationChannel"), "Invalid color provided for light color.", null)
            }
        }
        var sound = channel.getString(CHANNEL_SOUND, null)
        if (!sound.isNullOrEmpty()) {
            if (sound.contains(".")) {
                sound = sound.substring(0, sound.lastIndexOf('.'))
            }
            val audioAttributes =
                AudioAttributes
                    .Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
            val soundUri = Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + context.packageName + "/raw/" + sound)
            notificationChannel.setSound(soundUri, audioAttributes)
        }
        notificationManager.createNotificationChannel(notificationChannel)
    }

    public fun deleteChannel(call: PluginCall) {
        val channelId = call.getString("id")
        notificationManager.deleteNotificationChannel(channelId)
        call.resolve()
    }

    public fun listChannels(call: PluginCall) {
        val channels = JSArray()
        for (notificationChannel in notificationManager.notificationChannels) {
            val channel = JSObject()
            channel.put(CHANNEL_ID, notificationChannel.id)
            channel.put(CHANNEL_NAME, notificationChannel.name)
            channel.put(CHANNEL_DESCRIPTION, notificationChannel.description)
            channel.put(CHANNEL_IMPORTANCE, notificationChannel.importance)
            channel.put(CHANNEL_VISIBILITY, notificationChannel.lockscreenVisibility)
            channel.put(CHANNEL_SOUND, notificationChannel.sound)
            channel.put(CHANNEL_VIBRATE, notificationChannel.shouldVibrate())
            channel.put(CHANNEL_USE_LIGHTS, notificationChannel.shouldShowLights())
            channel.put(CHANNEL_LIGHT_COLOR, String.format("#%06X", 0xFFFFFF and notificationChannel.lightColor))
            Logger.debug(Logger.tags("NotificationChannel"), "visibility " + notificationChannel.lockscreenVisibility)
            Logger.debug(Logger.tags("NotificationChannel"), "importance " + notificationChannel.importance)
            channels.put(channel)
        }
        val result = JSObject()
        result.put("channels", channels)
        call.resolve(result)
    }

    private companion object {
        const val CHANNEL_ID = "id"
        const val CHANNEL_NAME = "name"
        const val CHANNEL_DESCRIPTION = "description"
        const val CHANNEL_IMPORTANCE = "importance"
        const val CHANNEL_VISIBILITY = "visibility"
        const val CHANNEL_SOUND = "sound"
        const val CHANNEL_VIBRATE = "vibration"
        const val CHANNEL_USE_LIGHTS = "lights"
        const val CHANNEL_LIGHT_COLOR = "lightColor"
    }
}

/**
 * Reads a channel light color the way the runtime's `WebColor` reads web colors, as the TypeScript definition documents
 * it: `#RRGGBB` or `#RRGGBBAA`, with or without the `#`. It does not go through `android.graphics.Color`, so that it
 * runs in JVM unit tests. The local-notifications and push-notifications plugins each have this function and the same
 * test for it; keep the two the same.
 *
 * @return the color as an ARGB color int
 * @throws IllegalArgumentException when the value is not 6 or 8 hexadecimal digits
 */
internal fun parseLightColor(value: String): Int {
    val hex = value.removePrefix("#")
    require((hex.length == 6 || hex.length == 8) && hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) {
        "Invalid color \"$value\", expected #RRGGBB or #RRGGBBAA"
    }
    val rgb = hex.substring(0, 6).toInt(16)
    val alpha = if (hex.length == 8) hex.substring(6).toInt(16) else 0xFF
    return (alpha shl 24) or rgb
}
