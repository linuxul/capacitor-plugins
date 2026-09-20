package com.capacitorjs.plugins.device

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.webkit.WebView

public class Device internal constructor(private val context: Context) {
    public val memUsed: Long
        get() {
            val runtime = Runtime.getRuntime()
            return runtime.totalMemory() - runtime.freeMemory()
        }

    public val platform: String
        get() = "android"

    public val uuid: String?
        get() = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)

    public val batteryLevel: Float
        get() {
            val batteryStatus = batteryStatus()
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1

            return level / scale.toFloat()
        }

    public val isCharging: Boolean
        get() {
            val status = batteryStatus()?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: return false
            return status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        }

    public val isVirtual: Boolean
        get() = Build.FINGERPRINT.contains("generic") || Build.PRODUCT.contains("sdk")

    public val name: String?
        get() = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)

    public val webViewVersion: String?
        get() {
            val info = WebView.getCurrentWebViewPackage()
            return if (info != null) info.versionName else Build.VERSION.RELEASE
        }

    private fun batteryStatus(): Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
}
