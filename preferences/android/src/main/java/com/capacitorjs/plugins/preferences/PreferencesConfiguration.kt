package com.capacitorjs.plugins.preferences

public class PreferencesConfiguration internal constructor(internal val group: String) {
    internal companion object {
        val DEFAULTS = PreferencesConfiguration("CapacitorStorage")
    }
}
