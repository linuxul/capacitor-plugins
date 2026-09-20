package com.capacitorjs.plugins.statusbar

import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

public class StatusBar(private val activity: AppCompatActivity, config: StatusBarConfig, private val listener: ChangeListener) {
    // save initial color of the status bar
    private var currentStatusBarColor: Int = statusBarColor
    private var currentStyle = "DEFAULT"

    init {
        setBackgroundColor(config.backgroundColor)
        setStyle(config.style)
        setOverlaysWebView(config.isOverlaysWebView)
        val info = getInfo()
        info.visible = true
        listener.onChange(statusBarOverlayChanged, info)
    }

    public fun setStyle(style: String) {
        val window = activity.window
        currentStyle = style
        val appliedStyle = if (style == "DEFAULT") styleForTheme else style

        WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = appliedStyle != "DARK"
    }

    private val styleForTheme: String
        get() {
            val currentNightMode = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            return if (currentNightMode != Configuration.UI_MODE_NIGHT_YES) "LIGHT" else "DARK"
        }

    public fun updateStyle() {
        setStyle(currentStyle)
    }

    public fun setBackgroundColor(color: Int) {
        val window = activity.window
        if (shouldSetStatusBarColor(isEdgeToEdgeOptOutEnabled(window))) {
            @Suppress("DEPRECATION")
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            statusBarColor = color
            currentStatusBarColor = color

            // only set foreground color if style is default
            if (currentStyle == "DEFAULT") {
                // determine if the color is light or dark using luminance and set icon color
                val isLightColor = ColorUtils.calculateLuminance(color) > 0.5
                WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = isLightColor
            }
        }
    }

    public fun hide() {
        val window = activity.window
        WindowCompat.getInsetsController(window, window.decorView).hide(WindowInsetsCompat.Type.statusBars())
        val info = getInfo()
        info.visible = false
        listener.onChange(statusBarVisibilityChanged, info)
    }

    public fun show() {
        val window = activity.window
        WindowCompat.getInsetsController(window, window.decorView).show(WindowInsetsCompat.Type.statusBars())
        val info = getInfo()
        info.visible = true
        listener.onChange(statusBarVisibilityChanged, info)
    }

    @Suppress("DEPRECATION")
    public fun setOverlaysWebView(overlays: Boolean) {
        val decorView = activity.window.decorView
        val uiOptions = decorView.systemUiVisibility
        if (overlays) {
            // Sets the layout to a fullscreen one that does not hide the actual status bar, so the WebView is displayed behind it.
            decorView.systemUiVisibility = uiOptions or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            currentStatusBarColor = statusBarColor
            statusBarColor = Color.TRANSPARENT
        } else {
            // Sets the layout to a normal one that displays the WebView below the status bar.
            decorView.systemUiVisibility =
                uiOptions and View.SYSTEM_UI_FLAG_LAYOUT_STABLE.inv() and View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN.inv()
            // recover the previous color of the status bar
            statusBarColor = currentStatusBarColor
        }
        listener.onChange(statusBarOverlayChanged, getInfo())
    }

    private fun shouldSetStatusBarColor(hasOptOut: Boolean): Boolean {
        val deviceApi = Build.VERSION.SDK_INT
        return when {
            // device below Android 15 - can always set status bar
            deviceApi < Build.VERSION_CODES.VANILLA_ICE_CREAM -> true

            // app targets 15 - can set status bar if opted out
            deviceApi == Build.VERSION_CODES.VANILLA_ICE_CREAM -> hasOptOut

            // app targets 16 - opt-out ignored or app targets 15 but there is not opt out
            else -> false
        }
    }

    private fun isEdgeToEdgeOptOutEnabled(window: Window): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            val value = TypedValue()
            window.context.theme.resolveAttribute(android.R.attr.windowOptOutEdgeToEdgeEnforcement, value, true)
            return value.data != 0 // value is set to -1 on true as of Android 15, so we have to do this.
        }
        return false
    }

    @Suppress("DEPRECATION")
    private val isOverlaid: Boolean
        get() =
            (activity.window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN) ==
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN

    public fun getInfo(): StatusBarInfo {
        val windowInsetsCompat = ViewCompat.getRootWindowInsets(activity.window.decorView)
        val isVisible = windowInsetsCompat != null && windowInsetsCompat.isVisible(WindowInsetsCompat.Type.statusBars())
        val info = StatusBarInfo()
        info.style = style
        info.overlays = isOverlaid
        info.visible = isVisible
        info.color = String.format("#%06X", 0xFFFFFF and statusBarColor)
        info.height = statusBarHeight
        return info
    }

    private val style: String
        get() {
            val window = activity.window
            return if (WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars) "LIGHT" else "DARK"
        }

    private val statusBarHeight: Int
        get() {
            val metrics = activity.resources.displayMetrics
            val insets = activity.windowManager.currentWindowMetrics.windowInsets
            return (insets.getInsets(WindowInsets.Type.statusBars()).top / metrics.density).toInt()
        }

    @Suppress("DEPRECATION")
    private var statusBarColor: Int
        get() = activity.window.statusBarColor
        set(color) {
            activity.window.statusBarColor = color
        }

    public fun interface ChangeListener {
        public fun onChange(eventName: String, info: StatusBarInfo)
    }

    public companion object {
        @Suppress("ktlint:standard:property-naming")
        public const val statusBarVisibilityChanged: String = "statusBarVisibilityChanged"

        @Suppress("ktlint:standard:property-naming")
        public const val statusBarOverlayChanged: String = "statusBarOverlayChanged"
    }
}
