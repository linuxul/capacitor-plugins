package com.capacitorjs.plugins.statusbar

import android.content.res.Configuration
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.util.WebColor
import java.util.Locale

@CapacitorPlugin(name = "StatusBar")
public class StatusBarPlugin : Plugin() {
    private lateinit var implementation: StatusBar

    override fun load() {
        implementation =
            StatusBar(activity, statusBarConfig()) { eventName, info -> notifyListeners(eventName, toJSObject(info), true) }
    }

    private fun statusBarConfig(): StatusBarConfig {
        val statusBarConfig = StatusBarConfig()
        val backgroundColor = config.getString("backgroundColor")
        if (backgroundColor != null) {
            try {
                statusBarConfig.backgroundColor = WebColor.parseColor(backgroundColor)
            } catch (ex: IllegalArgumentException) {
                Logger.debug("Background color not applied")
            }
        }
        statusBarConfig.style = styleFromConfig(config.getString("style", statusBarConfig.style) ?: statusBarConfig.style)
        statusBarConfig.isOverlaysWebView = config.getBoolean("overlaysWebView", statusBarConfig.isOverlaysWebView)
        return statusBarConfig
    }

    private fun styleFromConfig(style: String): String = when (style.lowercase(Locale.getDefault())) {
        "lightcontent", "dark" -> "DARK"
        "darkcontent", "light" -> "LIGHT"
        else -> "DEFAULT"
    }

    override fun handleOnConfigurationChanged(newConfig: Configuration?) {
        super.handleOnConfigurationChanged(newConfig)
        implementation.updateStyle()
    }

    // The setters change the activity's window, which belongs to the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun setStyle(call: PluginCall) {
        val style = call.getString("style") ?: throw PluginException("Style must be provided")
        implementation.setStyle(style)
        call.resolve()
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun setBackgroundColor(call: PluginCall) {
        val color = call.getString("color") ?: throw PluginException("Color must be provided")
        try {
            val parsedColor = WebColor.parseColor(color.uppercase(Locale.ROOT))
            implementation.setBackgroundColor(parsedColor)
            call.resolve()
        } catch (ex: IllegalArgumentException) {
            call.reject("Invalid color provided. Must be a hex string (ex: #ff0000")
        }
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun hide(call: PluginCall) {
        implementation.hide()
        call.resolve()
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun show(call: PluginCall) {
        implementation.show()
        call.resolve()
    }

    @PluginMethod
    public fun getInfo(call: PluginCall) {
        call.resolve(toJSObject(implementation.getInfo()))
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun setOverlaysWebView(call: PluginCall) {
        val overlay = call.getBoolean("overlay", true) ?: true
        implementation.setOverlaysWebView(overlay)
        call.resolve()
    }

    private fun toJSObject(info: StatusBarInfo): JSObject {
        val data = JSObject()
        data.put("visible", info.visible)
        data.put("style", info.style)
        data.put("color", info.color)
        data.put("overlays", info.overlays)
        data.put("height", info.height)
        return data
    }
}
