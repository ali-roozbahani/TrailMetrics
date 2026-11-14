package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.cinterop.BooleanVar
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSURL
import platform.Foundation.NSUserDomainMask

/**
 * Deletes the stored snapshot file (a regular file only) on [ioDispatcher], off the main thread.
 *
 * A stored path is a full path captured at save time, but the Application Support directory's
 * container UUID is not stable across reinstalls: the old absolute path then points at a container
 * that no longer exists while the file itself carries over under the same name. So only the file
 * name of the stored path is used, resolved against [applicationSupportDirectory], the current
 * Application Support directory ([resolve], which the iOS History screen calls to show the image).
 * A blank, missing or undeletable path is not an error.
 */
class IosSnapshotFileDeleter(
    private val ioDispatcher: CoroutineDispatcher,
    private val applicationSupportDirectory: () -> String? = ::currentApplicationSupportDirectory
) : SnapshotFileDeleter {

    @OptIn(ExperimentalForeignApi::class) // removeItemAtPath takes the error out-parameter
    override suspend fun delete(storedPath: String?) {
        val path = resolve(storedPath) ?: return
        // Not cancellable, as on Android: one short file operation that is better finished.
        withContext(NonCancellable + ioDispatcher) {
            // Only a regular file: removeItemAtPath removes a directory with everything in it, so a
            // path that names a directory deletes nothing. Best effort: it returns false for a file
            // that is missing or cannot be removed.
            if (isRegularFile(path)) NSFileManager.defaultManager.removeItemAtPath(path, error = null)
        }
    }

    override fun resolve(storedPath: String?): String? {
        if (storedPath.isNullOrBlank()) return null
        val fileName = storedPath.trimEnd('/').substringAfterLast('/')
        if (fileName.isEmpty() || fileName == "." || fileName == "..") return null
        val directory = applicationSupportDirectory() ?: return null
        return "${directory.trimEnd('/')}/$fileName"
    }
}

@OptIn(ExperimentalForeignApi::class) // fileExistsAtPath takes the isDirectory out-parameter
private fun isRegularFile(path: String): Boolean = memScoped {
    val isDirectory = alloc<BooleanVar>()
    NSFileManager.defaultManager.fileExistsAtPath(path, isDirectory = isDirectory.ptr) && !isDirectory.value
}

private fun currentApplicationSupportDirectory(): String? =
    (NSFileManager.defaultManager.URLsForDirectory(NSApplicationSupportDirectory, NSUserDomainMask)
        .firstOrNull() as? NSURL)?.path
