package com.capacitorjs.plugins.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.getcapacitor.Logger
import java.io.IOException

public object ImageUtils {
    /**
     * Resize an image to the given max width and max height. Constraint can be put
     * on one dimension, or both. Resize will always preserve aspect ratio.
     *
     * @return a new, scaled Bitmap
     */
    public fun resize(bitmap: Bitmap, desiredMaxWidth: Int, desiredMaxHeight: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        // 0 is treated as 'no restriction'
        val maxHeight = if (desiredMaxHeight == 0) height else desiredMaxHeight
        val maxWidth = if (desiredMaxWidth == 0) width else desiredMaxWidth

        // resize with preserved aspect ratio
        var newWidth = minOf(width, maxWidth).toFloat()
        var newHeight = (height * newWidth) / width

        if (newHeight > maxHeight) {
            // Integer division, as in the Java original
            newWidth = (width * maxHeight / height).toFloat()
            newHeight = maxHeight.toFloat()
        }
        return Bitmap.createScaledBitmap(bitmap, Math.round(newWidth), Math.round(newHeight), false)
    }

    /**
     * Transform an image with the given matrix
     */
    private fun transform(bitmap: Bitmap, matrix: Matrix): Bitmap =
        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)

    /**
     * Correct the orientation of an image by reading its exif information and rotating
     * the appropriate amount for portrait mode
     */
    @Throws(IOException::class)
    public fun correctOrientation(c: Context, bitmap: Bitmap, imageUri: Uri, exif: ExifWrapper): Bitmap {
        val orientation = getOrientation(c, imageUri)
        if (orientation == 0) {
            return bitmap
        }
        val matrix = Matrix()
        matrix.postRotate(orientation.toFloat())
        exif.resetOrientation()
        return transform(bitmap, matrix)
    }

    @Throws(IOException::class)
    private fun getOrientation(c: Context, imageUri: Uri): Int {
        // The Java original passed a null stream on and crashed with a NullPointerException
        val stream = c.contentResolver.openInputStream(imageUri) ?: throw IOException("Unable to open $imageUri")
        return stream.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        }
    }

    @Suppress("UNUSED_PARAMETER")
    public fun getExifData(c: Context, bitmap: Bitmap?, imageUri: Uri): ExifWrapper {
        try {
            // The Java original passed a null stream on and crashed with a NullPointerException
            val stream = c.contentResolver.openInputStream(imageUri) ?: return ExifWrapper(null)
            try {
                return ExifWrapper(ExifInterface(stream))
            } finally {
                try {
                    stream.close()
                } catch (ignored: IOException) {
                }
            }
        } catch (ex: IOException) {
            Logger.error("Error loading exif data from image", ex)
        }
        return ExifWrapper(null)
    }
}
