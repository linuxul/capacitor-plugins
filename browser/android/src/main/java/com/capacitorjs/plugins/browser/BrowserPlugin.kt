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

        val intent = Intent(context, BrowserControllerActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        val finalToolbarColor = toolbarColor
        browserControllerListener =
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

    private fun onBrowserEvent(event: Int) {
        when (event) {
            Browser.BROWSER_LOADED -> notifyListeners("browserPageLoaded", null)
            Browser.BROWSER_FINISHED -> notifyListeners("browserFinished", null)
        }
    }

    public companion object {
        private var browserControllerActivityInstance: BrowserControllerActivity? = null

        /**
         * Called by [BrowserControllerActivity] once it is ready. Clearing it also forgets the activity.
         */
        @JvmStatic
        public var browserControllerListener: BrowserControllerListener? = null
            set(listener) {
                field = listener
                if (listener == null) {
                    browserControllerActivityInstance = null
                }
            }
    }
}
