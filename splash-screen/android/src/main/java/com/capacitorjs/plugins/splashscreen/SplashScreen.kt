package com.capacitorjs.plugins.splashscreen

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Resources
import android.graphics.PixelFormat
import android.graphics.drawable.Animatable
import android.graphics.drawable.Drawable
import android.graphics.drawable.LayerDrawable
import android.os.Handler
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver.OnPreDrawListener
import android.view.WindowInsetsController
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import androidx.appcompat.app.AppCompatActivity
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.getcapacitor.Logger

/**
 * A Splash Screen service for showing and hiding a splash screen in the app.
 */
public class SplashScreen internal constructor(private val context: Context, private val config: SplashScreenConfig) {
    private var dialog: Dialog? = null
    private var splashImage: View? = null
    private var spinnerBar: ProgressBar? = null
    private var windowManager: WindowManager? = null
    private var isVisible = false
    private var isHiding = false
    private var content: View? = null
    private var onPreDrawListener: OnPreDrawListener? = null

    /**
     * Show the splash screen on launch without fading in
     */
    public fun showOnLaunch(activity: AppCompatActivity) {
        if (config.launchShowDuration == 0) {
            return
        }
        val settings = SplashScreenSettings()
        settings.showDuration = config.launchShowDuration
        settings.autoHide = config.launchAutoHide

        // Method can fail if styles are incorrectly set...
        // If it fails, log error & fallback to old method
        try {
            showWithAndroid12API(activity, settings)
            return
        } catch (e: Exception) {
            Logger.warn("Android 12 Splash API failed... using previous method.")
            onPreDrawListener = null
        }

        settings.fadeInDuration = config.launchFadeInDuration
        if (config.isUsingDialog) {
            showDialog(activity, settings, null, true)
        } else {
            show(activity, settings, null, true)
        }
    }

    /**
     * Show the Splash Screen using the Android 12 API
     *
     * @param settings Settings used to show the Splash Screen
     */
    private fun showWithAndroid12API(activity: AppCompatActivity, settings: SplashScreenSettings) {
        if (activity.isFinishing) return

        activity.runOnUiThread {
            val windowSplashScreen = activity.installSplashScreen()
            windowSplashScreen.setKeepOnScreenCondition { isVisible || isHiding }

            if (config.launchFadeOutDuration > 0) {
                // Set Fade Out Animation
                windowSplashScreen.setOnExitAnimationListener { windowSplashScreenView ->
                    val fadeAnimator = ObjectAnimator.ofFloat(windowSplashScreenView.view, View.ALPHA, 1f, 0f)
                    fadeAnimator.interpolator = LinearInterpolator()
                    fadeAnimator.duration = config.launchFadeOutDuration.toLong()

                    fadeAnimator.addListener(
                        object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) {
                                isHiding = false
                                windowSplashScreenView.remove()
                                activity.splashScreen.clearOnExitAnimationListener()
                            }
                        }
                    )

                    fadeAnimator.start()

                    isHiding = true
                    isVisible = false
                }
            }

            // Set Pre Draw Listener & Delay Drawing Until Duration Elapses
            val content = activity.findViewById<View>(android.R.id.content)
            this.content = content

            val listener =
                object : OnPreDrawListener {
                    override fun onPreDraw(): Boolean {
                        // Start Timer On First Run
                        if (!isVisible && !isHiding) {
                            isVisible = true

                            Handler(context.mainLooper).postDelayed(
                                {
                                    // Splash screen is done... start drawing content.
                                    if (settings.autoHide) {
                                        isVisible = false
                                        onPreDrawListener = null
                                        content.viewTreeObserver.removeOnPreDrawListener(this)
                                    }
                                },
                                settings.showDuration.toLong()
                            )
                        }

                        // Not ready to dismiss splash screen
                        return false
                    }
                }
            onPreDrawListener = listener

