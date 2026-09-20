package com.capacitorjs.plugins.splashscreen

public class SplashScreenSettings {
    public var showDuration: Int = 3000
    public var fadeInDuration: Int = 200
    public var fadeOutDuration: Int = 200

    @get:JvmName("isAutoHide")
    public var autoHide: Boolean = true
}
