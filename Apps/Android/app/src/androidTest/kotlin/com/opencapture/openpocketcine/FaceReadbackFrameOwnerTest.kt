package com.opencapture.openpocketcine

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mlkit.vision.common.InputImage
import com.opencapture.openpocketcine.session.LiveFaceDetector
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED pixels, actual thin-app adapter and ML Kit frame types; no camera session is constructed. */
@RunWith(AndroidJUnit4::class)
class FaceReadbackFrameOwnerTest {
    private fun onMain(action: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync { action() }

    @Test fun actualAdapterFactoryRetainsBitmapUntilItsFrameIsDiscarded() = onMain {
        val source = monitorLiveFeedSource { error("Frame-only operations must not read or create a camera session") }
        val bitmap = Bitmap.createBitmap(32, 16, Bitmap.Config.ARGB_8888)
        try {
            val frame = source.faceFrame(bitmap)
            assertEquals(32, frame.width)
            assertEquals(16, frame.height)
            assertFalse(bitmap.isRecycled)
            source.discardUnsubmittedFaceFrame(frame, bitmap)
            assertTrue(bitmap.isRecycled)
        } finally {
            if (!bitmap.isRecycled) bitmap.recycle()
        }
    }

    @Test fun actualAdapterDiscardsThroughTheRealMlFrameOwnerExactlyOnce() = onMain {
        val source = monitorLiveFeedSource { error("Discard must not read or create a camera session") }
        val bitmap = Bitmap.createBitmap(32, 16, Bitmap.Config.ARGB_8888)
        var ownerReleases = 0
        try {
            val image = InputImage.fromBitmap(bitmap, 0)
            val frame = LiveFaceDetector.Frame(image, bitmap.width, bitmap.height) {
                assertFalse(bitmap.isRecycled)
                ownerReleases++
                bitmap.recycle()
            }
            source.discardUnsubmittedFaceFrame(frame, bitmap)
            assertEquals(1, ownerReleases, "Recycling raw pixels directly bypasses the actual frame owner")
            assertTrue(bitmap.isRecycled)
        } finally {
            if (!bitmap.isRecycled) bitmap.recycle()
        }
    }
}
