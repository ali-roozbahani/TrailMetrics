package dev.roozbahani.trailmetrics.feature.history.util

import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SnapshotFileDeleterTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun `a null path is ignored`() {
        deleteSnapshotFile(null)
    }

    @Test
    fun `an empty path is ignored`() {
        deleteSnapshotFile("")
    }

    @Test
    fun `a blank path is ignored`() {
        deleteSnapshotFile("   ")
    }

    @Test
    fun `an existing file is deleted`() {
        val snapshot = tempFolder.newFile("snapshot.png")

        deleteSnapshotFile(snapshot.absolutePath)

        assertFalse(snapshot.exists())
    }

    @Test
    fun `a path to a missing file does not throw`() {
        val missing = File(tempFolder.root, "missing.png")

        deleteSnapshotFile(missing.absolutePath)

        assertFalse(missing.exists())
    }

    // File.delete removes an empty directory; no production check restricts it to files.
    @Test
    fun `a path to an empty directory deletes the directory`() {
        val directory = tempFolder.newFolder("snapshots")

        deleteSnapshotFile(directory.absolutePath)

        assertFalse(directory.exists())
    }

    @Test
    fun `a path to a non-empty directory leaves it and its contents in place`() {
        val directory = tempFolder.newFolder("snapshots")
        val child = File(directory, "snapshot.png").apply { createNewFile() }

        deleteSnapshotFile(directory.absolutePath)

        assertTrue(directory.exists())
        assertTrue(child.exists())
    }
}
