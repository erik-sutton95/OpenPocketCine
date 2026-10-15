package com.opencapture.openpocketcine.session

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FaceFrameInputTest {
    @Test fun initializerFailureReleasesPixelsAndStopsOnlyThisOptionalProducer() {
        var reports = 0
        var released = 0
        val input = FaceFrameInput { reports++ }
        assertNull(input.construct(320, 180, { released++ }) { throw NullPointerException("SDK component unavailable") })
        assertTrue(input.failed)
        assertEquals(1, reports)
        assertEquals(1, released)
        assertNull(input.construct(320, 180, { released++ }) { error("Failed producer must not retry the SDK every frame") })
        assertEquals(1, reports)
        assertEquals(2, released)
        // Operator retry creates a distinct producer; successful input still belongs to its detector.
        val retry = FaceFrameInput { error("Unexpected retry failure") }
        val bitmap = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888)
        val frame = retry.construct(32, 32, bitmap::recycle) { InputImage.fromBitmap(bitmap, 0) }
        assertNotNull(frame)
        assertFalse(bitmap.isRecycled)
        frame!!.release()
        assertTrue(bitmap.isRecycled)
        assertFalse(retry.failed)
    }

    @Test fun cancellationRemainsCancellationAndDoesNotBecomeAnSdkFailure() {
        var released = 0
        val input = FaceFrameInput { error("Cancellation must not be reported as SDK failure") }
        try {
            input.construct(32, 32, { released++ }) { throw CancellationException("retired") }
            fail("Cancellation must escape")
        } catch (_: CancellationException) {
            assertEquals(1, released)
            assertFalse(input.failed)
        }
    }
}
