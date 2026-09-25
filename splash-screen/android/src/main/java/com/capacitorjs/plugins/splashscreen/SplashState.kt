package com.capacitorjs.plugins.splashscreen

/**
 * Whether the splash screen is on screen and whether it is being hidden.
 *
 * It belongs to one thread, the main thread in the app: the plugin's show and hide run there, and so do the lifecycle
 * callbacks, the animations and the delayed hides that change it. Using it from any other thread throws an
 * [IllegalStateException] instead of racing with the main thread, as the bridge thread used to.
 *
 * @param isOwnerThread whether the current thread is the one the state belongs to
 */
internal class SplashState(private val isOwnerThread: () -> Boolean) {
    /**
     * The splash is on screen, or the launch splash is being kept on screen.
     */
    var isVisible: Boolean = false
        get() {
            checkOwnerThread()
            return field
        }
        set(value) {
            checkOwnerThread()
            field = value
        }

    /**
     * The splash is fading out.
     */
    var isHiding: Boolean = false
        get() {
            checkOwnerThread()
            return field
        }
        set(value) {
            checkOwnerThread()
            field = value
        }

    /**
     * Whether the Android 12 launch splash has to stay on screen: while it is shown and while it fades out.
     */
    val keepsLaunchSplash: Boolean
        get() = isVisible || isHiding

    /**
     * The splash is gone: neither visible nor being hidden.
     */
    fun hidden() {
        isHiding = false
        isVisible = false
    }

    private fun checkOwnerThread() {
        check(isOwnerThread()) {
            "The splash screen is used from thread ${Thread.currentThread().name}; only the main thread may use it"
        }
    }
}
