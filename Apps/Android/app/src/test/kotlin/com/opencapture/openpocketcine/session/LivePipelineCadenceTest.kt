package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertEquals

/**
 * Decodes and presents that name the same picture, the way the decoder pairs
 * them: one stamp goes on the released buffer and comes back from the renderer.
 */
private class Pictures(private val cadence: LivePipelineCadence) {
    private var nextStamp = 1L
    private val waiting = ArrayDeque<Long>()

    /** Decode [count] pictures. Each is now waiting for a present. */
    fun decode(count: Int = 1) {
        repeat(count) {
            cadence.noteOutput(nextStamp)
            waiting.addLast(nextStamp)
            nextStamp += 1
        }
    }

    /** Present the [count] oldest waiting pictures. */
    fun present(count: Int = 1) {
        repeat(count) { cadence.notePresented(waiting.removeFirst()) }
    }

    /** The renderer let the [count] oldest go for a newer buffer: never shown. */
    fun abandon(count: Int = 1) {
        repeat(count) { waiting.removeFirst() }
    }
}

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
            if (i % 2 == 0) cadence.notePresented(stampNs = i.toLong())
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

    @Test fun reportsMeanAndMaxTransitSeparatelyPerLeg() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 10_000_000)
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 30_000_000)
        cadence.noteTransit(LivePipelineCadence.Leg.PRESENT, 16_000_000)
        now = 1_000_000_000
        // Mean alone would hide the 30 ms picture; max alone would claim every
        // picture took 30 ms.
        val report = cadence.drain()!!
        assertTrue(report.contains("decodeMs=20.0/30.0"), report)
        assertTrue(report.contains("presentMs=16.0/16.0"), report)
    }

    @Test fun aLegWithNoSampleReadsAsAbsentRatherThanZero() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        now = 1_000_000_000
        // Zero would read as "instant"; the pipeline simply produced no picture.
        assertTrue(cadence.drain()!!.contains("decodeMs=-1.0/-1.0"))
    }

    @Test fun aStalledOrBackwardsSampleIsNotCountedAsTransit() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, -5_000_000)
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 9_000_000_000)
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 20_000_000)
        now = 1_000_000_000
        // A 9 s gap is a stall the gap counters already report; folding it into
        // the mean would put transit at seconds and hide every real reading.
        assertTrue(cadence.drain()!!.contains("decodeMs=20.0/20.0"))
    }

    @Test fun transitResetsBetweenWindowsInsteadOfAccumulating() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 80_000_000)
        now = 1_000_000_000
        assertTrue(cadence.drain()!!.contains("decodeMs=80.0/80.0"))
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, 10_000_000)
        now = 2_000_000_000
        assertTrue(cadence.drain()!!.contains("decodeMs=10.0/10.0"))
    }

    @Test fun picturesDecodedButNeverShownCountAsDropsNotDelay() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        val pictures = Pictures(cadence)
        pictures.decode(25)
        pictures.present(19)
        pictures.abandon(6)
        now = 1_000_000_000
        // The six are still in flight as far as this window can tell.
        assertTrue(cadence.drain()!!.contains("drop=0"))
        pictures.decode(25)
        pictures.present(25)
        now = 2_000_000_000
        // A second window went by without them. The renderer takes the newest
        // buffer and lets older ones go, so a smooth-but-late feed and a
        // current-but-stuttering feed differ here.
        assertTrue(cadence.drain()!!.contains("drop=6"))
    }

    @Test fun aStandingShortfallIsReportedOnceRatherThanEveryWindow() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        val pictures = Pictures(cadence)
        pictures.decode(25)
        pictures.present(22)
        pictures.abandon(3)
        now = 1_000_000_000
        cadence.drain()
        for (window in 2..4) {
            pictures.decode(25)
            pictures.present(25)
            now = window * 1_000_000_000L
            // The three never come back, but they were lost once. Re-announcing
            // them every second would read as a feed that keeps dropping.
            val expected = if (window == 2) "drop=3" else "drop=0"
            assertTrue(cadence.drain()!!.contains(expected), "window $window")
        }
    }

    @Test fun aPictureStraddlingTheWindowBoundaryIsNotADrop() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        val pictures = Pictures(cadence)
        pictures.decode(25)
        pictures.present(24)
        now = 1_000_000_000
        // Decoded just before the close, presented just after it. Counting each
        // window on its own called this a drop every single second.
        assertTrue(cadence.drain()!!.contains("drop=0"))
        pictures.present(1)
        pictures.decode(25)
        pictures.present(25)
        now = 2_000_000_000
        assertTrue(cadence.drain()!!.contains("drop=0"))
        pictures.decode(25)
        pictures.present(25)
        now = 3_000_000_000
        assertTrue(cadence.drain()!!.contains("drop=0"))
    }

    @Test fun aPictureAlwaysInFlightAtTheBoundaryIsNotADrop() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        val pictures = Pictures(cadence)
        // 25 fps, every picture on the glass 2 ms after it leaves the decoder,
        // and the one decoded 1 ms before each close lands 1 ms after it. The
        // backlog reads one at every boundary, but it is a different picture
        // each time — counting the backlog called that steady one a drop.
        for (window in 0 until 3) {
            val opened = window * 1_000_000_000L
            repeat(25) { i ->
                now = opened + i * 40_000_000L + 39_000_000L
                pictures.decode()
                if (i < 24) {
                    now += 2_000_000L
                    pictures.present()
                }
            }
            now = opened + 1_000_000_000L
            assertTrue(cadence.drain()!!.contains("drop=0"), "window ${window + 1}")
            now += 1_000_000L
            pictures.present()
        }
        now = 4_000_000_000
        // All 75 were shown, the last of them 1 ms into this window.
        assertTrue(cadence.drain()!!.contains("drop=0"), "after the last picture")
    }

    @Test fun aPresentForAPictureThisCadenceNeverSawIsIgnored() {
        var now = 0L
        val cadence = LivePipelineCadence { now }
        cadence.noteOutput(stampNs = 7)
        // Stamps from before a decoder restart, or repaints of a buffer this
        // cadence never released. Neither says anything about picture 7.
        cadence.notePresented(stampNs = 3)
        cadence.notePresented(stampNs = 4)
        now = 1_000_000_000
        assertTrue(cadence.drain()!!.contains("drop=0"))
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
