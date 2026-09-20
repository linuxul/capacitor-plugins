package com.capacitorjs.plugins.localnotifications

import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import org.json.JSONObject

/**
 * Action types that will be registered for the notifications
 */
public class NotificationAction(public var id: String? = null, public var title: String? = null, private var input: Boolean? = null) {
    public val isInput: Boolean
        get() = input == true

    public fun setInput(input: Boolean?) {
        this.input = input
    }

    public companion object {
        /**
         * @return the actions of every type, or null when a type has no id
         */
        public fun buildTypes(types: JSArray?): Map<String, Array<NotificationAction>>? {
            val actionTypeMap = HashMap<String, Array<NotificationAction>>()
            try {
                val objects = requireNotNull(types).toList<JSONObject>()
                for (obj in objects) {
                    val jsObject = JSObject.fromJSONObject(obj)
                    val actionGroupId = jsObject.getString("id") ?: return null
                    val actions = jsObject.getJSONArray("actions")
                    if (actions != null) {
                        actionTypeMap[actionGroupId] =
                            Array(actions.length()) { i ->
                                val action = JSObject.fromJSONObject(actions.getJSONObject(i))
                                NotificationAction(action.getString("id"), action.getString("title"), action.getBool("input"))
                            }
                    }
                }
            } catch (e: Exception) {
                Logger.error(Logger.tags("LN"), "Error when building action types", e)
            }
            return actionTypeMap
        }
    }
}
