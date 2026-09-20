package com.capacitorjs.plugins.toast

import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Toast")
public class ToastPlugin : Plugin() {
    @PluginMethod
    public fun show(call: PluginCall) {
        val text = call.getString("text")
        if (text == null) {
            call.reject("Must provide text")
            return
        }

        val duration =
            if (call.getString("duration", "short") == "long") {
                android.widget.Toast.LENGTH_LONG
            } else {
                android.widget.Toast.LENGTH_SHORT
            }
        Toast.show(context, text, duration, call.getString("position", "bottom"))

        call.resolve()
    }
}
