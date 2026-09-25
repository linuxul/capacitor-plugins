package com.capacitorjs.plugins.browser

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.util.WebColor

@CapacitorPlugin(name = "Browser")
public class BrowserPlugin : Plugin() {
    private lateinit var implementation: Browser

    // The listener this plugin handed to BrowserControllerActivity
    @Volatile
    private var ownControllerListener: BrowserControllerListener? = null

    override fun load() {
        implementation = Browser(context)
        implementation.browserEventListener = Browser.BrowserEventListener(::onBrowserEvent)
    }

    @PluginMethod
    public fun open(call: PluginCall) {
        // get the URL
        val urlString = call.getString("url")
        if (urlString == null) {
            call.reject("Must provide a URL to open")
            return
        }
        if (urlString.isEmpty()) {
            call.reject("URL must not be empty")
            return
        }
        val url: Uri
        try {
            url = Uri.parse(urlString)
        } catch (ex: Exception) {
            call.reject(ex.localizedMessage)
            return
        }

        // get the toolbar color, if provided
        val colorString = call.getString("toolbarColor")
        var toolbarColor: Int? = null
        if (colorString != null) {
            try {
                toolbarColor = WebColor.parseColor(colorString)
            } catch (ex: IllegalArgumentException) {
                Logger.error(logTag, "Invalid color provided for toolbarColor. Using default", null)
            }
        }

        // open the browser and finish

        val finalToolbarColor = toolbarColor
        val listener =
            BrowserControllerListener { activity ->
                try {
                    activity.open(implementation, url, finalToolbarColor)
                    browserControllerActivityInstance = activity
                    call.resolve()
                } catch (ex: ActivityNotFoundException) {
                    Logger.error(logTag, ex.localizedMessage, null)
                    call.reject("Unable to display URL")
                }
            }
        // Set before the activity starts, which reads it on the main thread as soon as it is created. Set after, the
        // activity could find no listener and leave the call pending.
        ownControllerListener = listener
        browserControllerListener = listener

        val intent = Intent(context, BrowserControllerActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    @PluginMethod
    public fun close(call: PluginCall) {
        if (browserControllerActivityInstance != null) {
            browserControllerActivityInstance = null
            val intent = Intent(context, BrowserControllerActivity::class.java)
            intent.putExtra("close", true)
            context.startActivity(intent)
        }
        call.resolve()
    }

    override fun handleOnResume() {
        if (!implementation.bindService()) {
            Logger.error(logTag, "Error binding to custom tabs service", null)
        }
    }

    override fun handleOnPause() {
        implementation.unbindService()
    }

    override fun handleOnDestroy() {
        // The listener holds this plugin, and through it the activity, until the browser closes. Only the listener is
        // dropped: the browser runs in its own task, and a new plugin instance must still be able to close it.
        val listener = ownControllerListener ?: return
        ownControllerListener = null
        if (controllerListener === listener) {
            controllerListener = null
        }
    }

    private fun onBrowserEvent(event: Int) {
        when (event) {
            Browser.BROWSER_LOADED -> notifyListeners("browserPageLoaded", null)
            Browser.BROWSER_FINISHED -> notifyListeners("browserFinished", null)
        }
    }

    public companion object {
        // Both are used from the bridge thread and from the main thread
        @Volatile
        private var browserControllerActivityInstance: BrowserControllerActivity? = null

        @Volatile
        private var controllerListener: BrowserControllerListener? = null

        /**
         * Called by [BrowserControllerActivity] once it is ready. Clearing it also forgets the activity.
         */
        @JvmStatic
        public var browserControllerListener: BrowserControllerListener?
            get() = controllerListener
            set(listener) {
                controllerListener = listener
                if (listener == null) {
                    browserControllerActivityInstance = null
                }
            }
    }
}
