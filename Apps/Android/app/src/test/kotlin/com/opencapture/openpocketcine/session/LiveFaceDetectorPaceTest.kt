package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveFaceDetectorPaceTest {
    @Test
    fun tracksAtFeedRateThenIdlesAt10HzAfterASecondWithoutFaces() {
        assertEquals(40L, LiveFaceDetector.pace(0))
        assertEquals(40L, LiveFaceDetector.pace(LiveFaceDetector.IDLE_AFTER_EMPTY_RUNS - 1))
        assertEquals(100L, LiveFaceDetector.pace(LiveFaceDetector.IDLE_AFTER_EMPTY_RUNS))
    }

    @Test
    fun trackingTakesEveryFrameAndIdleOnlyNearItsNextRun() {
        assertTrue(LiveFaceDetector.wantsFrame(emptyRuns = 0, sinceLastRunMs = 0))
        val idle = LiveFaceDetector.IDLE_AFTER_EMPTY_RUNS
        assertFalse(LiveFaceDetector.wantsFrame(idle, sinceLastRunMs = 20))
        assertTrue(LiveFaceDetector.wantsFrame(idle, sinceLastRunMs = 60), "readback lands by the 100 ms run")
    }
}
