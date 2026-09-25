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
     * Runs [block] right away on the main thread, and posts it to the main thread from any other thread, so that the
     * public functions can be called from any thread.
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
        onMainThread { buildAlert(context, message, title, okButtonTitle, listener).show() }
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
        onMainThread { buildConfirm(context, message, title, okButtonTitle, cancelButtonTitle, listener).show() }
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
        onMainThread {
            buildPrompt(context, message, title, okButtonTitle, cancelButtonTitle, inputPlaceholder, inputText, listener).show()
        }
    }

    /**
     * The dialog [alert] shows, not shown yet. Call on the main thread.
     */
    internal fun buildAlert(
        context: Context,
        message: String?,
        title: String?,
        okButtonTitle: String?,
        listener: OnResultListener
    ): AlertDialog {
        val builder = AlertDialog.Builder(context)

        if (title != null) {
            builder.setTitle(title)
        }
        builder
            .setMessage(message)
            .setPositiveButton(okButtonTitle ?: "OK") { dialog, _ ->
                dialog.dismiss()
                listener.onResult(true, false, null)
            }.setOnCancelListener { dialog ->
                dialog.dismiss()
                listener.onResult(false, true, null)
            }

        return builder.create()
    }

    /**
     * The dialog [confirm] shows, not shown yet. Call on the main thread.
     */
    internal fun buildConfirm(
        context: Context,
        message: String?,
        title: String?,
        okButtonTitle: String?,
        cancelButtonTitle: String?,
        listener: OnResultListener
    ): AlertDialog {
        val builder = AlertDialog.Builder(context)
        if (title != null) {
            builder.setTitle(title)
        }
        builder
            .setMessage(message)
            .setPositiveButton(okButtonTitle ?: "OK") { dialog, _ ->
                dialog.dismiss()
                listener.onResult(true, false, null)
            }.setNegativeButton(cancelButtonTitle ?: "Cancel") { dialog, _ ->
                dialog.dismiss()
                listener.onResult(false, false, null)
            }.setOnCancelListener { dialog ->
                dialog.dismiss()
                listener.onResult(false, true, null)
            }

        return builder.create()
    }

    /**
     * The dialog [prompt] shows, not shown yet. Call on the main thread.
     */
    internal fun buildPrompt(
        context: Context,
        message: String?,
        title: String?,
        okButtonTitle: String?,
        cancelButtonTitle: String?,
        inputPlaceholder: String?,
        inputText: String?,
        listener: OnResultListener
    ): AlertDialog {
        val builder = AlertDialog.Builder(context)
        val input = EditText(context)

        input.hint = inputPlaceholder ?: ""
        input.setText(inputText ?: "")
        if (title != null) {
            builder.setTitle(title)
        }
        builder
            .setMessage(message)
            .setView(input)
            .setPositiveButton(okButtonTitle ?: "OK") { dialog, _ ->
                dialog.dismiss()

                val enteredText = input.text.toString().trim { it <= ' ' }
                listener.onResult(true, false, enteredText)
            }.setNegativeButton(cancelButtonTitle ?: "Cancel") { dialog, _ ->
                dialog.dismiss()
                listener.onResult(false, true, null)
            }.setOnCancelListener { dialog ->
                dialog.dismiss()
                listener.onResult(false, true, null)
            }

        return builder.create()
    }
}
