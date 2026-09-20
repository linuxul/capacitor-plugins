package com.capacitorjs.plugins.preferences

import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONException
import org.json.JSONObject

@CapacitorPlugin(name = "Preferences")
public class PreferencesPlugin : Plugin() {
    private lateinit var preferences: Preferences

    override fun load() {
        preferences = Preferences(context, PreferencesConfiguration.DEFAULTS)
    }

    @PluginMethod
    public fun configure(call: PluginCall) {
        val group = call.getString("group") ?: PreferencesConfiguration.DEFAULTS.group
        preferences = Preferences(context, PreferencesConfiguration(group))
        call.resolve()
    }

    @PluginMethod
    public fun get(call: PluginCall) {
        val key = call.getString("key")
        if (key == null) {
            call.reject("Must provide key")
            return
        }

        val value = preferences.get(key)

        val ret = JSObject()
        ret.put("value", value ?: JSONObject.NULL)
        call.resolve(ret)
    }

    @PluginMethod
    public fun set(call: PluginCall) {
        val key = call.getString("key")
        if (key == null) {
            call.reject("Must provide key")
            return
        }

        preferences.set(key, call.getString("value"))

        call.resolve()
    }

    @PluginMethod
    public fun remove(call: PluginCall) {
        val key = call.getString("key")
        if (key == null) {
            call.reject("Must provide key")
            return
        }

        preferences.remove(key)

        call.resolve()
    }

    @PluginMethod
    public fun keys(call: PluginCall) {
        val keys = preferences.keys().toTypedArray()

        val ret = JSObject()
        try {
            ret.put("keys", JSArray(keys))
        } catch (ex: JSONException) {
            call.reject("Unable to serialize response.", ex = ex)
            return
        }
        call.resolve(ret)
    }

    @PluginMethod
    public fun clear(call: PluginCall) {
        preferences.clear()
        call.resolve()
    }

    @PluginMethod
    public fun migrate(call: PluginCall) {
        val migrated = ArrayList<String>()
        val existing = ArrayList<String>()
        val oldPreferences = Preferences(context, PreferencesConfiguration.DEFAULTS)

        for (key in oldPreferences.keys()) {
            val value = oldPreferences.get(key)
            val currentValue = preferences.get(key)

            if (currentValue == null) {
                preferences.set(key, value)
                migrated.add(key)
            } else {
                existing.add(key)
            }
        }

        val ret = JSObject()
        ret.put("migrated", JSArray(migrated))
        ret.put("existing", JSArray(existing))
        call.resolve(ret)
    }

    @PluginMethod
    public fun removeOld(call: PluginCall) {
        call.resolve()
    }
}
