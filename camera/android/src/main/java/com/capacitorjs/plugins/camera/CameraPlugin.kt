package com.capacitorjs.plugins.camera

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultCallback
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.getcapacitor.FileUtils
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PermissionState
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicInteger

/**
 * The Camera plugin makes it easy to take a photo or have the user select a photo
 * from their albums.
 *
 * On Android, this plugin sends an intent that opens the stock Camera app.
 *
 * Adapted from https://developer.android.com/training/camera/photobasics.html
 */
@CapacitorPlugin(
    name = "Camera",
    permissions = [
        Permission(strings = [Manifest.permission.CAMERA], alias = CameraPlugin.CAMERA),
        Permission(strings = [], alias = CameraPlugin.PHOTOS),
        // Storage permissions do not apply on Android 13 and later. The aliases stay because they are part of the
        // permission status that goes out to JavaScript.
        Permission(
            strings = [Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE],
            alias = CameraPlugin.SAVE_GALLERY
        ),
        // Placeholder: SAVE_GALLERY is reported and requested through this alias so that the end user does not
        // need to know about it.
        Permission(strings = [Manifest.permission.READ_EXTERNAL_STORAGE], alias = CameraPlugin.READ_EXTERNAL_STORAGE)
    ]
)
public class CameraPlugin : Plugin() {
    // The state of the active call. The plugin thread, the main thread and the executor take turns with it, one call
    // at a time, so each field is volatile.
    @Volatile private var imageFileSavePath: String? = null

    @Volatile private var imageEditedFileSavePath: String? = null

    @Volatile private var imageFileUri: Uri? = null

    @Volatile private var imagePickedContentUri: Uri? = null

    @Volatile private var isEdited = false

    @Volatile private var isSaved = false

    @Volatile private var pickMultipleMedia: ActivityResultLauncher<PickVisualMediaRequest>? = null

    @Volatile private var pickMedia: ActivityResultLauncher<PickVisualMediaRequest>? = null

    @Volatile private var settings = CameraSettings()

    // The getPhoto or pickImages call the state above belongs to. As on iOS, another one made while it is in progress
    // is rejected. Every path that settles it goes through resolveActiveCall or rejectActiveCall, which end it.
    private val activeCall = ActiveCall<PluginCall>()

    private val nextLocalRequestCode = AtomicInteger()

    // Decodes and encodes the images. Activity results arrive on the main thread, which must not do this work.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    @PluginMethod
    public fun getPhoto(call: PluginCall) {
        withActiveCall(call) {
            resetCallState(call)
            doShow(call)
        }
    }

    @PluginMethod
    public fun pickImages(call: PluginCall) {
        withActiveCall(call) {
            resetCallState(call)
            openPhotos(call, true)
        }
    }

    /**
     * Runs [block] with [call] as the active call: it becomes the active call when none is in progress, or already is
     * (a result arriving for it, or a call Android restored after ending the app while the camera was in front). When
     * another call is in progress, [call] is rejected instead, since the state belongs to that call.
     *
     * The bridge rejects a call with what a plugin method or an activity or permission callback throws, without going
     * through [rejectActiveCall], so this ends [call] when [block] throws: otherwise no later call could begin.
     */
    private inline fun withActiveCall(call: PluginCall, block: () -> Unit) {
        if (!activeCall.begin(call)) {
            call.reject(CALL_IN_PROGRESS_ERROR)
            return
        }
        try {
            block()
        } catch (t: Throwable) {
            activeCall.end(call)
            throw t
        }
    }

    /**
     * Makes the state [call]'s: its settings, and nothing the call before it left behind.
     */
    private fun resetCallState(call: PluginCall) {
        settings = getSettings(call)
        isEdited = false
        isSaved = false
        imageFileSavePath = null
        imageEditedFileSavePath = null
        imageFileUri = null
        imagePickedContentUri = null
    }

    /**
     * Ends [call] and resolves it. It ends first, so that the next getPhoto or pickImages call the JavaScript caller
     * makes once this one settles can begin.
     */
    private fun resolveActiveCall(call: PluginCall, data: JSObject) {
        activeCall.end(call)
        call.resolve(data)
    }

    /**
     * Ends [call] and rejects it, as [resolveActiveCall] does.
     */
    private fun rejectActiveCall(call: PluginCall, message: String, ex: Exception? = null) {
        activeCall.end(call)
        call.reject(message, ex = ex)
    }

