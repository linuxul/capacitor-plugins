package com.capacitorjs.plugins.camera

import android.app.Activity
import android.net.Uri
import android.os.Environment
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date

public object CameraUtils {
    @Throws(IOException::class)
    public fun createImageFileUri(activity: Activity, appId: String): Uri {
        val photoFile = createImageFile(activity)
        return FileProvider.getUriForFile(activity, "$appId.fileprovider", photoFile)
    }

    @Throws(IOException::class)
    public fun createImageFile(activity: Activity): File {
        // Create an image file name
        val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss").format(Date())
        val imageFileName = "JPEG_${timeStamp}_"
        val storageDir = activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES)

        return File.createTempFile(imageFileName, ".jpg", storageDir)
    }
}
