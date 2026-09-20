package com.capacitorjs.plugins.clipboard

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Clipboard")
public class ClipboardPlugin : Plugin() {
    private lateinit var implementation: Clipboard

    override fun load() {
        implementation = Clipboard(context)
    }

    @PluginMethod
    public fun write(call: PluginCall) {
        val content = call.getString("string") ?: call.getString("image") ?: call.getString("url")
        if (content == null) {
            call.reject("No data provided")
            return
        }

        val response = implementation.write(call.getString("label"), content)
        if (response.isSuccess) {
            call.resolve()
        } else {
            call.reject(response.errorMessage)
        }
    }

    @PluginMethod
    public fun read(call: PluginCall) {
        val result = implementation.read()

        if (result == null) {
            call.reject("Unable to read clipboard from the given Context")
        } else if (result.value == null) {
            call.reject("There is no data on the clipboard")
        } else {
            val resultJS = JSObject()
            resultJS.put("value", result.value)
            resultJS.put("type", result.type)

            call.resolve(resultJS)
        }
    }
}
