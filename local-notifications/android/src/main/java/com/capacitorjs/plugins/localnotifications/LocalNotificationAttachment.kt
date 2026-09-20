package com.capacitorjs.plugins.localnotifications

import com.getcapacitor.JSObject
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

public class LocalNotificationAttachment {
    public var id: String? = null
    public var url: String? = null
    public var options: JSONObject? = null

    public companion object {
        public fun getAttachments(notification: JSObject): List<LocalNotificationAttachment> {
            val attachmentsList = ArrayList<LocalNotificationAttachment>()
            val attachments: JSONArray =
                try {
                    notification.getJSONArray("attachments")
                } catch (e: Exception) {
                    null
                } ?: return attachmentsList
            for (i in 0 until attachments.length()) {
                val jsonObject =
                    try {
                        attachments.getJSONObject(i)
                    } catch (e: JSONException) {
                        null
                    } ?: continue
                val jsObject =
                    try {
                        JSObject.fromJSONObject(jsonObject)
                    } catch (e: JSONException) {
                        null
                    }
                val newAttachment = LocalNotificationAttachment()
                newAttachment.id = jsObject?.getString("id")
                newAttachment.url = jsObject?.getString("url")
                try {
                    newAttachment.options = jsObject?.getJSONObject("options")
                } catch (e: JSONException) {
                }
                attachmentsList.add(newAttachment)
            }

            return attachmentsList
        }
    }
}
