package com.capacitorjs.plugins.toast

import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Toast")
public class ToastPlugin : Plugin() {
    // Toasts are shown from the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun show(call: PluginCall) {
        val text = call.getString("text") ?: throw PluginException("Must provide text")

        val duration =
            if (call.getString("duration", "short") == "long") {
                android.widget.Toast.LENGTH_LONG
            } else {
                android.widget.Toast.LENGTH_SHORT
            }
        Toast.showNow(context, text, duration, call.getString("position", "bottom"))

        call.resolve()
    }
}
