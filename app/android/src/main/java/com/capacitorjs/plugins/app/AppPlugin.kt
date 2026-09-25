package com.capacitorjs.plugins.app

import android.content.Intent
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatDelegate
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.util.InternalUtils
import java.util.Locale

@CapacitorPlugin(name = "App")
public class AppPlugin : Plugin() {
    private var hasPausedEver = false

    private var onBackPressedCallback: OnBackPressedCallback? = null

    override fun load() {
        val disableBackButtonHandler = config.getBoolean("disableBackButtonHandler", false)

        bridge.app.setStatusChangeListener { isActive ->
            Logger.debug(logTag, "Firing change: $isActive")
            val data = JSObject()
            data.put("isActive", isActive)
            notifyListeners(EVENT_STATE_CHANGE, data, false)
        }
        bridge.app.setAppRestoredListener { result ->
            if (result != null) {
                Logger.debug(logTag, "Firing restored result")
                notifyListeners(EVENT_RESTORED_RESULT, result.wrappedResult, true)
            }
        }
        val callback =
            object : OnBackPressedCallback(!disableBackButtonHandler) {
                override fun handleOnBackPressed() {
                    if (!hasListeners(EVENT_BACK_BUTTON)) {
                        if (bridge.webView.canGoBack()) {
                            bridge.webView.goBack()
                        }
                    } else {
                        val data = JSObject()
                        data.put("canGoBack", bridge.webView.canGoBack())
                        notifyListeners(EVENT_BACK_BUTTON, data, true)
                        bridge.triggerJSEvent("backbutton", "document")
                    }
                }
            }
        onBackPressedCallback = callback

        // The activity owns the callback and can outlive this bridge: a fragment host, or a host that creates another
        // bridge in the same activity, destroys the bridge first. handleOnDestroy removes the callback, which would
        // otherwise keep the plugin and the bridge reachable and go on handling back presses for a destroyed bridge.
        activity.onBackPressedDispatcher.addCallback(activity, callback)
    }

    @PluginMethod
    public fun exitApp(call: PluginCall) {
        unsetAppListeners()
        call.resolve()
        bridge.activity.finish()
    }

    @PluginMethod
    public fun getInfo(call: PluginCall) {
        val data = JSObject()
        try {
            val packageInfo = checkNotNull(InternalUtils.getPackageInfo(context.packageManager, context.packageName))
            val applicationInfo = context.applicationInfo
            val stringId = applicationInfo.labelRes
            val appName = if (stringId == 0) checkNotNull(applicationInfo.nonLocalizedLabel).toString() else context.getString(stringId)
            data.put("name", appName)
            data.put("id", packageInfo.packageName)
            data.put("build", packageInfo.longVersionCode.toInt().toString())
            data.put("version", packageInfo.versionName)
        } catch (ex: Exception) {
            throw PluginException("Unable to get App Info", cause = ex)
        }
        call.resolve(data)
    }

    @PluginMethod
    public fun getLaunchUrl(call: PluginCall) {
        val launchUri = bridge.intentUri
        if (launchUri != null) {
            val data = JSObject()
            data.put("url", launchUri.toString())
            call.resolve(data)
        } else {
            call.resolve()
        }
    }

    @PluginMethod
    public fun getState(call: PluginCall) {
        val data = JSObject()
        data.put("isActive", bridge.app.isActive)
        call.resolve(data)
    }

    @PluginMethod
    public fun minimizeApp(call: PluginCall) {
        activity.moveTaskToBack(true)
        call.resolve()
    }

    // Enabling the callback registers it with the window's back dispatcher, which belongs to the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun toggleBackButtonHandler(call: PluginCall) {
        val callback = onBackPressedCallback ?: throw PluginException("onBackPressedCallback is not set")
        val enabled = call.getBoolean("enabled") ?: throw PluginException("enabled must be provided and must be a boolean")

        callback.isEnabled = enabled
        call.resolve()
    }

    @PluginMethod
    public fun getAppLanguage(call: PluginCall) {
        val ret = JSObject()
        val appLocales = AppCompatDelegate.getApplicationLocales()
        val appLocale = if (!appLocales.isEmpty) appLocales[0] else null
        ret.put("value", appLocale?.language ?: Locale.getDefault().language)
        call.resolve(ret)
    }

    /**
     * Handle ACTION_VIEW intents to store a URL that was used to open the app
     * @param intent
     */
    override fun handleOnNewIntent(intent: Intent?) {
        super.handleOnNewIntent(intent)
        val url = intent?.data
        if (intent?.action != Intent.ACTION_VIEW || url == null) {
            return
        }

        val ret = JSObject()
        ret.put("url", url.toString())
        notifyListeners(EVENT_URL_OPEN, ret, true)
    }

    override fun handleOnPause() {
        super.handleOnPause()
        hasPausedEver = true
        notifyListeners(EVENT_PAUSE, null)
    }

    override fun handleOnResume() {
        super.handleOnResume()
        if (hasPausedEver) {
            notifyListeners(EVENT_RESUME, null)
        }
    }

    override fun handleOnDestroy() {
        unsetAppListeners()
        onBackPressedCallback?.remove()
    }

    private fun unsetAppListeners() {
        bridge.app.setStatusChangeListener(null)
        bridge.app.setAppRestoredListener(null)
    }

    private companion object {
        const val EVENT_BACK_BUTTON = "backButton"
        const val EVENT_URL_OPEN = "appUrlOpen"
        const val EVENT_STATE_CHANGE = "appStateChange"
        const val EVENT_RESTORED_RESULT = "appRestoredResult"
        const val EVENT_PAUSE = "pause"
        const val EVENT_RESUME = "resume"
    }
}
