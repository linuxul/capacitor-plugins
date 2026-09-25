package com.capacitorjs.plugins.actionsheet

import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONException
import org.json.JSONObject

@CapacitorPlugin(name = "ActionSheet")
public class ActionSheetPlugin : Plugin() {
    private val implementation = ActionSheet()

    @PluginMethod
    public fun showActions(call: PluginCall) {
        val title = call.getString("title")
        val cancelable = call.getBoolean("cancelable", false) == true
        val options = call.getArray("options")
        if (options == null) {
            call.reject("Must supply options")
            return
        }
        if (activity.isFinishing) {
            call.reject("App is finishing")
            return
        }

        val actionOptions =
            try {
                options.toList<Any>().map { option ->
                    ActionSheetOption(JSObject.fromJSONObject(option as JSONObject).getString("title", ""))
                }
            } catch (ex: JSONException) {
                Logger.error("JSON error processing an option for showActions", ex)
                call.reject("JSON error processing an option for showActions", ex = ex)
                return
            }

        // Plugin methods run on the bridge thread. The sheet is a fragment, so set it up and show it on the main thread.
        bridge.executeOnMainThread {
            implementation.title = title
            implementation.options = actionOptions.toTypedArray()
            implementation.isCancelable = cancelable
            if (cancelable) {
                implementation.onCancelListener = ActionSheet.OnCancelListener { resolve(call, -1) }
            }
            implementation.onSelectedListener =
                ActionSheet.OnSelectListener { index ->
                    resolve(call, index)
                    implementation.dismiss()
                }
            try {
                implementation.show(activity.supportFragmentManager, "capacitorModalsActionSheet")
            } catch (ex: IllegalStateException) {
                // The activity has already saved its state
                call.reject("Unable to show the action sheet", ex = ex)
            }
        }
    }

    private fun resolve(call: PluginCall, selectedIndex: Int) {
        val ret = JSObject()
        ret.put("index", selectedIndex)
        ret.put("canceled", selectedIndex < 0)
        call.resolve(ret)
        implementation.dismiss()
    }
}
