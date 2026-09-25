package com.capacitorjs.plugins.dialog

import android.app.AlertDialog
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.EditText

public object Dialog {
    public fun interface OnResultListener {
        public fun onResult(value: Boolean, didCancel: Boolean, inputValue: String?)
    }

    public fun interface OnCancelListener {
        public fun onCancel()
    }

    /**
     * Runs [block] right away on the main thread, and posts it to the main thread from any other thread. DialogPlugin
     * calls from the main thread, so what showing a dialog throws rejects its call instead of crashing the app.
     */
    private inline fun onMainThread(crossinline block: () -> Unit) {
        val mainLooper = Looper.getMainLooper()
        if (mainLooper.isCurrentThread) {
            block()
        } else {
            Handler(mainLooper).post { block() }
        }
    }

    /**
     * Show an alert window
     * @param context the context
     * @param message the message for the alert
     * @param title the title for the alert
     * @param okButtonTitle the title for the OK button, "OK" when null
     * @param listener the listener for returning data back
     */
    @JvmStatic
    public fun alert(context: Context, message: String?, title: String? = null, okButtonTitle: String? = null, listener: OnResultListener) {
        val alertOkButtonTitle = okButtonTitle ?: "OK"

        onMainThread {
            val builder = AlertDialog.Builder(context)

            if (title != null) {
                builder.setTitle(title)
            }
            builder
                .setMessage(message)
                .setPositiveButton(alertOkButtonTitle) { dialog, _ ->
                    dialog.dismiss()
                    listener.onResult(true, false, null)
                }.setOnCancelListener { dialog ->
                    dialog.dismiss()
                    listener.onResult(false, true, null)
                }

            builder.create().show()
        }
    }

    @JvmStatic
    public fun confirm(
        context: Context,
        message: String?,
        title: String? = null,
        okButtonTitle: String? = null,
        cancelButtonTitle: String? = null,
        listener: OnResultListener
    ) {
        val confirmOkButtonTitle = okButtonTitle ?: "OK"
        val confirmCancelButtonTitle = cancelButtonTitle ?: "Cancel"

        onMainThread {
            val builder = AlertDialog.Builder(context)
            if (title != null) {
                builder.setTitle(title)
            }
            builder
                .setMessage(message)
                .setPositiveButton(confirmOkButtonTitle) { dialog, _ ->
                    dialog.dismiss()
                    listener.onResult(true, false, null)
                }.setNegativeButton(confirmCancelButtonTitle) { dialog, _ ->
                    dialog.dismiss()
                    listener.onResult(false, false, null)
                }.setOnCancelListener { dialog ->
                    dialog.dismiss()
                    listener.onResult(false, true, null)
                }

            builder.create().show()
        }
    }

    @JvmStatic
    public fun prompt(
        context: Context,
        message: String?,
        title: String? = null,
        okButtonTitle: String? = null,
        cancelButtonTitle: String? = null,
        inputPlaceholder: String? = null,
        inputText: String? = null,
        listener: OnResultListener
    ) {
        val promptOkButtonTitle = okButtonTitle ?: "OK"
        val promptCancelButtonTitle = cancelButtonTitle ?: "Cancel"
        val promptInputPlaceholder = inputPlaceholder ?: ""
        val promptInputText = inputText ?: ""

        onMainThread {
            val builder = AlertDialog.Builder(context)
            val input = EditText(context)

            input.hint = promptInputPlaceholder
            input.setText(promptInputText)
            if (title != null) {
                builder.setTitle(title)
            }
            builder
                .setMessage(message)
                .setView(input)
                .setPositiveButton(promptOkButtonTitle) { dialog, _ ->
                    dialog.dismiss()

                    val enteredText = input.text.toString().trim { it <= ' ' }
                    listener.onResult(true, false, enteredText)
                }.setNegativeButton(promptCancelButtonTitle) { dialog, _ ->
                    dialog.dismiss()
                    listener.onResult(false, true, null)
                }.setOnCancelListener { dialog ->
                    dialog.dismiss()
                    listener.onResult(false, true, null)
                }

            builder.create().show()
        }
    }
}
