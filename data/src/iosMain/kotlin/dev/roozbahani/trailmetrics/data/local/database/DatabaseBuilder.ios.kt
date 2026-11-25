package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.Room
import androidx.room3.RoomDatabase
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.cinterop.ExperimentalForeignApi
import org.koin.mp.KoinPlatform.getKoin
import platform.Foundation.NSDocumentDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSUserDomainMask

@OptIn(ExperimentalForeignApi::class)
actual fun getDatabaseBuilder(): RoomDatabase.Builder<TrailMetricsDatabase> {
    val documentDirectory = NSFileManager.defaultManager.URLForDirectory(
        directory = NSDocumentDirectory,
        inDomain = NSUserDomainMask,
        appropriateForURL = null,
        create = false,
        error = null
    )
    val dbFilePath = requireNotNull(documentDirectory).path + "/" + DATABASE_FILE_NAME
    return databaseBuilderAt(dbFilePath, getKoin().get<Logger>())
}

/**
 * The builder of the database file at [path]. The file protection class is set where Room opens the file
 * ([DatabaseFileProtectionCallback]), not here: this runs where Koin first resolves the database, which can
 * be the main thread.
 */
internal fun databaseBuilderAt(
    path: String,
    logger: Logger,
    protectionSetter: FileProtectionSetter = fileManagerProtectionSetter
): RoomDatabase.Builder<TrailMetricsDatabase> =
    Room.databaseBuilder<TrailMetricsDatabase>(name = path)
        .addCallback(DatabaseFileProtectionCallback(path, logger, protectionSetter))
