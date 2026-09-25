package com.capacitorjs.plugins.camera

import android.app.Activity
import android.net.Uri
import android.os.Environment
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

public object CameraUtils {
    @Throws(IOException::class)
    public fun createImageFileUri(activity: Activity, appId: String): Uri {
        val photoFile = createImageFile(activity)
        return FileProvider.getUriForFile(activity, "$appId.fileprovider", photoFile)
    }

    @Throws(IOException::class)
    public fun createImageFile(activity: Activity): File {
        val imageFileName = "JPEG_${fileTimestamp(Date())}_"
        val storageDir = activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES)

        return File.createTempFile(imageFileName, ".jpg", storageDir)
    }

    /**
     * The time in an image file name. The pattern is fixed, so the default locale must not change its digits or its
     * calendar: Thai uses the Buddhist era, and Arabic its own digits.
     */
    internal fun fileTimestamp(date: Date): String = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(date)
}
