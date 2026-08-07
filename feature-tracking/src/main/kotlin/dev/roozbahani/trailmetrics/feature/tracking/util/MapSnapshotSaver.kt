package dev.roozbahani.trailmetrics.feature.tracking.util

import android.content.Context
import android.graphics.Bitmap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

internal fun saveSnapshotToFile(context: Context, bitmap: Bitmap): String? =
    try {
        val fileName = "activity_${System.currentTimeMillis()}.png"
        val file = File(context.filesDir, fileName)

        val scaledBitmap = if (bitmap.width > SNAPSHOT_MAX_WIDTH) {
            val scaledHeight = (bitmap.height * SNAPSHOT_MAX_WIDTH / bitmap.width)
            Bitmap.createScaledBitmap(
                bitmap,
                SNAPSHOT_MAX_WIDTH,
                scaledHeight,
                true
            )
        } else {
            bitmap
        }

        FileOutputStream(file).use { out ->
            scaledBitmap.compress(
                Bitmap.CompressFormat.PNG,
                PNG_QUALITY_IGNORED,
                out
            )
        }
        file.absolutePath
    } catch (ex: IOException) {
        null
    }

private const val SNAPSHOT_MAX_WIDTH = 600
private const val PNG_QUALITY_IGNORED = 100 // PNG is lossless; this value is ignored by the codec
