package com.capacitorjs.plugins.toast

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Gravity

public object Toast {
    private const val GRAVITY_TOP = Gravity.TOP or Gravity.CENTER_HORIZONTAL
    private const val GRAVITY_CENTER = Gravity.CENTER_VERTICAL or Gravity.CENTER_HORIZONTAL

    public fun show(context: Context, text: String, duration: Int = android.widget.Toast.LENGTH_LONG, position: String? = "bottom") {
        Handler(Looper.getMainLooper()).post {
            val toast = android.widget.Toast.makeText(context, text, duration)
            when (position) {
                "top" -> toast.setGravity(GRAVITY_TOP, 0, 40)
                "center" -> toast.setGravity(GRAVITY_CENTER, 0, 0)
            }
            toast.show()
        }
    }
}
