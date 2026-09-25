package com.capacitorjs.plugins.dialog

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Dialog")
public class DialogPlugin : Plugin() {
    // Dialogs are shown from the main thread
    @PluginMethod(thread = PluginThread.MAIN)
    public fun alert(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val buttonTitle = call.getString("buttonTitle", "OK")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        Dialog.alert(activity, message, title, buttonTitle) { _, _, _ -> call.resolve() }
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun confirm(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        Dialog.confirm(activity, message, title, okButtonTitle, cancelButtonTitle) { value, _, _ ->
            val ret = JSObject()
            ret.put("value", value)
            call.resolve(ret)
        }
    }

    @PluginMethod(thread = PluginThread.MAIN)
    public fun prompt(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message") ?: throw PluginException("Please provide a message for the dialog")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")
        val inputPlaceholder = call.getString("inputPlaceholder", "")
        val inputText = call.getString("inputText", "")

        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        Dialog.prompt(activity, message, title, okButtonTitle, cancelButtonTitle, inputPlaceholder, inputText) { _, didCancel, inputValue ->
            val ret = JSObject()
            ret.put("cancelled", didCancel)
            ret.put("value", inputValue ?: "")
            call.resolve(ret)
        }
    }
}
