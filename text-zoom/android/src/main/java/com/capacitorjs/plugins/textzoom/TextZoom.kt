package com.capacitorjs.plugins.textzoom

import android.app.Activity
import android.webkit.WebView

public class TextZoom internal constructor(internal val activity: Activity, internal val webView: WebView) {
    public fun get(): Double = webView.settings.textZoom.toDouble() / 100

    public fun set(level: Double) {
        webView.settings.textZoom = Math.round(level * 100).toInt()
    }

    public val preferred: Double
        get() = activity.resources.configuration.fontScale.toString().toDouble()
}
