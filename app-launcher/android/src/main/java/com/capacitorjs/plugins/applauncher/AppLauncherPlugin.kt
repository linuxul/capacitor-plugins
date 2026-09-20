package com.capacitorjs.plugins.applauncher

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.util.InternalUtils

@CapacitorPlugin(name = "AppLauncher")
public class AppLauncherPlugin : Plugin() {
    @PluginMethod
    public fun canOpenUrl(call: PluginCall) {
        val url = call.getString("url")
        if (url == null) {
            call.reject("Must supply a url")
            return
        }

        val pm = activity.applicationContext.packageManager

        val ret = JSObject()
        try {
            InternalUtils.getPackageInfo(pm, url, PackageManager.GET_ACTIVITIES.toLong())
            ret.put("value", true)
            call.resolve(ret)
            return
        } catch (e: PackageManager.NameNotFoundException) {
            Logger.error(logTag, "Package name '$url' not found!", null)
        }
        ret.put("value", canResolve(pm, Intent(Intent.ACTION_VIEW, Uri.parse(url))) || canResolve(pm, Intent(url)))
        call.resolve(ret)
    }

    private fun canResolve(pm: PackageManager, intent: Intent): Boolean =
        pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null

    @PluginMethod
    public fun openUrl(call: PluginCall) {
        val url = call.getString("url")
        if (url == null) {
            call.reject("Must provide a url to open")
            return
        }
        val launchIntent = Intent(Intent.ACTION_VIEW)
        launchIntent.data = Uri.parse(url)
        val completed =
            canLaunchIntent(launchIntent) ||
                canLaunchIntent(context.packageManager.getLaunchIntentForPackage(url)) ||
                canLaunchIntent(Intent(url))

        val ret = JSObject()
        ret.put("completed", completed)
        call.resolve(ret)
    }

    private fun canLaunchIntent(intent: Intent?): Boolean {
        if (intent == null) {
            return false
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (ex: Exception) {
            false
        }
    }
}
