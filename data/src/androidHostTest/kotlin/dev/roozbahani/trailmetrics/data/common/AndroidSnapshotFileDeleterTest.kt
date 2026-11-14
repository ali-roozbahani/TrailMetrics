package dev.roozbahani.trailmetrics.data.common

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
class AndroidSnapshotFileDeleterTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val deleter = AndroidSnapshotFileDeleter(UnconfinedTestDispatcher())

    @Test
    fun `a null path is ignored`() = runTest {
        deleter.delete(null)
    }

    @Test
    fun `an empty path is ignored`() = runTest {
        deleter.delete("")
    }

    @Test
    fun `a blank path is ignored`() = runTest {
        deleter.delete("   ")
    }

    @Test
    fun `an existing file is deleted`() = runTest {
        val snapshot = tempFolder.newFile("snapshot.png")

        deleter.delete(snapshot.absolutePath)

        assertFalse(snapshot.exists())
    }

    @Test
    fun `a path to a missing file returns normally`() = runTest {
        val missing = File(tempFolder.root, "missing.png")

        deleter.delete(missing.absolutePath)

        assertFalse(missing.exists())
    }

    @Test
    fun `a path to an empty directory leaves the directory`() = runTest {
        val directory = tempFolder.newFolder("snapshots")

        deleter.delete(directory.absolutePath)

        assertTrue(directory.isDirectory)
    }

    @Test
    fun `resolve returns the stored path as it is and null for none`() {
        assertEquals("/data/files/snapshot.png", deleter.resolve("/data/files/snapshot.png"))
        assertNull(deleter.resolve(null))
        assertNull(deleter.resolve(""))
        assertNull(deleter.resolve("   "))
    }

    @Test
    fun `a path to a non-empty directory leaves it and its contents in place`() = runTest {
        val directory = tempFolder.newFolder("snapshots")
        val child = File(directory, "snapshot.png").apply { createNewFile() }

        deleter.delete(directory.absolutePath)

        assertTrue(directory.exists())
        assertTrue(child.exists())
    }

    @Test
    fun `the delete runs on the injected dispatcher`() = runTest {
        val snapshot = tempFolder.newFile("snapshot.png")
        val queuedDeleter = AndroidSnapshotFileDeleter(StandardTestDispatcher(testScheduler))

        val call = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            queuedDeleter.delete(snapshot.absolutePath)
        }

        assertTrue(snapshot.exists(), "the caller did not delete on its own thread")
        testScheduler.runCurrent()
        call.join()
        assertFalse(snapshot.exists())
    }

    @Test
    fun `a caller that is already cancelled still gets the file removed`() = runTest {
        val snapshot = tempFolder.newFile("snapshot.png")

        launch(UnconfinedTestDispatcher(testScheduler)) {
            currentCoroutineContext().cancel()
            deleter.delete(snapshot.absolutePath)
        }.join()

        assertFalse(snapshot.exists())
    }
}
