package com.capacitorjs.plugins.screenorientation

import android.content.res.Configuration
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "ScreenOrientation")
public class ScreenOrientationPlugin : Plugin() {
    private lateinit var implementation: ScreenOrientation

    override fun load() {
        implementation = ScreenOrientation(activity)
    }

    @PluginMethod
    public fun orientation(call: PluginCall) {
        val ret = JSObject()
        ret.put("type", implementation.currentOrientationType)
        call.resolve(ret)
    }

    @PluginMethod
    public fun lock(call: PluginCall) {
        val orientationType = call.getString("orientation")
        if (orientationType == null) {
            call.reject("Input option 'orientation' must be provided.")
            return
        }
        implementation.lock(orientationType)
        call.resolve()
    }

    @PluginMethod
    public fun unlock(call: PluginCall) {
        implementation.unlock()
        call.resolve()
    }

    override fun handleOnConfigurationChanged(newConfig: Configuration?) {
        super.handleOnConfigurationChanged(newConfig)
        if (newConfig != null && implementation.hasOrientationChanged(newConfig.orientation)) {
            onOrientationChanged()
        }
    }

    private fun onOrientationChanged() {
        val ret = JSObject()
        ret.put("type", implementation.currentOrientationType)
        notifyListeners("screenOrientationChange", ret)
    }
}
