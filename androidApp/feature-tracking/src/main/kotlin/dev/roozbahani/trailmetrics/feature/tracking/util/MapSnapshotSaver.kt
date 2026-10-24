package dev.roozbahani.trailmetrics.feature.tracking.util

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Scales [bitmap], PNG-encodes it and writes it to `filesDir` on [ioDispatcher]; returns the file path,
 * or null when the write fails. When the caller is cancelled, a file that was written is deleted and the
 * cancellation propagates, so no path is delivered for a file that no longer exists.
 */
internal suspend fun saveSnapshotToFile(
    context: Context,
    bitmap: Bitmap,
    ioDispatcher: CoroutineDispatcher = Dispatchers.IO
): String? {
    val file = File(context.filesDir, "activity_${System.currentTimeMillis()}.png")
    return try {
        withContext(ioDispatcher) { writeSnapshot(file, bitmap) }
    } catch (ex: CancellationException) {
        val deleted = withContext(NonCancellable + ioDispatcher) { !file.exists() || file.delete() }
        if (!deleted) Log.e("MapSnapshotSaver", "Failed to delete the snapshot of a cancelled save: ${file.name}")
        throw ex
    }
}

private fun writeSnapshot(file: File, bitmap: Bitmap): String? {
    var scaledBitmap: Bitmap = bitmap
    return try {
        if (bitmap.width > SNAPSHOT_MAX_WIDTH) {
            val scaledHeight = (bitmap.height * SNAPSHOT_MAX_WIDTH / bitmap.width)
            scaledBitmap = Bitmap.createScaledBitmap(
                bitmap,
                SNAPSHOT_MAX_WIDTH,
                scaledHeight,
                true
            )
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
        Log.e("MapSnapshotSaver", "Failed to save map snapshot", ex)
        null
    } finally {
        // The scaled copy is ours to release; the original belongs to the Maps callback.
        if (scaledBitmap !== bitmap) scaledBitmap.recycle()
    }
}

private const val SNAPSHOT_MAX_WIDTH = 600
private const val PNG_QUALITY_IGNORED = 100 // PNG is lossless; this value is ignored by the codec
