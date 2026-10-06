package dev.roozbahani.trailmetrics.feature.tracking.util

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
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

    @Test
    fun `a bitmap wider than 600 px is scaled to 600 px wide keeping its aspect ratio`() {
        val path = assertNotNull(saveSnapshotToFile(context, bitmap(width = 1200, height = 800)))

        assertSavedPng(path, width = 600, height = 400)
    }

    @Test
    fun `the scaled height is rounded down`() {
        val path = assertNotNull(saveSnapshotToFile(context, bitmap(width = 1000, height = 333)))

        // 333 x 600 / 1000 = 199.8
        assertSavedPng(path, width = 600, height = 199)
    }

    @Test
    fun `a bitmap exactly 600 px wide is written unscaled`() {
        val path = assertNotNull(saveSnapshotToFile(context, bitmap(width = 600, height = 900)))

        assertSavedPng(path, width = 600, height = 900)
    }

    @Test
    fun `a bitmap narrower than 600 px is written unscaled`() {
        val path = assertNotNull(saveSnapshotToFile(context, bitmap(width = 320, height = 480)))

        assertSavedPng(path, width = 320, height = 480)
    }

    @Test
    fun `a files directory that cannot be written to returns null and does not throw`() {
        // A regular file where the directory should be: opening a file inside it fails with an IOException.
        val notADirectory = File.createTempFile("filesDir", ".txt").apply { deleteOnExit() }
        val unwritable = object : ContextWrapper(context) {
            override fun getFilesDir(): File = notADirectory
        }

        assertNull(saveSnapshotToFile(unwritable, bitmap(width = 100, height = 100)))
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
}
