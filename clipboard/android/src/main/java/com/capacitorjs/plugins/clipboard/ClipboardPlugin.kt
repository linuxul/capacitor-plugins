package com.capacitorjs.plugins.clipboard

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
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
        val content =
            call.getString("string") ?: call.getString("image") ?: call.getString("url") ?: throw PluginException("No data provided")

        val response = implementation.write(call.getString("label"), content)
        if (!response.isSuccess) {
            throw PluginException(response.errorMessage)
        }
        call.resolve()
    }

    @PluginMethod
    public fun read(call: PluginCall) {
        val result = implementation.read() ?: throw PluginException("Unable to read clipboard from the given Context")
        val value = result.value ?: throw PluginException("There is no data on the clipboard")

        val resultJS = JSObject()
        resultJS.put("value", value)
        resultJS.put("type", result.type)

        call.resolve(resultJS)
    }
}
