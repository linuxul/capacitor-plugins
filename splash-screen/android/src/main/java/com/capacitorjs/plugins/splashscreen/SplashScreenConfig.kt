package com.capacitorjs.plugins.splashscreen

import android.widget.ImageView.ScaleType

public class SplashScreenConfig {
    public var backgroundColor: Int? = null
    public var spinnerStyle: Int? = null
    public var spinnerColor: Int? = null

    @get:JvmName("isShowSpinner")
    public var showSpinner: Boolean = false
    public var launchShowDuration: Int = 500

    @get:JvmName("isLaunchAutoHide")
    public var launchAutoHide: Boolean = true
    public val launchFadeInDuration: Int = 0
    public var launchFadeOutDuration: Int = 200
    public var resourceName: String = "splash"
    public var isImmersive: Boolean = false
    public var isFullScreen: Boolean = false
    public var scaleType: ScaleType = ScaleType.FIT_XY
    public var isUsingDialog: Boolean = false
    public var layoutName: String? = null
}
