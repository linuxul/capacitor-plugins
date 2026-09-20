package com.capacitorjs.plugins.browser

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsCallback
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsServiceConnection
import androidx.browser.customtabs.CustomTabsSession

/**
 * The Browser class implements Custom Chrome Tabs. See
 * https://developer.chrome.com/multidevice/android/customtabs for background
 * on how this code works.
 */
public class Browser(private val context: Context) {
    /**
     * Interface for callbacks for browser events.
     */
    internal fun interface BrowserEventListener {
        fun onBrowserEvent(event: Int)
    }

    /**
     * The object that receives callbacks.
     */
    internal var browserEventListener: BrowserEventListener? = null

    private var customTabsClient: CustomTabsClient? = null
    private var browserSession: CustomTabsSession? = null
    private var isInitialLoad = false
    private val group = EventGroup(::handleGroupCompletion)
    private val connection: CustomTabsServiceConnection =
        object : CustomTabsServiceConnection() {
            override fun onCustomTabsServiceConnected(name: ComponentName, client: CustomTabsClient) {
                customTabsClient = client
                client.warmup(0)
            }

            override fun onServiceDisconnected(name: ComponentName?) {}
        }

    /**
     * Open the browser to the specified URL, optionally with the specified toolbar color.
     * @param url
     * @param toolbarColor
     */
    @JvmOverloads
    public fun open(url: Uri, toolbarColor: Int? = null) {
        val builder = CustomTabsIntent.Builder(customTabsSession)

        builder.setShareState(CustomTabsIntent.SHARE_STATE_ON)

        if (toolbarColor != null) {
            val params = CustomTabColorSchemeParams.Builder().setToolbarColor(toolbarColor).build()
            builder.setDefaultColorSchemeParams(params)
        }

        val tabsIntent = builder.build()
        tabsIntent.intent.putExtra(Intent.EXTRA_REFERRER, Uri.parse(Intent.URI_ANDROID_APP_SCHEME.toString() + "//" + context.packageName))

        isInitialLoad = true
        group.reset()
        tabsIntent.launchUrl(context, url)
    }

    /**
     * Bind to the custom tabs service, required to be called in the `onResume` lifecycle event.
     */
    public fun bindService(): Boolean {
        val customTabPackageName = CustomTabsClient.getPackageName(context, null) ?: FALLBACK_CUSTOM_TAB_PACKAGE_NAME
        val result = CustomTabsClient.bindCustomTabsService(context, customTabPackageName, connection)
        group.leave()
        return result
    }

    /**
     * Unbind the custom tabs service, required to be called in the `onPause` lifecycle event.
     */
    public fun unbindService() {
        context.unbindService(connection)
        group.enter()
    }

    private fun handledNavigationEvent(navigationEvent: Int) {
        when (navigationEvent) {
            CustomTabsCallback.NAVIGATION_FINISHED ->
                if (isInitialLoad) {
                    browserEventListener?.onBrowserEvent(BROWSER_LOADED)
                    isInitialLoad = false
                }

            CustomTabsCallback.TAB_HIDDEN -> group.leave()

            CustomTabsCallback.TAB_SHOWN -> group.enter()
        }
    }

    private fun handleGroupCompletion() {
        // events such as TAB_HIDDEN and onPause can occur for multiple reasons and in
        // different sequences so there is no single point to fire this. so we rely on the
        // event group to track when it is safe to assume that the browser is done.
        browserEventListener?.onBrowserEvent(BROWSER_FINISHED)
    }

    private val customTabsSession: CustomTabsSession?
        get() {
            val client = customTabsClient ?: return null

            if (browserSession == null) {
                browserSession =
                    client.newSession(
                        object : CustomTabsCallback() {
                            override fun onNavigationEvent(navigationEvent: Int, extras: Bundle?) {
                                handledNavigationEvent(navigationEvent)
                            }
                        }
                    )
            }

            return browserSession
        }

    public companion object {
        /**
         * Sent when the browser has loaded the initial page.
         */
        public const val BROWSER_LOADED: Int = 1

        /**
         * Sent when the browser is finished.
         */
        public const val BROWSER_FINISHED: Int = 2

        private const val FALLBACK_CUSTOM_TAB_PACKAGE_NAME = "com.android.chrome"
    }
}
