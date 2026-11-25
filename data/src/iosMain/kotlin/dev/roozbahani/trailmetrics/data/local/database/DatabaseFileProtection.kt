package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.RoomDatabase
import androidx.sqlite.SQLiteConnection
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.ObjCObjectVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import platform.Foundation.NSError
import platform.Foundation.NSFileManager
import platform.Foundation.NSFileProtectionCompleteUntilFirstUserAuthentication
import platform.Foundation.NSFileProtectionKey
import platform.Foundation.NSFileProtectionType

/**
 * The iOS Data Protection class of the database (owner decision of 2026-11-25). The database holds the
 * in-progress tracking session, which is saved on every location update while tracking runs with the
 * screen off: the file must stay readable and writable while the device is locked, after the first unlock
 * since boot. `NSFileProtectionComplete` would close it a few seconds after the lock and
 * `NSFileProtectionCompleteUnlessOpen` would refuse the journal files SQLite creates while locked; both lose
 * saves. The history and the route draft live in the same file, so they have the same class.
 *
 * It is the class iOS gives a file when the app sets none (no data-protection entitlement); it is set here
 * so that it is a decision in the code, not a default.
 */
internal val databaseFileProtection: NSFileProtectionType = NSFileProtectionCompleteUntilFirstUserAuthentication

/** The files SQLite keeps next to the database file, by suffix. */
private val sqliteCompanionSuffixes = listOf("-wal", "-shm", "-journal")

/**
 * Sets the protection class of one file or directory; returns why it failed, or null. A seam: the simulator
 * neither stores nor reports a protection class, so a test records the calls instead.
 */
internal fun interface FileProtectionSetter {
    fun setProtection(path: String, protection: NSFileProtectionType): String?
}

/** [FileProtectionSetter] through `NSFileManager.setAttributes`. */
// Both opt-ins for the NSError out-parameter of setAttributes (alloc, ptr, reading its value): no other API
// reports why the class could not be set.
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
internal val fileManagerProtectionSetter = FileProtectionSetter { path, protection ->
    memScoped {
        val error = alloc<ObjCObjectVar<NSError?>>()
        val isSet = NSFileManager.defaultManager.setAttributes(
            attributes = mapOf<Any?, Any?>(NSFileProtectionKey to protection),
            ofItemAtPath = path,
            error = error.ptr
        )
        if (isSet) null else error.value?.localizedDescription ?: "no reason given"
    }
}

/**
 * Gives [databaseFileProtection] to the directory of [databasePath] (a file created in it later, such as a
 * journal SQLite makes again after a close, gets the directory's class) and to the database file and its
 * companions that exist. Returns one line per path whose class could not be set; empty when all were.
 */
internal fun applyDatabaseFileProtection(
    databasePath: String,
    setter: FileProtectionSetter = fileManagerProtectionSetter,
    fileExists: (String) -> Boolean = { NSFileManager.defaultManager.fileExistsAtPath(it) }
): List<String> {
    val directory = databasePath.substringBeforeLast('/', missingDelimiterValue = ".")
    val files = (listOf(databasePath) + sqliteCompanionSuffixes.map { databasePath + it }).filter(fileExists)
    return (listOf(directory) + files).mapNotNull { path ->
        setter.setProtection(path, databaseFileProtection)?.let { reason -> "$path: $reason" }
    }
}

/**
 * Applies [databaseFileProtection] each time Room opens the database, on Room's query context (off the main
 * thread), after SQLite created the file and its journal.
 *
 * A path whose class cannot be set is logged and the database opens as usual: the file then keeps the class
 * iOS gave it, which without a data-protection entitlement is the same class, and failing the open instead
 * would lose every save, not only make the class implicit.
 */
internal class DatabaseFileProtectionCallback(
    private val databasePath: String,
    private val logger: Logger,
    private val setter: FileProtectionSetter = fileManagerProtectionSetter
) : RoomDatabase.Callback() {
    override suspend fun onOpen(connection: SQLiteConnection) {
        applyDatabaseFileProtection(databasePath, setter).forEach { failure ->
            logger.debug(TAG, "Setting the database file protection failed: $failure")
        }
    }

    private companion object {
        const val TAG = "DatabaseFileProtection"
    }
}
