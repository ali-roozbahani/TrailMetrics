package dev.roozbahani.trailmetrics.feature.tracking.util

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import kotlin.coroutines.CoroutineContext
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [saveSnapshotToFile] under Robolectric's native graphics, so the PNG is really encoded and can be
 * decoded back to check its size.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class MapSnapshotSaverTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private val testDispatcher = UnconfinedTestDispatcher()

    private suspend fun save(bitmap: Bitmap): String? = saveSnapshotToFile(context, bitmap, testDispatcher)

    @Test
    fun `a bitmap wider than 600 px is scaled to 600 px wide keeping its aspect ratio`() = runTest {
        val path = assertNotNull(save(bitmap(width = 1200, height = 800)))

        assertSavedPng(path, width = 600, height = 400)
    }

    @Test
    fun `the scaled height is rounded down`() = runTest {
        val path = assertNotNull(save(bitmap(width = 1000, height = 333)))

        // 333 x 600 / 1000 = 199.8
        assertSavedPng(path, width = 600, height = 199)
    }

    @Test
    fun `a bitmap exactly 600 px wide is written unscaled`() = runTest {
        val path = assertNotNull(save(bitmap(width = 600, height = 900)))

        assertSavedPng(path, width = 600, height = 900)
    }

    @Test
    fun `a bitmap narrower than 600 px is written unscaled`() = runTest {
        val path = assertNotNull(save(bitmap(width = 320, height = 480)))

        assertSavedPng(path, width = 320, height = 480)
    }

    @Test
    fun `a files directory that cannot be written to returns null and does not throw`() = runTest {
        // A regular file where the directory should be: opening a file inside it fails with an IOException.
        val notADirectory = File.createTempFile("filesDir", ".txt").apply { deleteOnExit() }
        val unwritable = object : ContextWrapper(context) {
            override fun getFilesDir(): File = notADirectory
        }

        assertNull(saveSnapshotToFile(unwritable, bitmap(width = 100, height = 100), testDispatcher))
    }

    @Test
    fun `the scale, encode and write run on the injected dispatcher`() = runTest {
        val recording = RecordingDispatcher()

        val path = assertNotNull(saveSnapshotToFile(context, bitmap(width = 1200, height = 800), recording))

        assertEquals(1, recording.dispatchCount)
        assertSavedPng(path, width = 600, height = 400)
    }

    @Test
    fun `a failed write returns null from the injected dispatcher`() = runTest {
        val recording = RecordingDispatcher()
        val notADirectory = File.createTempFile("filesDir", ".txt").apply { deleteOnExit() }
        val unwritable = object : ContextWrapper(context) {
            override fun getFilesDir(): File = notADirectory
        }

        assertNull(saveSnapshotToFile(unwritable, bitmap(width = 100, height = 100), recording))
        assertEquals(1, recording.dispatchCount)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `a save cancelled after the write deletes its file and rethrows the cancellation`() = runTest {
        val recording = RecordingDispatcher()
        var cancellation: CancellationException? = null
        val job = launch(UnconfinedTestDispatcher(testScheduler), start = CoroutineStart.LAZY) {
            try {
                saveSnapshotToFile(context, bitmap(width = 100, height = 100), recording)
            } catch (ex: CancellationException) {
                cancellation = ex
                throw ex
            }
        }
        // The job is cancelled right after the IO block wrote the file.
        recording.cancelAfterFirstBlock = job

        job.start()
        job.join()

        assertNotNull(cancellation)
        val leftovers = context.filesDir.listFiles { file -> file.name.startsWith("activity_") }.orEmpty()
        assertEquals(0, leftovers.size)
    }

    private fun assertSavedPng(path: String, width: Int, height: Int) {
        val file = File(path)
        assertTrue(file.isFile, "$path exists")
        assertEquals(context.filesDir.canonicalFile, file.canonicalFile.parentFile)
        assertTrue(file.name.startsWith("activity_") && file.name.endsWith(".png"), "file name ${file.name}")
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        assertEquals("image/png", options.outMimeType)
        assertEquals(width, options.outWidth)
        assertEquals(height, options.outHeight)
    }

    private fun bitmap(width: Int, height: Int): Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

    /** Runs each block inline and counts the dispatches; can cancel a job right after the first block. */
    private class RecordingDispatcher : CoroutineDispatcher() {
        var dispatchCount = 0
        var cancelAfterFirstBlock: Job? = null

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            dispatchCount++
            block.run()
            cancelAfterFirstBlock?.cancel()
            cancelAfterFirstBlock = null
        }
    }
}
