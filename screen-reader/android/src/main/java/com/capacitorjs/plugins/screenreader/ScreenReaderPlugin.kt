package com.capacitorjs.plugins.screenreader

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "ScreenReader")
public class ScreenReaderPlugin : Plugin() {
    private lateinit var screenReader: ScreenReader

    override fun load() {
        screenReader = ScreenReader(context)
        screenReader.addStateChangeListener { enabled ->
            val ret = JSObject()
            ret.put("value", enabled)
            notifyListeners(EVENT_STATE_CHANGE, ret)
        }
    }

    override fun handleOnDestroy() {
        screenReader.removeAllListeners()
    }

    @PluginMethod
    public fun isEnabled(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", screenReader.isEnabled)
        call.resolve(ret)
    }

    @PluginMethod
    public fun speak(call: PluginCall) {
        val value = call.getString("value")
        val language = call.getString("language") ?: "en"
        screenReader.speak(value, language)
        call.resolve()
    }

    public companion object {
        public const val EVENT_STATE_CHANGE: String = "stateChange"
    }
}