    @PluginMethod
    public fun pickLimitedLibraryPhotos(call: PluginCall) {
        call.unimplemented("not supported on android")
    }

    @PluginMethod
    public fun getLimitedLibraryPhotos(call: PluginCall) {
        call.unimplemented("not supported on android")
    }

    private fun doShow(call: PluginCall) {
        when (settings.source) {
            CameraSource.CAMERA -> showCamera(call)
            CameraSource.PHOTOS -> showPhotos(call)
            else -> showPrompt(call)
        }
    }

    private fun showPrompt(call: PluginCall) {
        // We have all necessary permissions, open the camera
        val options = listOf(call.getString("promptLabelPhoto", "From Photos"), call.getString("promptLabelPicture", "Take Picture"))

        val fragment = CameraBottomSheetDialogFragment()
        fragment.title = call.getString("promptLabelHeader", "Photo")
        fragment.setOptions(
            options,
            { index ->
                if (index == 0) {
                    settings.source = CameraSource.PHOTOS
                    openPhotos(call)
                } else if (index == 1) {
                    settings.source = CameraSource.CAMERA
                    openCamera(call)
                }
            },
            { rejectActiveCall(call, USER_CANCELLED) }
        )
        // Plugin methods run on the bridge thread, and fragments are shown from the main thread
        bridge.executeOnMainThread {
            try {
                fragment.show(activity.supportFragmentManager, "capacitorModalsActionSheet")
            } catch (ex: IllegalStateException) {
                // The activity has already saved its state
                rejectActiveCall(call, PROMPT_ERROR, ex)
            }
        }
    }

