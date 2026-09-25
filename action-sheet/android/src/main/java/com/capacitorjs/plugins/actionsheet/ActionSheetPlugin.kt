package com.capacitorjs.plugins.actionsheet

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginException
import com.getcapacitor.PluginMethod
import com.getcapacitor.PluginThread
import com.getcapacitor.annotation.CapacitorPlugin
import kotlin.coroutines.suspendCoroutine
import org.json.JSONException
import org.json.JSONObject

@CapacitorPlugin(name = "ActionSheet")
public class ActionSheetPlugin : Plugin() {
    // The sheet is a fragment, so it is set up and shown on the main thread. The method returns once an option is
    // picked or the sheet closes without one.
    @PluginMethod(thread = PluginThread.MAIN)
    public suspend fun showActions(call: PluginCall): JSObject {
        val title = call.getString("title")
        val cancelable = call.getBoolean("cancelable", false) == true
        val options = call.getArray("options") ?: throw PluginException("Must supply options")
        if (activity.isFinishing) {
            throw PluginException("App is finishing")
        }

        val actionOptions =
            try {
                options.toList<Any>().map { option ->
                    ActionSheetOption(JSObject.fromJSONObject(option as JSONObject).getString("title", ""))
                }
            } catch (ex: JSONException) {
                throw PluginException("JSON error processing an option for showActions", cause = ex)
            }

        val selectedIndex =
            suspendCoroutine { continuation ->
                val answer = ResumeOnce(continuation)
                // A sheet for each call: while one is on screen, the next call must not take over its listeners
                val sheet = ActionSheet()
                sheet.title = title
                sheet.options = actionOptions.toTypedArray()
                sheet.isCancelable = cancelable
                sheet.onSelectedListener =
                    ActionSheet.OnSelectListener { index ->
                        answer.resume(index)
                        sheet.dismiss()
                    }
                // Cancelling dismisses the sheet as well, so this answers both, and a sheet closed without an answer
                sheet.onDismissListener = { answer.resume(CANCELED_INDEX) }
                try {
                    sheet.show(activity.supportFragmentManager, "capacitorModalsActionSheet")
                } catch (ex: IllegalStateException) {
                    // The activity has already saved its state. Nothing has resumed the continuation yet.
                    throw PluginException("Unable to show the action sheet", cause = ex)
                }
            }

        val ret = JSObject()
        ret.put("index", selectedIndex)
        ret.put("canceled", selectedIndex < 0)
        return ret
    }

    private companion object {
        const val CANCELED_INDEX = -1
    }
}
