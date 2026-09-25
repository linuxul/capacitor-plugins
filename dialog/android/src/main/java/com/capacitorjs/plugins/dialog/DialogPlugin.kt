package com.capacitorjs.plugins.dialog

import android.app.AlertDialog
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin
import kotlin.coroutines.suspendCoroutine

@CapacitorPlugin(name = "Dialog")
public class DialogPlugin : Plugin() {
    // The dialogs on screen, so that they close with the activity. Only the main thread uses it.
    private val shownDialogs = HashSet<AlertDialog>()

    // Dialogs are shown from the main thread, and each method returns once the user has answered
    @PluginMethod(thread = PluginThread.MAIN)
    public suspend fun alert(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val buttonTitle = call.getString("buttonTitle", "OK")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        showAndAwaitAnswer { listener -> Dialog.buildAlert(activity, message, title, buttonTitle, listener) }
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public suspend fun confirm(call: PluginCall): JSObject {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        val answer =
            showAndAwaitAnswer { listener ->
                Dialog.buildConfirm(activity, message, title, okButtonTitle, cancelButtonTitle, listener)
            }
        return JSObject().put("value", answer.value)
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public suspend fun prompt(call: PluginCall): JSObject {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")
        val inputPlaceholder = call.getString("inputPlaceholder", "")
        val inputText = call.getString("inputText", "")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        val answer =
            showAndAwaitAnswer { listener ->
                Dialog.buildPrompt(activity, message, title, okButtonTitle, cancelButtonTitle, inputPlaceholder, inputText, listener)
            }
        return JSObject().put("cancelled", answer.didCancel).put("value", answer.inputValue ?: "")
    }

    override fun handleOnDestroy() {
        // A dialog left open would leak its window. Its call has been cancelled with the bridge, so the answer that
        // dismissing it gives is dropped.
        val dialogs = shownDialogs.toList()
        shownDialogs.clear()
        dialogs.forEach { it.dismiss() }
    }

    /**
     * Shows the dialog that [build] makes and returns the user's answer. A dialog that is dismissed without one, for
     * example by code or with its activity, answers as the back button does: cancelled.
     */
    private suspend fun showAndAwaitAnswer(build: (Dialog.OnResultListener) -> AlertDialog): Answer = suspendCoroutine { continuation ->
        val answer = ResumeOnce(continuation)
        val dialog = build { value, didCancel, inputValue -> answer.resume(Answer(value, didCancel, inputValue)) }
        dialog.setOnDismissListener {
            shownDialogs.remove(dialog)
            answer.resume(Answer.DISMISSED)
        }
        // What showing throws rejects the call: nothing has resumed the continuation yet
        dialog.show()
        shownDialogs.add(dialog)
    }

    private class Answer(val value: Boolean, val didCancel: Boolean, val inputValue: String?) {
        companion object {
            // What the back button answers
            val DISMISSED = Answer(value = false, didCancel = true, inputValue = null)
        }
    }
}