            content.viewTreeObserver.addOnPreDrawListener(listener)
        }
    }

    /**
     * Show the Splash Screen
     *
     * @param settings Settings used to show the Splash Screen
     * @param splashListener A listener to handle the finish of the animation (if any)
     */
    public fun show(activity: AppCompatActivity, settings: SplashScreenSettings, splashListener: SplashListener?) {
        if (config.isUsingDialog) {
            showDialog(activity, settings, splashListener, false)
        } else {
            show(activity, settings, splashListener, false)
        }
    }

    private fun showDialog(
        activity: AppCompatActivity,
        settings: SplashScreenSettings,
        splashListener: SplashListener?,
        isLaunchSplash: Boolean
    ) {
        if (activity.isFinishing) return

        if (isVisible) {
            splashListener?.completed()
            return
        }

        activity.runOnUiThread {
            val style =
                when {
                    config.isImmersive -> R.style.capacitor_immersive_style
                    config.isFullScreen -> R.style.capacitor_full_screen_style
                    else -> R.style.capacitor_default_style
                }
            val dialog = Dialog(activity, style)
            this.dialog = dialog

            val splashId = getSplashLayoutId("Layout not found, using default")
            if (splashId != 0) {
                dialog.setContentView(splashId)
            } else {
                val splash = getSplashDrawable()
                val parent = LinearLayout(context)
                parent.layoutParams =
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                parent.orientation = LinearLayout.VERTICAL
                if (splash != null) {
                    parent.background = splash
                }
                dialog.setContentView(parent)
            }

            dialog.setCancelable(false)
            if (!dialog.isShowing) {
                dialog.show()
            }
            isVisible = true

            if (settings.autoHide) {
                Handler(context.mainLooper).postDelayed(
                    {
                        hideDialog(activity, isLaunchSplash)
                        splashListener?.completed()
                    },
                    settings.showDuration.toLong()
                )
            } else {
                // If no autoHide, call complete
                splashListener?.completed()
            }
        }
    }

    /**
     * Hide the Splash Screen
     *
     * @param settings Settings used to hide the Splash Screen
     */
    public fun hide(settings: SplashScreenSettings) {
        hide(settings.fadeOutDuration, false)
    }

    /**
     * Hide the Splash Screen when showing it as a dialog
     *
     * @param activity the activity showing the dialog
     */
    public fun hideDialog(activity: AppCompatActivity) {
        hideDialog(activity, false)
    }

    public fun onPause() {
        tearDown(true)
    }

    public fun onDestroy() {
        tearDown(true)
    }

    /**
     * The id of the configured layout, or 0 when none is configured or it does not exist
     */
    private fun getSplashLayoutId(notFoundMessage: String): Int {
        val layoutName = config.layoutName ?: return 0
        val splashId = context.resources.getIdentifier(layoutName, "layout", context.packageName)
        if (splashId == 0) {
            Logger.warn(notFoundMessage)
        }
        return splashId
    }

    private fun buildViews() {
        if (splashImage == null) {
            val splashId = getSplashLayoutId("Layout not found, defaulting to ImageView")

            val splashImage: View
            if (splashId != 0) {
                val root: ViewGroup = FrameLayout(context)
                root.layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                splashImage = (context as Activity).layoutInflater.inflate(splashId, root, false)
            } else {
                val splash = getSplashDrawable() ?: return
                if (splash is Animatable) {
                    splash.start()
                }

                if (splash is LayerDrawable) {
                    for (i in 0 until splash.numberOfLayers) {
                        val layerDrawable = splash.getDrawable(i)

                        if (layerDrawable is Animatable) {
                            layerDrawable.start()
                        }
                    }
                }

                val imageView = ImageView(context)
                // Stops flickers dead in their tracks
                // https://stackoverflow.com/a/21847579/32140
                imageView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
                imageView.scaleType = config.scaleType
                imageView.setImageDrawable(splash)
                splashImage = imageView
            }

            splashImage.fitsSystemWindows = true

            config.backgroundColor?.let { splashImage.setBackgroundColor(it) }
            this.splashImage = splashImage
        }

        if (spinnerBar == null) {
            val spinnerBarStyle = config.spinnerStyle
            val spinnerBar = if (spinnerBarStyle != null) ProgressBar(context, null, spinnerBarStyle) else ProgressBar(context)
            spinnerBar.isIndeterminate = true

            val spinnerBarColor = config.spinnerColor
            if (spinnerBarColor != null) {
                val states =
                    arrayOf(
                        // enabled
                        intArrayOf(android.R.attr.state_enabled),
                        // disabled
                        intArrayOf(-android.R.attr.state_enabled),
                        // unchecked
                        intArrayOf(-android.R.attr.state_checked),
                        // pressed
                        intArrayOf(android.R.attr.state_pressed)
                    )
                val colors = intArrayOf(spinnerBarColor, spinnerBarColor, spinnerBarColor, spinnerBarColor)
                spinnerBar.indeterminateTintList = ColorStateList(states, colors)
            }
            this.spinnerBar = spinnerBar
        }
    }

    private fun getSplashDrawable(): Drawable? {
        val splashId = context.resources.getIdentifier(config.resourceName, "drawable", context.packageName)
        return try {
            context.resources.getDrawable(splashId, context.theme)
        } catch (ex: Resources.NotFoundException) {
            Logger.warn("No splash screen found, not displaying")
            null
        }
    }

    private fun show(
        activity: AppCompatActivity,
        settings: SplashScreenSettings,
        splashListener: SplashListener?,
        isLaunchSplash: Boolean
    ) {
        val windowManager = activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        this.windowManager = windowManager

        if (activity.isFinishing) {
            return
        }

        buildViews()

        if (isVisible) {
            splashListener?.completed()
            return
        }

        val listener =
            object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animator: Animator) {
                    isVisible = true

                    if (settings.autoHide) {
                        Handler(context.mainLooper).postDelayed(
                            {
                                hide(settings.fadeOutDuration, isLaunchSplash)
                                splashListener?.completed()
                            },
                            settings.showDuration.toLong()
                        )
                    } else {
                        // If no autoHide, call complete
                        splashListener?.completed()
                    }
                }
            }

        Handler(context.mainLooper).post {
            val params = WindowManager.LayoutParams()
            params.gravity = Gravity.CENTER
            params.flags = activity.window.attributes.flags

            // Required to enable the view to actually fade
            params.format = PixelFormat.TRANSLUCENT

            // Without a splash drawable there is no view. The Java original handed null to the window manager, which
            // refused it with an IllegalArgumentException.
            val splashImage = splashImage
            if (splashImage == null) {
                Logger.debug("Could not add splash view")
                return@post
            }

            try {
                windowManager.addView(splashImage, params)
            } catch (ex: IllegalStateException) {
                Logger.debug("Could not add splash view")
                return@post
            } catch (ex: IllegalArgumentException) {
                Logger.debug("Could not add splash view")
                return@post
            }

            if (config.isImmersive) {
                activity.runOnUiThread {
                    WindowCompat.setDecorFitsSystemWindows(activity.window, false)
                    val controller = splashImage.windowInsetsController
                    controller?.hide(WindowInsetsCompat.Type.systemBars())
                    controller?.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else if (config.isFullScreen) {
                activity.runOnUiThread {
                    WindowCompat.setDecorFitsSystemWindows(activity.window, false)
                    splashImage.windowInsetsController?.hide(WindowInsetsCompat.Type.statusBars())
                }
            }

            splashImage.alpha = 0f

            splashImage
                .animate()
                .alpha(1f)
                .setInterpolator(LinearInterpolator())
                .setDuration(settings.fadeInDuration.toLong())
                .setListener(listener)
                .start()

            splashImage.visibility = View.VISIBLE

            val spinnerBar = spinnerBar
            if (spinnerBar != null) {
                spinnerBar.visibility = View.INVISIBLE

                if (spinnerBar.parent != null) {
                    windowManager.removeView(spinnerBar)
                }

                params.height = WindowManager.LayoutParams.WRAP_CONTENT
                params.width = WindowManager.LayoutParams.WRAP_CONTENT

                windowManager.addView(spinnerBar, params)

                if (config.showSpinner) {
                    spinnerBar.alpha = 0f

                    spinnerBar
                        .animate()
                        .alpha(1f)
                        .setInterpolator(LinearInterpolator())
                        .setDuration(settings.fadeInDuration.toLong())
                        .start()

                    spinnerBar.visibility = View.VISIBLE
                }
            }
        }
    }

    /**
     * Hides a launch splash that is shown with the Android 12 API.
     *
     * @return false when that is not how the splash is shown
     */
    private fun hideAndroid12Splash(): Boolean {
        val listener = onPreDrawListener ?: return false
        isVisible = false
        content?.viewTreeObserver?.removeOnPreDrawListener(listener)
        onPreDrawListener = null
        return true
    }

    private fun warnAboutAutomaticHide(isLaunchSplash: Boolean) {
        // Warn the user if the splash was hidden automatically, which means they could be experiencing an app
        // that feels slower than it actually is.
        if (isLaunchSplash && isVisible) {
            Logger.debug(
                "SplashScreen was automatically hidden after the launch timeout. " +
                    "You should call `SplashScreen.hide()` as soon as your web app is loaded (or increase the timeout)." +
                    "Read more at https://capacitorjs.com/docs/apis/splash-screen#hiding-the-splash-screen"
            )
        }
    }

    private fun hide(fadeOutDuration: Int, isLaunchSplash: Boolean) {
        warnAboutAutomaticHide(isLaunchSplash)

        if (isHiding) {
            return
        }

        // Hide with Android 12 API
        if (onPreDrawListener != null) {
            if (fadeOutDuration != 200) {
                Logger.warn(
                    "fadeOutDuration parameter doesn't work on initial splash screen, use launchFadeOutDuration configuration option"
                )
            }
            hideAndroid12Splash()
            return
        }

        val splashImage = splashImage
        if (splashImage == null || splashImage.parent == null) {
            return
        }

        isHiding = true

        val listener =
            object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animator: Animator) {
                    tearDown(false)
                }

                override fun onAnimationCancel(animator: Animator) {
                    tearDown(false)
                }
            }

        Handler(context.mainLooper).post {
            spinnerBar?.let { spinnerBar ->
                spinnerBar.alpha = 1f

                spinnerBar
                    .animate()
                    .alpha(0f)
                    .setInterpolator(LinearInterpolator())
                    .setDuration(fadeOutDuration.toLong())
                    .start()
            }

            splashImage.alpha = 1f

            splashImage
                .animate()
                .alpha(0f)
                .setInterpolator(LinearInterpolator())
                .setDuration(fadeOutDuration.toLong())
                .setListener(listener)
                .start()
        }
    }

    private fun hideDialog(activity: AppCompatActivity, isLaunchSplash: Boolean) {
        warnAboutAutomaticHide(isLaunchSplash)

        if (isHiding) {
            return
        }

        // Hide with Android 12 API
        if (hideAndroid12Splash()) {
            return
        }

        isHiding = true

        activity.runOnUiThread {
            val dialog = dialog
            if (dialog != null && dialog.isShowing) {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    dialog.dismiss()
                }
                this.dialog = null
                isHiding = false
                isVisible = false
            }
        }
    }

    private fun tearDown(removeSpinner: Boolean) {
        val spinnerBar = spinnerBar
        if (spinnerBar != null && spinnerBar.parent != null) {
            spinnerBar.visibility = View.INVISIBLE

            if (removeSpinner) {
                windowManager?.removeView(spinnerBar)
            }
        }

        val splashImage = splashImage
        if (splashImage != null && splashImage.parent != null) {
            splashImage.visibility = View.INVISIBLE

            windowManager?.removeView(splashImage)
        }

        if (config.isFullScreen || config.isImmersive) {
            // Exit fullscreen mode
            WindowCompat.setDecorFitsSystemWindows((context as Activity).window, true)
        }
        isHiding = false
        isVisible = false
    }
}
