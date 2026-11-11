package dev.roozbahani.trailmetrics.data.local.dao

import androidx.room3.Dao
import androidx.room3.Query
import androidx.room3.Upsert
import dev.roozbahani.trailmetrics.data.local.entity.RouteDraftEntity
import dev.roozbahani.trailmetrics.data.local.entity.RouteDraftEntity.Companion.ROUTE_DRAFT_ID

@Dao
interface RouteDraftDao {
    @Upsert
    suspend fun upsert(draft: RouteDraftEntity)

    @Query("SELECT * FROM tbl_route_draft WHERE id = $ROUTE_DRAFT_ID")
    suspend fun get(): RouteDraftEntity?

    @Query("DELETE FROM tbl_route_draft WHERE id = $ROUTE_DRAFT_ID")
    suspend fun clear()
}
