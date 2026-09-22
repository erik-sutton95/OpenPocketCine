package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ScopeSamplePublicationTest {
    @Test fun changingClipsClearsScopesAndRejectsAnAlreadyQueuedOldResult() {
        val first = LiveScopeSampleBus.openSource()
        val oldFrame = picture(200)
        assertTrue(LiveScopeSampleBus.publish(first, oldFrame))
        val queuedPublish = { LiveScopeSampleBus.publish(first, oldFrame) }
        val second = LiveScopeSampleBus.openSource()
        try {
            assertFalse(queuedPublish())
            assertTrue(LiveScopeSampleBus.bundle.isEmpty)
            val newFrame = picture(80)
            assertTrue(LiveScopeSampleBus.publish(second, newFrame))
            assertEquals(newFrame, LiveScopeSampleBus.bundle)
        } finally { LiveScopeSampleBus.closeSource(second) }
    }

    @Test fun departingLiveRendererCannotOverwriteOrClearPlayback() {
        val live = LiveScopeSampleBus.openSource()
        val playback = LiveScopeSampleBus.openSource()
        val frame = picture(128)
        try {
            assertTrue(LiveScopeSampleBus.publish(playback, frame))
            assertFalse(LiveScopeSampleBus.publish(live, picture(230)))
            LiveScopeSampleBus.closeSource(live)
            assertEquals(frame, LiveScopeSampleBus.bundle)
            assertTrue(LiveScopeSampleBus.isCurrent(playback))
        } finally { LiveScopeSampleBus.closeSource(playback) }
        assertFalse(LiveScopeSampleBus.publish(playback, frame))
        assertTrue(LiveScopeSampleBus.bundle.isEmpty)
    }

    @Test fun sourceReadinessStillRequiresANewlyLatchedFrameAfterAClipChange() {
        val source = InspectorPreviewSource()
        source.configure("first", true)
        source.didLatch(source.beginLatch())
        val old = source.captureEpoch()
        source.configure("second", false)
        assertFalse(source.isCurrent(old))
        assertEquals(null, source.captureEpoch())
        source.configure("second", true)
        source.didLatch(old)
        assertEquals(null, source.captureEpoch())
        source.didLatch(source.beginLatch())
        assertTrue(source.isCurrent(source.captureEpoch()))
    }

    private fun picture(code: Int) = ScopeAssistBundle(
        revision = 1,
        samples = ScopeSamples.EMPTY.copy(histogramLuma = IntArray(256).also { it[code] = 9 }),
    )
}
