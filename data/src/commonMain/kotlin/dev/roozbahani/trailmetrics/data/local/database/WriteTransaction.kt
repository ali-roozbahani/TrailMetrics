package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.withWriteTransaction

/**
 * Runs the writes of a block as one transaction of the database: all of them or none. The DAO calls inside
 * [block] join it, whichever DAO they are on.
 */
interface WriteTransaction {
    suspend fun run(block: suspend () -> Unit)
}

/** [WriteTransaction] on a Room database's writer connection. */
class RoomWriteTransaction(private val database: TrailMetricsDatabase) : WriteTransaction {
    override suspend fun run(block: suspend () -> Unit) {
        database.withWriteTransaction { block() }
    }
}
