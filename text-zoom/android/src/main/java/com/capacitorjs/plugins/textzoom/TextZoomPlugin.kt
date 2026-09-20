package com.capacitorjs.plugins.textzoom

import android.os.Handler
import android.os.Looper
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "TextZoom")
public class TextZoomPlugin : Plugin() {
    private lateinit var textZoom: TextZoom
    private lateinit var mainHandler: Handler

    override fun load() {
        textZoom = TextZoom(bridge.activity, bridge.webView)
        mainHandler = Handler(Looper.getMainLooper())
    }

    @PluginMethod
    public fun get(call: PluginCall) {
        mainHandler.post {
            val ret = JSObject()
            ret.put("value", textZoom.get())
            call.resolve(ret)
        }
    }

    @PluginMethod
    public fun set(call: PluginCall) {
        mainHandler.post {
            val value = call.getDouble("value")

            if (value == null) {
                call.reject("Invalid integer value.")
            } else {
                textZoom.set(value)
                call.resolve()
            }
        }
    }

    @PluginMethod
    public fun getPreferred(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", textZoom.preferred)
        call.resolve(ret)
    }
}
