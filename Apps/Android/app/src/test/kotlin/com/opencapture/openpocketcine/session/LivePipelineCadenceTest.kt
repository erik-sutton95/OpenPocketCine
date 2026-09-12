package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertEquals

class LivePipelineCadenceTest {
    @Test fun maximumGapIncludesInitialSilenceAndTrailingSilence() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        now = 900_000_000
        cadence.note(LivePipelineCadence.Stage.AU)
        now = 905_000_000
        cadence.note(LivePipelineCadence.Stage.AU)
        now = 1_000_000_000
        val initial = cadence.drain()!!
        assertTrue(initial.contains("au=2.0/s gap=900.0ms"), initial)
        now = 2_000_000_000
        val trailing = cadence.drain()!!
        assertTrue(trailing.contains("au=0.0/s gap=1095.0ms"), trailing)
    }

    @Test fun unseenImageFromBeforeForegroundCannotDismissRecovery() {
        val clock = PresentedFrameClock()
        clock.note(sourceNs = 12, nowMs = 100)
        val resumedAt = clock.beginProbe(sourceNowNs = 20, nowMs = 10_000)
        assertFalse(clock.note(sourceNs = 19, nowMs = 10_001))
        assertFalse(RecoveryPictureProof.isFresh(resumedAt, 10_002, clock.lastPresentedAt, 10_001))
        assertTrue(clock.note(sourceNs = 21, nowMs = 10_003))
        assertTrue(RecoveryPictureProof.isFresh(resumedAt, 10_004, clock.lastPresentedAt, 10_003))
    }

    @Test fun measuresAckAndActualPictureSeparatelyWithoutPerTickLogs() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        for (i in 0 until 40) {
            cadence.note(LivePipelineCadence.Stage.ACK)
            if (i % 2 == 0) cadence.note(LivePipelineCadence.Stage.PRESENT)
            now += 25_000_000
            if (i < 39) assertNull(cadence.drain())
        }
        val report = cadence.drain()!!
        assertTrue(report.contains("ack=40.0/s gap=25.0ms"), report)
        assertTrue(report.contains("present=20.0/s gap=50.0ms"), report)
        now += 1_000_000_000
        val silence = cadence.drain()!!
        assertTrue(silence.contains("ack=0.0/s"), silence)
        assertTrue(silence.contains("age=1025.0ms"), silence)
    }

    @Test fun capturesDecoderBacklogAndInputPressure() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        val first = cadence.queued()
        now = 40_000_000
        val second = cadence.queued()
        now = 200_000_000
        cadence.dequeued(first)
        cadence.inputMiss()
        now = 1_000_000_000
        val report = cadence.drain()!!
        assertTrue(report.contains("queue=1 peak=2 wait=200.0ms inputMiss=1"), report)
        cadence.dequeued(second)
        now += 1_000_000_000
        assertTrue(cadence.drain()!!.contains("queue=0 peak=1"))
    }

    @Test fun repaintingAHeldImageCannotEstablishFreshPicture() {
        val clock = PresentedFrameClock()
        assertTrue(clock.note(sourceNs = 12, nowMs = 100))
        assertFalse(clock.note(sourceNs = 12, nowMs = 10_000))
        assertEquals(100, clock.lastPresentedAt)
        assertTrue(clock.note(sourceNs = 13, nowMs = 10_100))
        assertFalse(clock.note(sourceNs = 11, nowMs = 10_150))
        assertEquals(10_100, clock.lastPresentedAt)
        clock.beginEpoch(20)
        assertFalse(clock.note(sourceNs = 19, nowMs = 10_200))
        assertEquals(10_100, clock.lastPresentedAt)
        assertTrue(clock.note(sourceNs = 20, nowMs = 10_250))
    }

    @Test fun handshakeOrNewAuWithoutNewPresentCannotCompleteRecovery() {
        assertFalse(RecoveryPictureProof.isFresh(100, 200, 99, 199))
        assertFalse(RecoveryPictureProof.isFresh(100, 200, 199, 99))
        assertFalse(RecoveryPictureProof.isFresh(100, 200, null, 199))
        assertTrue(RecoveryPictureProof.isFresh(100, 200, 199, 199))
        assertFalse(RecoveryPictureProof.isFresh(100, 2_200, 199, 2_199))
    }
}
