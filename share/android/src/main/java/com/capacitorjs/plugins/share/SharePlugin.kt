package com.capacitorjs.plugins.share

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.activity.result.ActivityResult
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.File
import java.util.UUID

@CapacitorPlugin(name = "Share")
public class SharePlugin : Plugin() {
    private var broadcastReceiver: BroadcastReceiver? = null
    private var stopped = false
    private var isPresenting = false
    private var chosenComponent: ComponentName? = null
    private var expectedNonce: String? = null

    override fun load() {
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    // Validate nonce to prevent spoofing from other apps
                    //  Reference: https://github.com/ionic-team/capacitor-plugins/pull/2592
                    val receivedNonce = intent?.getStringExtra(NONCE_EXTRA_KEY)
                    if (receivedNonce == null || receivedNonce != expectedNonce) {
                        // Reject broadcasts that don't have the correct nonce
                        return
                    }

                    val component = intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT, ComponentName::class.java)

                    // Only clear nonce if we successfully got the component data
                    if (component != null) {
                        chosenComponent = component
                        expectedNonce = null
                    }
                }
            }
        broadcastReceiver = receiver
        ContextCompat.registerReceiver(context, receiver, IntentFilter(Intent.EXTRA_CHOSEN_COMPONENT), ContextCompat.RECEIVER_EXPORTED)
    }

    @ActivityCallback
    private fun activityResult(call: PluginCall, result: ActivityResult) {
        if (result.resultCode == Activity.RESULT_CANCELED && !stopped) {
            call.reject("Share canceled")
        } else {
            val callResult = JSObject()
            callResult.put("activityType", chosenComponent?.packageName ?: "")
            call.resolve(callResult)
        }
        isPresenting = false
        expectedNonce = null
    }

    @PluginMethod
    public fun canShare(call: PluginCall) {
        val callResult = JSObject()
        callResult.put("value", true)
        call.resolve(callResult)
    }

    @PluginMethod
    public fun share(call: PluginCall) {
        if (isPresenting) {
            call.reject("Can't share while sharing is in progress")
            return
        }

        val title = call.getString("title", "")
        var text = call.getString("text")
        val url = call.getString("url")
        val files = call.getArray("files")
        val dialogTitle = call.getString("dialogTitle", "Share")

        if (text == null && url == null && (files == null || files.length() == 0)) {
            call.reject("Must provide a URL or Message or files")
            return
        }

        if (url != null && !isFileUrl(url) && !isHttpUrl(url)) {
            call.reject("Unsupported url")
            return
        }

        val intent = Intent(if (files != null && files.length() > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND)

        if (text != null) {
            // If they supplied both fields, concat them
            if (url != null && isHttpUrl(url)) text = "$text $url"
            intent.putExtra(Intent.EXTRA_TEXT, text)
            intent.setTypeAndNormalize("text/plain")
        }

        if (url != null && isHttpUrl(url) && text == null) {
            intent.putExtra(Intent.EXTRA_TEXT, url)
            intent.setTypeAndNormalize("text/plain")
        } else if (url != null && isFileUrl(url)) {
            val filesArray = JSArray()
            filesArray.put(url)
            if (!shareFiles(filesArray, intent, call)) {
                return
            }
        }

        if (title != null) {
            intent.putExtra(Intent.EXTRA_SUBJECT, title)
        }

        if (files != null && files.length() != 0 && !shareFiles(files, intent, call)) {
            return
        }

        // Generate a random nonce to prevent spoofing via exported receiver
        val nonce = UUID.randomUUID().toString()
        expectedNonce = nonce
        val callbackIntent = Intent(Intent.EXTRA_CHOSEN_COMPONENT)
        callbackIntent.putExtra(NONCE_EXTRA_KEY, nonce)

        var flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            flags = flags or PendingIntent.FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT
        }

        // requestCode parameter is not used. Providing 0
        val pi = PendingIntent.getBroadcast(context, 0, callbackIntent, flags)
        val chooser = Intent.createChooser(intent, dialogTitle, pi.intentSender)
        chosenComponent = null
        chooser.addCategory(Intent.CATEGORY_DEFAULT)
        stopped = false
        isPresenting = true
        startActivityForResult(call, chooser, "activityResult")
    }

    /**
     * Adds the files to the intent. Returns false when it rejected the call, which must then not open the chooser.
     */
    private fun shareFiles(files: JSArray, intent: Intent, call: PluginCall): Boolean {
        val fileUris = ArrayList<Uri>()
        try {
            val filesList = files.toList<Any?>()
            for (item in filesList) {
                // Anything that is not a string ends up in the catch block, as it did in Java
                val file = item as String
                if (!isFileUrl(file)) {
                    call.reject("only file urls are supported")
                    return false
                }

                var type = getMimeType(file)
                if (type == null || filesList.size > 1) {
                    type = "*/*"
                }
                intent.setType(type)

                val fileUrl = FileProvider.getUriForFile(
                    activity,
                    context.packageName + ".fileprovider",
                    File(checkNotNull(Uri.parse(file).path))
                )
                fileUris.add(fileUrl)
            }
            if (fileUris.size > 1) {
                intent.putExtra(Intent.EXTRA_STREAM, fileUris)
            } else if (fileUris.size == 1) {
                intent.clipData = ClipData.newRawUri("", fileUris[0])
                intent.putExtra(Intent.EXTRA_STREAM, fileUris[0])
            }
            intent.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            return true
        } catch (ex: Exception) {
            call.reject(ex.localizedMessage, ex = ex)
            return false
        }
    }

    override fun handleOnDestroy() {
        expectedNonce = null
        broadcastReceiver?.let { activity.unregisterReceiver(it) }
    }

    override fun handleOnStop() {
        super.handleOnStop()
        stopped = true
    }

    private fun getMimeType(url: String): String? {
        val extension = MimeTypeMap.getFileExtensionFromUrl(url) ?: return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    private fun isFileUrl(url: String): Boolean = url.startsWith("file:")

    private fun isHttpUrl(url: String): Boolean = url.startsWith("http")

    private companion object {
        const val NONCE_EXTRA_KEY = "_share_nonce"
    }
}
