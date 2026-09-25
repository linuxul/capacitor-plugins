package com.capacitorjs.plugins.splashscreen

import android.widget.ImageView
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.util.WebColor
import java.util.Locale

@CapacitorPlugin(name = "SplashScreen")
public class SplashScreenPlugin : Plugin() {
    private lateinit var splashScreen: SplashScreen
    private lateinit var splashScreenConfig: SplashScreenConfig

    override fun load() {
        splashScreenConfig = readSplashScreenConfig()
        splashScreen = SplashScreen(context, splashScreenConfig)
        if (!bridge.isMinimumWebViewInstalled() && bridge.config.errorPath != null && !splashScreenConfig.launchAutoHide) {
            return
        }
        splashScreen.showOnLaunch(activity)
    }

    // The splash screen's views and state belong to the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun show(call: PluginCall) {
        splashScreen.show(
            activity,
            getSettings(call),
            object : SplashListener {
                override fun completed() {
                    call.resolve()
                }

                override fun error() {
                    call.reject("An error occurred while showing splash")
                }
            }
        )
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun hide(call: PluginCall) {
        if (splashScreenConfig.isUsingDialog) {
            splashScreen.hideDialog(activity)
        } else {
            splashScreen.hide(getSettings(call))
        }
        call.resolve()
    }

    override fun handleOnPause() {
        splashScreen.onPause()
    }

    override fun handleOnDestroy() {
        splashScreen.onDestroy()
    }

    private fun getSettings(call: PluginCall): SplashScreenSettings {
        val settings = SplashScreenSettings()
        call.getInt("showDuration")?.let { settings.showDuration = it }
        call.getInt("fadeInDuration")?.let { settings.fadeInDuration = it }
        call.getInt("fadeOutDuration")?.let { settings.fadeOutDuration = it }
        call.getBoolean("autoHide")?.let { settings.autoHide = it }
        return settings
    }

    private fun readSplashScreenConfig(): SplashScreenConfig {
        val splashConfig = SplashScreenConfig()
        val backgroundColor = config.getString("backgroundColor")
        if (backgroundColor != null) {
            try {
                splashConfig.backgroundColor = WebColor.parseColor(backgroundColor)
            } catch (ex: IllegalArgumentException) {
                Logger.debug("Background color not applied")
            }
        }
        splashConfig.launchShowDuration = config.getInt("launchShowDuration", splashConfig.launchShowDuration)
        splashConfig.launchFadeOutDuration = config.getInt("launchFadeOutDuration", splashConfig.launchFadeOutDuration)
        splashConfig.launchAutoHide = config.getBoolean("launchAutoHide", splashConfig.launchAutoHide)
        config.getString("androidSplashResourceName")?.let { splashConfig.resourceName = it }
        splashConfig.isImmersive = config.getBoolean("splashImmersive", splashConfig.isImmersive)
        splashConfig.isFullScreen = config.getBoolean("splashFullScreen", splashConfig.isFullScreen)

        val spinnerStyle = config.getString("androidSpinnerStyle")
        if (spinnerStyle != null) {
            splashConfig.spinnerStyle =
                when (spinnerStyle.lowercase(Locale.ROOT)) {
                    "horizontal" -> android.R.attr.progressBarStyleHorizontal
                    "small" -> android.R.attr.progressBarStyleSmall
                    "large" -> android.R.attr.progressBarStyleLarge
                    "inverse" -> android.R.attr.progressBarStyleInverse
                    "smallinverse" -> android.R.attr.progressBarStyleSmallInverse
                    "largeinverse" -> android.R.attr.progressBarStyleLargeInverse
                    else -> android.R.attr.progressBarStyleLarge
                }
        }
        val spinnerColor = config.getString("spinnerColor")
        if (spinnerColor != null) {
            try {
                splashConfig.spinnerColor = WebColor.parseColor(spinnerColor)
            } catch (ex: IllegalArgumentException) {
                Logger.debug("Spinner color not applied")
            }
        }
        val scaleTypeName = config.getString("androidScaleType")
        if (scaleTypeName != null) {
            splashConfig.scaleType =
                try {
                    ImageView.ScaleType.valueOf(scaleTypeName)
                } catch (ex: IllegalArgumentException) {
                    ImageView.ScaleType.FIT_XY
                }
        }

        splashConfig.showSpinner = config.getBoolean("showSpinner", splashConfig.showSpinner)
        splashConfig.isUsingDialog = config.getBoolean("useDialog", splashConfig.isUsingDialog)
        config.getString("layoutName")?.let { splashConfig.layoutName = it }

        return splashConfig
    }
}
