package com.capacitorjs.plugins.preferences

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences

public class Preferences internal constructor(context: Context, configuration: PreferencesConfiguration) {
    private val preferences: SharedPreferences = context.getSharedPreferences(configuration.group, Activity.MODE_PRIVATE)

    public fun get(key: String?): String? = preferences.getString(key, null)

    public fun set(key: String?, value: String?) {
        executeOperation { putString(key, value) }
    }

    public fun remove(key: String?) {
        executeOperation { remove(key) }
    }

    public fun keys(): Set<String> = preferences.all.keys

    public fun clear() {
        executeOperation { clear() }
    }

    private fun executeOperation(operation: SharedPreferences.Editor.() -> Unit) {
        val editor = preferences.edit()
        editor.operation()
        editor.apply()
    }
}
