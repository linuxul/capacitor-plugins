package com.capacitorjs.plugins.dialog

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Dialog")
public class DialogPlugin : Plugin() {
    @PluginMethod
    public fun alert(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message")
        val buttonTitle = call.getString("buttonTitle", "OK")

        if (message == null) {
            call.reject("Please provide a message for the dialog")
            return
        }

        if (activity.isFinishing) {
            call.reject("App is finishing")
            return
        }

        Dialog.alert(activity, message, title, buttonTitle) { _, _, _ -> call.resolve() }
    }

    @PluginMethod
    public fun confirm(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")

        if (message == null) {
            call.reject("Please provide a message for the dialog")
            return
        }

        if (activity.isFinishing) {
            call.reject("App is finishing")
            return
        }

        Dialog.confirm(activity, message, title, okButtonTitle, cancelButtonTitle) { value, _, _ ->
            val ret = JSObject()
            ret.put("value", value)
            call.resolve(ret)
        }
    }

    @PluginMethod
    public fun prompt(call: PluginCall) {
        val title = call.getString("title")
        val message = call.getString("message")
        val okButtonTitle = call.getString("okButtonTitle", "OK")
        val cancelButtonTitle = call.getString("cancelButtonTitle", "Cancel")
        val inputPlaceholder = call.getString("inputPlaceholder", "")
        val inputText = call.getString("inputText", "")

        if (message == null) {
            call.reject("Please provide a message for the dialog")
            return
        }

        if (activity.isFinishing) {
            call.reject("App is finishing")
            return
        }

        Dialog.prompt(activity, message, title, okButtonTitle, cancelButtonTitle, inputPlaceholder, inputText) { _, didCancel, inputValue ->
            val ret = JSObject()
            ret.put("cancelled", didCancel)
            ret.put("value", inputValue ?: "")
            call.resolve(ret)
        }
    }
}
