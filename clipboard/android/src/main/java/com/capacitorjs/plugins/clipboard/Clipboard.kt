package com.capacitorjs.plugins.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import com.getcapacitor.Logger

public class Clipboard(private val context: Context) {
    private val clipboard: ClipboardManager? = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager?

    /**
     * Writes provided content to the clipboard.
     *
     * @param label User-visible label for the clip data.
     * @param content The content to be written to the clipboard.
     * @return A response indicating the success status of the write request.
     */
    public fun write(label: String?, content: String?): ClipboardWriteResponse {
        val data: ClipData? = ClipData.newPlainText(label, content)

        return if (data != null && clipboard != null) {
            try {
                clipboard.setPrimaryClip(data)
                ClipboardWriteResponse(true)
            } catch (e: Exception) {
                Logger.error(TAG, e)
                ClipboardWriteResponse(false, "Writing to the clipboard failed")
            }
        } else if (clipboard == null) {
            ClipboardWriteResponse(false, "Problem getting a reference to the system clipboard")
        } else {
            ClipboardWriteResponse(false, "Problem formatting data")
        }
    }

    /**
     * Reads data from the clipboard.
     * @return Data from the clipboard or null if no reference to the system clipboard.
     */
    public fun read(): ClipboardData? {
        if (clipboard == null) {
            return null
        }

        var value: String? = null
        if (clipboard.hasPrimaryClip()) {
            val item = clipboard.primaryClip?.getItemAt(0)
            if (clipboard.primaryClipDescription?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true) {
                Logger.debug(TAG, "Got plaintxt")
                value = item?.text?.toString()
            } else {
                Logger.debug(TAG, "Not plaintext!")
                value = item?.coerceToText(context)?.toString()
            }
        }

        var type = "text/plain"
        if (value != null && value.startsWith("data:")) {
            // Same tokens as Java's String.split, which drops trailing empty strings: a bare "data:" has no type and throws
            type = value.javaSplit(';')[0].javaSplit(':')[1]
        }

        return ClipboardData(value, type)
    }

    private fun String.javaSplit(delimiter: Char): List<String> = split(delimiter).dropLastWhile { it.isEmpty() }

    private companion object {
        const val TAG = "Clipboard"
    }
}