    private fun showCamera(call: PluginCall) {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            rejectActiveCall(call, NO_CAMERA_ERROR)
            return
        }
        openCamera(call)
    }

    private fun showPhotos(call: PluginCall) {
        openPhotos(call)
    }

    private fun checkCameraPermissions(call: PluginCall): Boolean {
        // if the manifest does not contain the camera permissions key, we don't need to ask the user
        val hasCameraPerms = !isPermissionDeclared(CAMERA) || getPermissionState(CAMERA) == PermissionState.GRANTED

        // Saving to the gallery goes through MediaStore and needs no permission
        if (!hasCameraPerms) {
            requestPermissionForAlias(CAMERA, call, "cameraPermissionsCallback")
            return false
        }
        return true
    }

    /**
     * Completes the plugin call after a camera permission request
     *
     * @see getPhoto
     * @param call the plugin call
     */
    @PermissionCallback
    private fun cameraPermissionsCallback(call: PluginCall) {
        if (!activeCall.isActive(call)) {
            // The bridge hands a plugin's permission results to its waiting calls in the order they asked, whichever
            // prompt a result is for. When requestPermissions asks while the active call waits for the camera prompt,
            // the two calls can swap results: this is then the requestPermissions call, and checkPermissions, its
            // callback, answers and ends the active call. Answer this one as checkPermissions would instead of taking
            // a picture for it.
            checkPermissions(call)
            return
        }
        withActiveCall(call) {
            if (call.methodName == "pickImages") {
                openPhotos(call, true)
            } else {
                if (settings.source == CameraSource.CAMERA && getPermissionState(CAMERA) != PermissionState.GRANTED) {
                    Logger.debug(logTag, "User denied camera permission: " + getPermissionState(CAMERA).toString())
                    rejectActiveCall(call, PERMISSION_DENIED_ERROR_CAMERA)
                    return
                }
                doShow(call)
            }
        }
    }

    override fun requestPermissionForAliases(aliases: Array<String>, call: PluginCall, callbackName: String) {
        for (i in aliases.indices) {
            if (aliases[i] == SAVE_GALLERY) {
                aliases[i] = READ_EXTERNAL_STORAGE
            }
        }
        super.requestPermissionForAliases(aliases, call, callbackName)
    }

    private fun getSettings(call: PluginCall): CameraSettings {
        val settings = CameraSettings()
        settings.resultType = getResultType(call.getString("resultType"))
        settings.saveToGallery = call.getBoolean("saveToGallery") ?: CameraSettings.DEFAULT_SAVE_IMAGE_TO_GALLERY
        settings.allowEditing = call.getBoolean("allowEditing") ?: false
        settings.quality = call.getInt("quality") ?: CameraSettings.DEFAULT_QUALITY
        settings.width = call.getInt("width") ?: 0
        settings.height = call.getInt("height") ?: 0
        settings.shouldResize = settings.width > 0 || settings.height > 0
        settings.shouldCorrectOrientation = call.getBoolean("correctOrientation") ?: CameraSettings.DEFAULT_CORRECT_ORIENTATION
        settings.source =
            try {
                CameraSource.valueOf(call.getString("source") ?: CameraSource.PROMPT.source)
            } catch (ex: IllegalArgumentException) {
                CameraSource.PROMPT
            }
        return settings
    }

    private fun getResultType(resultType: String?): CameraResultType? {
        if (resultType == null) {
            return null
        }
        return try {
            CameraResultType.valueOf(resultType.uppercase(Locale.ROOT))
        } catch (ex: IllegalArgumentException) {
            Logger.debug(logTag, "Invalid result type \"$resultType\", defaulting to base64")
            CameraResultType.BASE64
        }
    }

    public fun openCamera(call: PluginCall) {
        if (!checkCameraPermissions(call)) {
            return
        }
        val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        if (takePictureIntent.resolveActivity(context.packageManager) == null) {
            rejectActiveCall(call, NO_CAMERA_ACTIVITY_ERROR)
            return
        }
        // If we will be saving the photo, send the target file along
        try {
            val photoFile = CameraUtils.createImageFile(activity)
            imageFileSavePath = photoFile.absolutePath
            // TODO: Verify provider config exists
            imageFileUri = FileProvider.getUriForFile(activity, "$appId.fileprovider", photoFile)
            takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT, imageFileUri)
        } catch (ex: Exception) {
            rejectActiveCall(call, IMAGE_FILE_SAVE_ERROR, ex)
            return
        }

        startActivityForResult(call, takePictureIntent, "processCameraImage")
    }

    public fun openPhotos(call: PluginCall) {
        openPhotos(call, false)
    }

    private fun <I, O> registerActivityResultLauncher(
        contract: ActivityResultContract<I, O>,
        callback: ActivityResultCallback<O>
    ): ActivityResultLauncher<I> {
        val key = "cap_activity_rq#" + nextLocalRequestCode.getAndIncrement()
        val fragment = bridge.fragment
        if (fragment != null) {
            val host = fragment.host
            if (host is ActivityResultRegistryOwner) {
                return host.activityResultRegistry.register(key, contract, callback)
            }
            return fragment.requireActivity().activityResultRegistry.register(key, contract, callback)
        }
        return bridge.activity.activityResultRegistry.register(key, contract, callback)
    }

    private fun getContractForCall(call: PluginCall): ActivityResultContract<PickVisualMediaRequest, List<Uri>> {
        val limit = call.getInt("limit") ?: 0
        return if (limit > 1) {
            ActivityResultContracts.PickMultipleVisualMedia(limit)
        } else {
            ActivityResultContracts.PickMultipleVisualMedia()
        }
    }

    private fun openPhotos(call: PluginCall, multiple: Boolean) {
        val request = PickVisualMediaRequest.Builder().setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly).build()
        try {
            // Each launcher unregisters before its call settles: from then on the field may hold the next call's. A
            // result for a call that has settled already is dropped, since the state may be the next call's too.
            if (multiple) {
                val launcher =
                    registerActivityResultLauncher(getContractForCall(call)) { uris ->
                        pickMultipleMedia?.unregister()
                        if (!activeCall.isActive(call)) {
                            return@registerActivityResultLauncher
                        }
                        if (uris.isNotEmpty()) {
                            processInBackground(call) { processPickedImages(uris, call) }
                        } else {
                            rejectActiveCall(call, USER_CANCELLED)
                        }
                    }
                pickMultipleMedia = launcher
                launcher.launch(request)
            } else {
                val launcher =
                    registerActivityResultLauncher(ActivityResultContracts.PickVisualMedia()) { uri ->
                        pickMedia?.unregister()
                        if (!activeCall.isActive(call)) {
                            return@registerActivityResultLauncher
                        }
                        if (uri != null) {
                            imagePickedContentUri = uri
                            processInBackground(call) { processPickedImage(uri, call) }
                        } else {
                            rejectActiveCall(call, USER_CANCELLED)
                        }
                    }
                pickMedia = launcher
                launcher.launch(request)
            }
        } catch (ex: ActivityNotFoundException) {
            rejectActiveCall(call, NO_PHOTO_ACTIVITY_ERROR)
        }
    }

    private fun processPickedImages(uris: List<Uri>, call: PluginCall) {
        val ret = JSObject()
        val photos = JSArray()
        for (imageUri in uris) {
            try {
                val processResult = processPickedImages(imageUri)
                val error = processResult.getString("error")
                if (!error.isNullOrEmpty()) {
                    rejectActiveCall(call, error)
                    return
                }
                photos.put(processResult)
            } catch (ex: SecurityException) {
                // Rejecting and going on to resolve settled the call twice
                rejectActiveCall(call, "SecurityException", ex)
                return
            }
        }
        ret.put("photos", photos)
        resolveActiveCall(call, ret)
    }

    /**
     * Runs [work] on the plugin's executor, rejecting the call with what it throws: nothing else would settle it.
     */
    private fun processInBackground(call: PluginCall, work: () -> Unit) {
        try {
            executor.execute {
                try {
                    work()
                } catch (ex: Exception) {
                    rejectActiveCall(call, UNABLE_TO_PROCESS_IMAGE, ex)
                }
            }
        } catch (ex: RejectedExecutionException) {
            // The plugin has been destroyed
            rejectActiveCall(call, UNABLE_TO_PROCESS_IMAGE, ex)
        }
    }

    @ActivityCallback
    public fun processCameraImage(call: PluginCall, @Suppress("UNUSED_PARAMETER") result: ActivityResult?) {
        withActiveCall(call) {
            processInBackground(call) { processCapturedImage(call) }
        }
    }

    private fun processCapturedImage(call: PluginCall) {
        settings = getSettings(call)
        val savePath = imageFileSavePath
        if (savePath == null) {
            rejectActiveCall(call, IMAGE_PROCESS_NO_FILE_ERROR)
            return
        }
        // Load the image as a Bitmap
        val contentUri = Uri.fromFile(File(savePath))
        val bitmap = BitmapFactory.decodeFile(savePath, BitmapFactory.Options())

        if (bitmap == null) {
            rejectActiveCall(call, USER_CANCELLED)
            return
        }

        returnResult(call, bitmap, contentUri)
    }

    public fun processPickedImage(call: PluginCall, result: ActivityResult?) {
        settings = getSettings(call)
        val u = result?.data?.data
        if (u == null) {
            rejectActiveCall(call, USER_CANCELLED)
            return
        }

        imagePickedContentUri = u

        processPickedImage(u, call)
    }

    private fun processPickedImage(imageUri: Uri, call: PluginCall) {
        var imageStream: InputStream? = null

        try {
            imageStream = context.contentResolver.openInputStream(imageUri)
            val bitmap = BitmapFactory.decodeStream(imageStream)

            if (bitmap == null) {
                rejectActiveCall(call, "Unable to process bitmap")
                return
            }

            returnResult(call, bitmap, imageUri)
        } catch (err: OutOfMemoryError) {
            rejectActiveCall(call, "Out of memory")
        } catch (ex: FileNotFoundException) {
            rejectActiveCall(call, "No such image found", ex)
        } finally {
            closeImageStream(imageStream)
        }
    }

    private fun processPickedImages(imageUri: Uri): JSObject {
        var imageStream: InputStream? = null
        val ret = JSObject()
        try {
            imageStream = context.contentResolver.openInputStream(imageUri)
            var bitmap = BitmapFactory.decodeStream(imageStream)

            if (bitmap == null) {
                ret.put("error", "Unable to process bitmap")
                return ret
            }

            val exif = ImageUtils.getExifData(context, bitmap, imageUri)
            try {
                bitmap = prepareBitmap(bitmap, imageUri, exif)
            } catch (e: IOException) {
                ret.put("error", UNABLE_TO_PROCESS_IMAGE)
                return ret
            }
            // Compress the final image and prepare for output to client
            val bitmapOutputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, settings.quality, bitmapOutputStream)

            val newUri = getTempImage(imageUri, bitmapOutputStream)
            if (newUri != null) {
                exif.copyExif(newUri.path)
                ret.put("format", "jpeg")
                ret.put("exif", exif.toJson())
                ret.put("path", newUri.toString())
                ret.put("webPath", FileUtils.getPortablePath(context, bridge.localUrl, newUri))
            } else {
                ret.put("error", UNABLE_TO_PROCESS_IMAGE)
            }
            return ret
        } catch (err: OutOfMemoryError) {
            ret.put("error", "Out of memory")
        } catch (ex: FileNotFoundException) {
            ret.put("error", "No such image found")
            Logger.error(logTag, "No such image found", ex)
        } finally {
            closeImageStream(imageStream)
        }
        return ret
    }

    private fun closeImageStream(imageStream: InputStream?) {
        try {
            imageStream?.close()
        } catch (e: IOException) {
            Logger.error(logTag, UNABLE_TO_PROCESS_IMAGE, e)
        }
    }

    @ActivityCallback
    private fun processEditedImage(call: PluginCall, result: ActivityResult?) {
        withActiveCall(call) {
            processInBackground(call) {
                isEdited = true
                settings = getSettings(call)
                if (result?.resultCode == Activity.RESULT_CANCELED) {
                    // User cancelled the edit operation, if this file was picked from photos,
                    // process the original picked image, otherwise process it as a camera photo
                    val pickedUri = imagePickedContentUri
                    if (pickedUri != null) {
                        processPickedImage(pickedUri, call)
                    } else {
                        processCapturedImage(call)
                    }
                } else {
                    processPickedImage(call, result)
                }
            }
        }
    }

    /**
     * Save the modified image on the same path,
     * or on a temporary location if it's a content url
     */
    @Throws(IOException::class)
    private fun saveImage(uri: Uri, input: InputStream): Uri {
        var outFile =
            if (uri.scheme == "content") {
                getTempFile(uri)
            } else {
                File(uri.path ?: throw IOException("No path in $uri"))
            }
        try {
            writePhoto(outFile, input)
        } catch (ex: FileNotFoundException) {
            // Some gallery apps return read only file url, create a temporary file for modifications
            outFile = getTempFile(uri)
            writePhoto(outFile, input)
        }
        return Uri.fromFile(outFile)
    }

    @Throws(IOException::class)
    private fun writePhoto(outFile: File, input: InputStream) {
        FileOutputStream(outFile).use { fos ->
            val buffer = ByteArray(1024)
            while (true) {
                val len = input.read(buffer)
                if (len == -1) {
                    break
                }
                fos.write(buffer, 0, len)
            }
        }
    }

    @Throws(IOException::class)
    private fun getTempFile(uri: Uri): File {
        var filename = Uri.parse(Uri.decode(uri.toString())).lastPathSegment ?: throw IOException("No file name in $uri")
        if (!filename.contains(".jpg") && !filename.contains(".jpeg")) {
            filename += "." + Date().time + ".jpeg"
        }
        return File(context.cacheDir, filename)
    }

    /**
     * After processing the image, return the final result back to the caller.
     */
    private fun returnResult(call: PluginCall, originalBitmap: Bitmap, u: Uri) {
        val exif = ImageUtils.getExifData(context, originalBitmap, u)
        val bitmap =
            try {
                prepareBitmap(originalBitmap, u, exif)
            } catch (e: IOException) {
                rejectActiveCall(call, UNABLE_TO_PROCESS_IMAGE)
                return
            }
        // Compress the final image and prepare for output to client
        val bitmapOutputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, settings.quality, bitmapOutputStream)

        if (settings.allowEditing && !isEdited) {
            editImage(call, u, bitmapOutputStream)
            return
        }

        val saveToGallery = call.getBoolean("saveToGallery") ?: CameraSettings.DEFAULT_SAVE_IMAGE_TO_GALLERY
        val fileToSavePath = imageEditedFileSavePath ?: imageFileSavePath
        if (saveToGallery && fileToSavePath != null) {
            isSaved = true
            try {
                saveToGallery(File(fileToSavePath), bitmap)
            } catch (e: IOException) {
                isSaved = false
                Logger.error(logTag, IMAGE_GALLERY_SAVE_ERROR, e)
            }
        }

        // Clear stored paths and images before the result goes out: settling ends the call, and the next call's
        // paths would be the ones cleared after that. The result itself is built from u and bitmapOutputStream.
        if (settings.resultType != CameraResultType.URI) {
            deleteImageFile()
        }
        imageFileSavePath = null
        imageFileUri = null
        imagePickedContentUri = null
        imageEditedFileSavePath = null

        when (settings.resultType) {
            CameraResultType.BASE64 -> returnBase64(call, exif, bitmapOutputStream)
            CameraResultType.URI -> returnFileURI(call, exif, u, bitmapOutputStream)
            CameraResultType.DATAURL -> returnDataUrl(call, exif, bitmapOutputStream)
            null -> rejectActiveCall(call, INVALID_RESULT_TYPE_ERROR)
        }
    }

    @Throws(IOException::class)
    private fun saveToGallery(fileToSave: File, bitmap: Bitmap) {
        val resolver = context.contentResolver
        val values = ContentValues()
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileToSave.name)
        values.put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DCIM)

        val uri =
            resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Failed to create new MediaStore record.")

        val stream = resolver.openOutputStream(uri) ?: throw IOException("Failed to open output stream.")

        val inserted = stream.use { bitmap.compress(Bitmap.CompressFormat.JPEG, settings.quality, it) }

        if (!inserted) {
            isSaved = false
        }
    }

    private fun deleteImageFile() {
        val savePath = imageFileSavePath
        if (savePath != null && !settings.saveToGallery) {
            val photoFile = File(savePath)
            if (photoFile.exists()) {
                photoFile.delete()
            }
        }
    }

    private fun returnFileURI(call: PluginCall, exif: ExifWrapper, u: Uri, bitmapOutputStream: ByteArrayOutputStream) {
        val newUri = getTempImage(u, bitmapOutputStream)
        if (newUri != null) {
            exif.copyExif(newUri.path)
            val ret = JSObject()
            ret.put("format", "jpeg")
            ret.put("exif", exif.toJson())
            ret.put("path", newUri.toString())
            ret.put("webPath", FileUtils.getPortablePath(context, bridge.localUrl, newUri))
            ret.put("saved", isSaved)
            resolveActiveCall(call, ret)
        } else {
            rejectActiveCall(call, UNABLE_TO_PROCESS_IMAGE)
        }
    }

    private fun getTempImage(u: Uri, bitmapOutputStream: ByteArrayOutputStream): Uri? = try {
        saveImage(u, ByteArrayInputStream(bitmapOutputStream.toByteArray()))
    } catch (ex: IOException) {
        null
    }

    /**
     * Apply our standard processing of the bitmap, returning a new one and
     * recycling the old one in the process
     */
    @Throws(IOException::class)
    private fun prepareBitmap(original: Bitmap, imageUri: Uri, exif: ExifWrapper): Bitmap {
        var bitmap = original
        if (settings.shouldCorrectOrientation) {
            bitmap = replaceBitmap(bitmap, ImageUtils.correctOrientation(context, bitmap, imageUri, exif))
        }

        if (settings.shouldResize) {
            bitmap = replaceBitmap(bitmap, ImageUtils.resize(bitmap, settings.width, settings.height))
        }

        return bitmap
    }

    private fun replaceBitmap(bitmap: Bitmap, newBitmap: Bitmap): Bitmap {
        if (bitmap != newBitmap) {
            bitmap.recycle()
        }
        return newBitmap
    }

    private fun returnDataUrl(call: PluginCall, exif: ExifWrapper, bitmapOutputStream: ByteArrayOutputStream) {
        val encoded = Base64.encodeToString(bitmapOutputStream.toByteArray(), Base64.NO_WRAP)

        val data = JSObject()
        data.put("format", "jpeg")
        data.put("dataUrl", "data:image/jpeg;base64,$encoded")
        data.put("exif", exif.toJson())
        resolveActiveCall(call, data)
    }

    private fun returnBase64(call: PluginCall, exif: ExifWrapper, bitmapOutputStream: ByteArrayOutputStream) {
        val encoded = Base64.encodeToString(bitmapOutputStream.toByteArray(), Base64.NO_WRAP)

        val data = JSObject()
        data.put("format", "jpeg")
        data.put("base64String", encoded)
        data.put("exif", exif.toJson())
        resolveActiveCall(call, data)
    }

    /**
     * Also the permission callback of requestPermissions, which the bridge can hand the active call instead of the
     * requestPermissions call (see [cameraPermissionsCallback]). Ending the call it answers keeps that call from
     * blocking the next one; any other call is not the active call, and ending it changes nothing.
     */
    @PluginMethod
    override fun checkPermissions(pluginCall: PluginCall) {
        activeCall.end(pluginCall)
        super.checkPermissions(pluginCall)
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        // If the camera permission is defined in the manifest, then we have to prompt the user
        // or else we will get a security exception when trying to present the camera. If, however,
        // it is not defined in the manifest then we don't need to prompt and it will just work.
        if (isPermissionDeclared(CAMERA)) {
            // just request normally
            super.requestPermissions(call)
        } else {
            // Storage permissions do not apply on Android 13 and later, so there is nothing to ask for
            checkPermissions(call)
        }
    }

    /**
     * The permission states as this plugin reports them, which is what `checkPermissions` and
     * `getPermissionState` read.
     */
    override val permissionStates: Map<String, PermissionState>
        get() {
            val states = HashMap(super.permissionStates)

            // If Camera is not in the manifest and therefore not required, say the permission is granted
            if (!isPermissionDeclared(CAMERA)) {
                states[CAMERA] = PermissionState.GRANTED
            }

            if (states.containsKey(PHOTOS)) {
                states[PHOTOS] = PermissionState.GRANTED
            }

            // The SAVE_GALLERY state matches the READ_EXTERNAL_STORAGE state.
            states[READ_EXTERNAL_STORAGE]?.let { states[SAVE_GALLERY] = it }

            return states
        }

    private fun editImage(call: PluginCall, uri: Uri, bitmapOutputStream: ByteArrayOutputStream) {
        try {
            val editIntent = getTempImage(uri, bitmapOutputStream)?.let { createEditIntent(it) }
            if (editIntent != null) {
                startActivityForResult(call, editIntent, "processEditedImage")
            } else {
                rejectActiveCall(call, IMAGE_EDIT_ERROR)
            }
        } catch (ex: Exception) {
            rejectActiveCall(call, IMAGE_EDIT_ERROR, ex)
        }
    }

    private fun createEditIntent(origPhotoUri: Uri): Intent? {
        try {
            val editFile = File(origPhotoUri.path ?: return null)
            val editUri = FileProvider.getUriForFile(activity, context.packageName + ".fileprovider", editFile)
            val editIntent = Intent(Intent.ACTION_EDIT)
            editIntent.setDataAndType(editUri, "image/*")
            imageEditedFileSavePath = editFile.absolutePath
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            editIntent.addFlags(flags)
            editIntent.putExtra(MediaStore.EXTRA_OUTPUT, editUri)

            val resInfoList =
                context.packageManager.queryIntentActivities(
                    editIntent,
                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                )

            for (resolveInfo in resInfoList) {
                context.grantUriPermission(resolveInfo.activityInfo.packageName, editUri, flags)
            }
            return editIntent
        } catch (ex: Exception) {
            return null
        }
    }

    override fun saveInstanceState(): Bundle? {
        val bundle = super.saveInstanceState()
        bundle?.putString("cameraImageFileSavePath", imageFileSavePath)
        return bundle
    }

    override fun restoreState(state: Bundle?) {
        val storedImageFileSavePath = state?.getString("cameraImageFileSavePath")
        if (storedImageFileSavePath != null) {
            imageFileSavePath = storedImageFileSavePath
        }
    }

    /**
     * Unregister activity result launches to prevent leaks.
     */
    override fun handleOnDestroy() {
        pickMedia?.unregister()
        pickMultipleMedia?.unregister()
        // The results the active call waits for can no longer arrive
        activeCall.clear()
        executor.shutdown()
    }

    internal companion object {
        // Permission alias constants
        const val CAMERA = "camera"
        const val PHOTOS = "photos"
        const val SAVE_GALLERY = "saveGallery"
        const val READ_EXTERNAL_STORAGE = "readExternalStorage"

        // Message constants
        private const val INVALID_RESULT_TYPE_ERROR = "Invalid resultType option"
        private const val PERMISSION_DENIED_ERROR_CAMERA = "User denied access to camera"
        private const val NO_CAMERA_ERROR = "Device doesn't have a camera available"
        private const val NO_CAMERA_ACTIVITY_ERROR = "Unable to resolve camera activity"
        private const val NO_PHOTO_ACTIVITY_ERROR = "Unable to resolve photo activity"
        private const val IMAGE_FILE_SAVE_ERROR = "Unable to create photo on disk"
        private const val IMAGE_PROCESS_NO_FILE_ERROR = "Unable to process image, file not found on disk"
        private const val UNABLE_TO_PROCESS_IMAGE = "Unable to process image"
        private const val IMAGE_EDIT_ERROR = "Unable to edit image"
        private const val PROMPT_ERROR = "Unable to show the photo prompt"
        private const val IMAGE_GALLERY_SAVE_ERROR = "Unable to save the image in the gallery"
        private const val USER_CANCELLED = "User cancelled photos app"

        // The same message as on iOS
        private const val CALL_IN_PROGRESS_ERROR = "Another getPhoto or pickImages call is in progress"
    }
}
