package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.media.ScopeSamples
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.opencapture.opencine.runtime.ScopeSampleBus
import com.opencapture.opencine.media.ScopeAssistBundle

class ScopeSamplePublicationTest {
    private val scopeBus = ScopeSampleBus()
    @Test fun changingClipsClearsScopesAndRejectsAnAlreadyQueuedOldResult() {
        val first = scopeBus.openSource()
        val oldFrame = picture(200)
        assertTrue(scopeBus.publish(first, oldFrame))
        val queuedPublish = { scopeBus.publish(first, oldFrame) }
        val second = scopeBus.openSource()
        try {
            assertFalse(queuedPublish())
            assertTrue(scopeBus.bundle.isEmpty)
            val newFrame = picture(80)
            assertTrue(scopeBus.publish(second, newFrame))
            assertEquals(newFrame, scopeBus.bundle)
        } finally { scopeBus.closeSource(second) }
    }

    @Test fun departingLiveRendererCannotOverwriteOrClearPlayback() {
        val live = scopeBus.openSource()
        val playback = scopeBus.openSource()
        val frame = picture(128)
        try {
            assertTrue(scopeBus.publish(playback, frame))
            assertFalse(scopeBus.publish(live, picture(230)))
            scopeBus.closeSource(live)
            assertEquals(frame, scopeBus.bundle)
            assertTrue(scopeBus.isCurrent(playback))
        } finally { scopeBus.closeSource(playback) }
        assertFalse(scopeBus.publish(playback, frame))
        assertTrue(scopeBus.bundle.isEmpty)
    }

    private fun picture(code: Int) = ScopeAssistBundle(
        revision = 1,
        samples = ScopeSamples.EMPTY.copy(histogramLuma = IntArray(256).also { it[code] = 9 }),
    )
}
