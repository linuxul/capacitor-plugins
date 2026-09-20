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
import java.util.concurrent.Executors
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
    private var imageFileSavePath: String? = null
    private var imageEditedFileSavePath: String? = null
    private var imageFileUri: Uri? = null
    private var imagePickedContentUri: Uri? = null
    private var isEdited = false
    private var isSaved = false
    private var pickMultipleMedia: ActivityResultLauncher<PickVisualMediaRequest>? = null
    private var pickMedia: ActivityResultLauncher<PickVisualMediaRequest>? = null

    private val nextLocalRequestCode = AtomicInteger()

    private var settings = CameraSettings()

    @PluginMethod
    public fun getPhoto(call: PluginCall) {
        isEdited = false
        settings = getSettings(call)
        doShow(call)
    }

    @PluginMethod
    public fun pickImages(call: PluginCall) {
        settings = getSettings(call)
        openPhotos(call, true)
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
            { call.reject(USER_CANCELLED) }
        )
        fragment.show(activity.supportFragmentManager, "capacitorModalsActionSheet")
    }

    private fun showCamera(call: PluginCall) {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            call.reject(NO_CAMERA_ERROR)
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
        if (call.methodName == "pickImages") {
            openPhotos(call, true)
        } else {
            if (settings.source == CameraSource.CAMERA && getPermissionState(CAMERA) != PermissionState.GRANTED) {
                Logger.debug(logTag, "User denied camera permission: " + getPermissionState(CAMERA).toString())
                call.reject(PERMISSION_DENIED_ERROR_CAMERA)
                return
            }
            doShow(call)
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
            call.reject(NO_CAMERA_ACTIVITY_ERROR)
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
            call.reject(IMAGE_FILE_SAVE_ERROR, ex = ex)
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
            if (multiple) {
                val launcher =
                    registerActivityResultLauncher(getContractForCall(call)) { uris ->
                        if (uris.isNotEmpty()) {
                            Executors.newSingleThreadExecutor().execute { processPickedImages(uris, call) }
                        } else {
                            call.reject(USER_CANCELLED)
                        }
                        pickMultipleMedia?.unregister()
                    }
                pickMultipleMedia = launcher
                launcher.launch(request)
            } else {
                val launcher =
                    registerActivityResultLauncher(ActivityResultContracts.PickVisualMedia()) { uri ->
                        if (uri != null) {
                            imagePickedContentUri = uri
                            processPickedImage(uri, call)
                        } else {
                            call.reject(USER_CANCELLED)
                        }
                        pickMedia?.unregister()
                    }
                pickMedia = launcher
                launcher.launch(request)
            }
        } catch (ex: ActivityNotFoundException) {
            call.reject(NO_PHOTO_ACTIVITY_ERROR)
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
                    call.reject(error)
                    return
                }
                photos.put(processResult)
            } catch (ex: SecurityException) {
                call.reject("SecurityException")
            }
        }
        ret.put("photos", photos)
        call.resolve(ret)
    }

    @ActivityCallback
    public fun processCameraImage(call: PluginCall, @Suppress("UNUSED_PARAMETER") result: ActivityResult?) {
        settings = getSettings(call)
        val savePath = imageFileSavePath
        if (savePath == null) {
            call.reject(IMAGE_PROCESS_NO_FILE_ERROR)
            return
        }
        // Load the image as a Bitmap
        val contentUri = Uri.fromFile(File(savePath))
        val bitmap = BitmapFactory.decodeFile(savePath, BitmapFactory.Options())

        if (bitmap == null) {
            call.reject(USER_CANCELLED)
            return
        }

        returnResult(call, bitmap, contentUri)
    }

    public fun processPickedImage(call: PluginCall, result: ActivityResult?) {
        settings = getSettings(call)
        val u = result?.data?.data
        if (u == null) {
            call.reject(USER_CANCELLED)
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
                call.reject("Unable to process bitmap")
                return
            }

            returnResult(call, bitmap, imageUri)
        } catch (err: OutOfMemoryError) {
            call.reject("Out of memory")
        } catch (ex: FileNotFoundException) {
            call.reject("No such image found", ex = ex)
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
        isEdited = true
        settings = getSettings(call)
        if (result?.resultCode == Activity.RESULT_CANCELED) {
            // User cancelled the edit operation, if this file was picked from photos,
            // process the original picked image, otherwise process it as a camera photo
            val pickedUri = imagePickedContentUri
            if (pickedUri != null) {
                processPickedImage(pickedUri, call)
            } else {
                processCameraImage(call, result)
            }
        } else {
            processPickedImage(call, result)
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
                call.reject(UNABLE_TO_PROCESS_IMAGE)
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

        when (settings.resultType) {
            CameraResultType.BASE64 -> returnBase64(call, exif, bitmapOutputStream)
            CameraResultType.URI -> returnFileURI(call, exif, u, bitmapOutputStream)
            CameraResultType.DATAURL -> returnDataUrl(call, exif, bitmapOutputStream)
            null -> call.reject(INVALID_RESULT_TYPE_ERROR)
        }
        // Result returned, clear stored paths and images
        if (settings.resultType != CameraResultType.URI) {
            deleteImageFile()
        }
        imageFileSavePath = null
        imageFileUri = null
        imagePickedContentUri = null
        imageEditedFileSavePath = null
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
            call.resolve(ret)
        } else {
            call.reject(UNABLE_TO_PROCESS_IMAGE)
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
        call.resolve(data)
    }

    private fun returnBase64(call: PluginCall, exif: ExifWrapper, bitmapOutputStream: ByteArrayOutputStream) {
        val encoded = Base64.encodeToString(bitmapOutputStream.toByteArray(), Base64.NO_WRAP)

        val data = JSObject()
        data.put("format", "jpeg")
        data.put("base64String", encoded)
        data.put("exif", exif.toJson())
        call.resolve(data)
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
                call.reject(IMAGE_EDIT_ERROR)
            }
        } catch (ex: Exception) {
            call.reject(IMAGE_EDIT_ERROR, ex = ex)
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
        private const val IMAGE_GALLERY_SAVE_ERROR = "Unable to save the image in the gallery"
        private const val USER_CANCELLED = "User cancelled photos app"
    }
}
