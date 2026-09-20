package com.capacitorjs.plugins.browser

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

public class BrowserControllerActivity : Activity() {
    private var isCustomTabsOpen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        isCustomTabsOpen = false

        BrowserPlugin.browserControllerListener?.onControllerReady(this)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent?.hasExtra("close") == true) {
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        if (isCustomTabsOpen) {
            isCustomTabsOpen = false
            finish()
        } else {
            isCustomTabsOpen = true
        }
    }

    public fun open(implementation: Browser, url: Uri, toolbarColor: Int?) {
        implementation.open(url, toolbarColor)
    }

    override fun onDestroy() {
        super.onDestroy()
        isCustomTabsOpen = false
        BrowserPlugin.browserControllerListener = null
    }
}
