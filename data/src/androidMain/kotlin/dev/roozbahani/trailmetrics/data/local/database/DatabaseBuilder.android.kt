package dev.roozbahani.trailmetrics.data.local.database

import android.content.Context
import androidx.room3.Room
import androidx.room3.RoomDatabase
import org.koin.mp.KoinPlatform.getKoin

actual fun getDatabaseBuilder(): RoomDatabase.Builder<TrailMetricsDatabase> {
    val context: Context = getKoin().get()
    val dbFile = context.getDatabasePath("trailmetrics.db")
    return Room.databaseBuilder<TrailMetricsDatabase>(context, dbFile.absolutePath)
}
