package com.opencapture.openpocketcine.feed

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises actual asynchronous bitmap publication and the production EGL grade path. */
@RunWith(AndroidJUnit4::class)
class MonitorBackdropFeedTest {
    @Test fun retiredCallbacksCannotClearOrRegradeCurrentProducer() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val feed = MonitorBackdropFeed(instrumentation.targetContext)
        val old = Any(); val next = Any()
        instrumentation.runOnMainSync { feed.attach(old); feed.setActive(true) }
        val stale = assertNotNull(feed.acquire(old, 0))
        instrumentation.runOnMainSync { feed.attach(next) }
        assertNull(feed.acquire(next, 1_000_000_000))
        feed.submit(stale, frame(255, 0, 0), FeedEffectsRenderPlan.IDENTITY)
        var ticket: BackdropFrameAdmission.Ticket? = null
        await { ticket = feed.acquire(next, 1_000_000_000); ticket != null }
        feed.submit(checkNotNull(ticket), frame(0, 255, 0), FeedEffectsRenderPlan.IDENTITY)
        await { feed.source.image != null }
        val current = assertNotNull(feed.source.image)
        assertEquals(Color.GREEN, current.getPixel(0, 0))
        instrumentation.runOnMainSync {
            feed.invalidate(old)
            feed.updatePlan(old, FeedEffectsRenderPlan.IDENTITY)
        }
        assertSame(current, feed.source.image)
        assertFalse(feed.hasDemand(old)); assertTrue(feed.hasDemand(next))
        instrumentation.runOnMainSync { feed.setActive(false) }
        assertNull(feed.source.image)
        assertNull(feed.acquire(next, 2_000_000_000))
    }

    @Test fun rawOrientationAndRealGradeRemainBoundedAcrossResize() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val renderer = InspectorPreviewRenderer()
        try {
            // Distinct rows catch double flips between bottom-up GLES and top-down Vulkan taps.
            val raw = byteArrayOf(255.toByte(), 0, 0, 255.toByte(), 0, 0, 255.toByte(), 255.toByte())
            val upright = InspectorPreviewFrame.fromTap(raw, 1, 2, bottomUp = false)
            val flipped = InspectorPreviewFrame.fromTap(raw, 1, 2, bottomUp = true)
            val a = renderer.render(instrumentation.targetContext, FeedEffectsRenderPlan.IDENTITY, upright)
            val b = renderer.render(instrumentation.targetContext, FeedEffectsRenderPlan.IDENTITY, flipped)
            assertEquals(Color.RED, a.getPixel(0, 0)); assertEquals(Color.BLUE, a.getPixel(0, 1))
            assertEquals(Color.BLUE, b.getPixel(0, 0)); assertEquals(Color.RED, b.getPixel(0, 1))
            val resized = renderer.render(instrumentation.targetContext, FeedEffectsRenderPlan.IDENTITY, frame(0, 255, 0))
            assertEquals(213, resized.width); assertEquals(120, resized.height)
            assertEquals(Color.GREEN, resized.getPixel(100, 60))
        } finally { renderer.close() }
    }

    private fun frame(r: Int, g: Int, b: Int): InspectorPreviewFrame = InspectorPreviewFrame(213, 120,
        ByteArray(213 * 120 * 4) { when (it % 4) { 0 -> r; 1 -> g; 2 -> b; else -> 255 }.toByte() })

    private fun await(predicate: () -> Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (System.nanoTime() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            if (predicate()) return
            Thread.sleep(20)
        }
        assertTrue(predicate(), "bounded preview did not complete")
    }
}
