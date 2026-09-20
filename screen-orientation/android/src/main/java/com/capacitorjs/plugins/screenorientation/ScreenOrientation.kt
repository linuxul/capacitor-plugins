package com.capacitorjs.plugins.screenorientation

import android.content.pm.ActivityInfo
import android.view.Surface
import androidx.appcompat.app.AppCompatActivity

public class ScreenOrientation(private val activity: AppCompatActivity) {
    private var configOrientation = 0

    public val currentOrientationType: String
        // An activity that is not attached to a display reports the default orientation
        get() = fromRotationToOrientationType(activity.display?.rotation ?: Surface.ROTATION_0)

    public fun lock(orientationType: String) {
        activity.requestedOrientation = fromOrientationTypeToEnum(orientationType)
    }

    public fun unlock() {
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    public fun hasOrientationChanged(orientation: Int): Boolean {
        if (orientation == configOrientation) {
            return false
        }
        configOrientation = orientation
        return true
    }

    private fun fromRotationToOrientationType(rotation: Int): String = when (rotation) {
        Surface.ROTATION_90 -> "landscape-primary"
        Surface.ROTATION_180 -> "portrait-secondary"
        Surface.ROTATION_270 -> "landscape-secondary"
        else -> "portrait-primary"
    }

    private fun fromOrientationTypeToEnum(orientationType: String): Int = when (orientationType) {
        "any" -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED

        "landscape", "landscape-primary" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE

        "landscape-secondary" -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE

        "portrait-secondary" -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT

        // Case: portrait-primary
        else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
}
