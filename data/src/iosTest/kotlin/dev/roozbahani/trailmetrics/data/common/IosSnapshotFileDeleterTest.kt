package dev.roozbahani.trailmetrics.data.common

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import platform.Foundation.NSFileManager
import platform.Foundation.NSNumber
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import platform.Foundation.NSFilePosixPermissions
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The cases of the Android deleter's test on the real [IosSnapshotFileDeleter], with a temporary
 * directory standing in for the Application Support directory, plus the reinstall case: a stored
 * path of a container that no longer exists still finds the file by its name.
 */
@OptIn(ExperimentalForeignApi::class, ExperimentalCoroutinesApi::class)
class IosSnapshotFileDeleterTest {

    private val fileManager = NSFileManager.defaultManager
    private val supportDirectory = NSTemporaryDirectory().trimEnd('/') + "/snapshot-deleter-" + NSUUID().UUIDString
    private fun deleterOn(dispatcher: CoroutineDispatcher) =
        IosSnapshotFileDeleter(dispatcher) { supportDirectory }
    private val deleter = deleterOn(UnconfinedTestDispatcher())

    @BeforeTest
    fun createSupportDirectory() {
        fileManager.createDirectoryAtPath(
            supportDirectory,
            withIntermediateDirectories = true,
            attributes = null,
            error = null
        )
    }

    @AfterTest
    fun removeSupportDirectory() {
        setPermissions(supportDirectory, WRITABLE)
        fileManager.removeItemAtPath(supportDirectory, error = null)
    }

    private fun snapshotFile(name: String = "snapshot.png"): String {
        val path = "$supportDirectory/$name"
        fileManager.createFileAtPath(path, contents = null, attributes = null)
        return path
    }

    private fun setPermissions(path: String, mode: Int) {
        fileManager.setAttributes(
            mapOf(NSFilePosixPermissions to NSNumber(int = mode)),
            ofItemAtPath = path,
            error = null
        )
    }

    @Test
    fun `a stored path of the current directory deletes the file`() = runTest {
        val path = snapshotFile()

        deleter.delete(path)

        assertFalse(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `a stored path of a container that no longer exists finds the file by its name`() = runTest {
        val path = snapshotFile("snapshot-7.png")

        deleter.delete("/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/snapshot-7.png")

        assertFalse(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `null empty and blank paths delete nothing`() = runTest {
        val path = snapshotFile()

        deleter.delete(null)
        deleter.delete("")
        deleter.delete("   ")
        deleter.delete("/")

        assertTrue(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `a missing file is not an error and leaves the others`() = runTest {
        val path = snapshotFile()

        deleter.delete("$supportDirectory/missing.png")

        assertTrue(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `a file that cannot be removed is not an error`() = runTest {
        val path = snapshotFile()
        // A directory without write permission refuses to unlink its entries.
        setPermissions(supportDirectory, READ_ONLY)

        deleter.delete(path)

        assertTrue(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `the delete runs on the injected dispatcher`() = runTest {
        val path = snapshotFile()
        val queuedDeleter = deleterOn(StandardTestDispatcher(testScheduler))

        val call = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { queuedDeleter.delete(path) }

        assertTrue(fileManager.fileExistsAtPath(path), "the caller did not delete on its own thread")
        testScheduler.runCurrent()
        call.join()
        assertFalse(fileManager.fileExistsAtPath(path))
    }

    @Test
    fun `a caller that is already cancelled still gets the file removed`() = runTest {
        val path = snapshotFile()

        launch(UnconfinedTestDispatcher(testScheduler)) {
            currentCoroutineContext().cancel()
            deleter.delete(path)
        }.join()

        assertFalse(fileManager.fileExistsAtPath(path))
    }

    private companion object {
        const val WRITABLE = 0b111_101_101
        const val READ_ONLY = 0b101_101_101
    }
}
