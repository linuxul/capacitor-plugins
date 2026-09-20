package com.capacitorjs.plugins.device

import android.os.Build
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.util.Locale

@CapacitorPlugin(name = "Device")
public class DevicePlugin : Plugin() {
    private lateinit var implementation: Device

    override fun load() {
        implementation = Device(context)
    }

    @PluginMethod
    public fun getId(call: PluginCall) {
        val r = JSObject()

        r.put("identifier", implementation.uuid)

        call.resolve(r)
    }

    @PluginMethod
    public fun getInfo(call: PluginCall) {
        val r = JSObject()

        r.put("memUsed", implementation.memUsed)
        r.put("model", Build.MODEL)
        r.put("operatingSystem", "android")
        r.put("osVersion", Build.VERSION.RELEASE)
        r.put("androidSDKVersion", Build.VERSION.SDK_INT)
        r.put("platform", implementation.platform)
        r.put("manufacturer", Build.MANUFACTURER)
        r.put("isVirtual", implementation.isVirtual)
        r.put("name", implementation.name)
        r.put("webViewVersion", implementation.webViewVersion)

        call.resolve(r)
    }

    @PluginMethod
    public fun getBatteryInfo(call: PluginCall) {
        val r = JSObject()

        // Java widened the float to a double here, which is the number JavaScript has been receiving
        r.put("batteryLevel", implementation.batteryLevel.toDouble())
        r.put("isCharging", implementation.isCharging)

        call.resolve(r)
    }

    @PluginMethod
    public fun getLanguageCode(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", Locale.getDefault().language)
        call.resolve(ret)
    }

    @PluginMethod
    public fun getLanguageTag(call: PluginCall) {
        val ret = JSObject()
        ret.put("value", Locale.getDefault().toLanguageTag())
        call.resolve(ret)
    }
}
