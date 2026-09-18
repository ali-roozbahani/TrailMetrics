package dev.roozbahani.trailmetrics.feature.history.util

import java.io.File

internal fun deleteSnapshotFile(path: String?) {
    if (!path.isNullOrBlank()) {
        File(path).delete()
    }
}
