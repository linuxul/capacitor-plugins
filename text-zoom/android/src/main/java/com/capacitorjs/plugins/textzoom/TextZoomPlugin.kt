package com.capacitorjs.plugins.textzoom

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "TextZoom")
public class TextZoomPlugin : Plugin() {
    private lateinit var textZoom: TextZoom

    override fun load() {
        textZoom = TextZoom(bridge.activity, bridge.webView)
    }

    // The web view's settings belong to the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun get(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", textZoom.get())
        call.resolve(ret)
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun set(call: PluginCall) {
        val value = call.getDouble("value") ?: throw PluginException("Invalid integer value.")
        textZoom.set(value)
        call.resolve()
    }

    @PluginMethod
    public fun getPreferred(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", textZoom.preferred)
        call.resolve(ret)
    }
}
