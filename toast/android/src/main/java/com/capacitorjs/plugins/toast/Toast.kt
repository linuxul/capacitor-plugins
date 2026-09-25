package com.capacitorjs.plugins.toast

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Gravity

public object Toast {
    private const val GRAVITY_TOP = Gravity.TOP or Gravity.CENTER_HORIZONTAL
    private const val GRAVITY_CENTER = Gravity.CENTER_VERTICAL or Gravity.CENTER_HORIZONTAL

    /**
     * Shows a toast from any thread: it is posted to the main thread.
     */
    public fun show(context: Context, text: String, duration: Int = android.widget.Toast.LENGTH_LONG, position: String? = "bottom") {
        Handler(Looper.getMainLooper()).post { showNow(context, text, duration, position) }
    }

    /**
     * Shows a toast right away. Call on the main thread.
     */
    internal fun showNow(context: Context, text: String, duration: Int, position: String?) {
        val toast = android.widget.Toast.makeText(context, text, duration)
        when (position) {
            "top" -> toast.setGravity(GRAVITY_TOP, 0, 40)
            "center" -> toast.setGravity(GRAVITY_CENTER, 0, 0)
        }
        toast.show()
    }
}
