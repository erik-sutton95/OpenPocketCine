package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.EvComp
import kotlin.math.abs
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FacePriorityExposureTest {
    @Test
    fun oneDarkFaceAddsPositiveEV() {
        val transfer = MonitorTransfer.REC709
        val dark = LiveColorScience.encode(0.18 / 4, transfer)
        val next = FacePriorityExposure.nextEV(EvComp.ZERO, dark, transfer)
        assertTrue(next != null && next.thirds > 0)
    }

    @Test
    fun oneBrightFaceSubtractsEV() {
        val transfer = MonitorTransfer.REC709
        val bright = LiveColorScience.encode(0.18 * 4, transfer)
        val next = FacePriorityExposure.nextEV(EvComp.ZERO, bright, transfer)
        assertTrue(next != null && next.thirds < 0)
    }

    @Test
    fun largeErrorMovesOneThird() {
        val transfer = MonitorTransfer.REC709
        val dark = LiveColorScience.encode(0.18 / 4, transfer)
        assertEquals(EvComp(1), FacePriorityExposure.nextEV(EvComp.ZERO, dark, transfer))
    }

    @Test
    fun twoThirdsDeadbandHolds() {
        val transfer = MonitorTransfer.REC709
        val near = LiveColorScience.encode(0.18 * 2.0.pow(-0.5), transfer)
        assertNull(FacePriorityExposure.nextEV(EvComp.ZERO, near, transfer))
    }

    @Test
    fun alreadyOnGrayIsDeadband() {
        val transfer = MonitorTransfer.DLOG2
        assertNull(
            FacePriorityExposure.nextEV(EvComp.ZERO, transfer.middleGrayEncoded, transfer),
        )
    }

    @Test
    fun restoreUsesSavedOrZero() {
        assertEquals(EvComp.ZERO, FacePriorityExposure.restoreEV(null))
        assertEquals(EvComp(3), FacePriorityExposure.restoreEV(EvComp(3)))
        assertEquals(EvComp(-2), FacePriorityExposure.restoreEV(EvComp(-2)))
        assertEquals(EvComp(3), FacePriorityExposure.restoreWrite(EvComp(3), true, EvComp.ZERO))
        assertNull(FacePriorityExposure.restoreWrite(EvComp(3), false, EvComp.ZERO))
        assertNull(FacePriorityExposure.restoreWrite(EvComp(3), true, EvComp(3)))
        assertEquals(EvComp.ZERO, FacePriorityExposure.restoreWrite(null, true, EvComp(2)))
    }

    @Test
    fun twoFacesUseMedian() {
        assertEquals(0.5, FacePriorityExposure.median(listOf(0.1, 0.9)))
        assertEquals(0.4, FacePriorityExposure.median(listOf(0.2, 0.4, 0.9)))
        assertNull(FacePriorityExposure.median(emptyList()))
    }

    @Test
    fun emptyTapWritesNothing() {
        val bytes = ByteArray(16) { 128.toByte() }
        assertNull(
            FacePriorityExposure.medianEncoded(
                bytes = bytes,
                width = 2,
                height = 2,
                bytesPerRow = 8,
                boxes = emptyList(),
                transfer = MonitorTransfer.REC709,
            ),
        )
    }

    @Test
    fun samplesPixelsInsideTheBox() {
        val bytes = ByteArray(8 * 8 * 4)
        for (y in 0 until 8) {
            for (x in 4 until 8) {
                val i = (y * 8 + x) * 4
                bytes[i] = 0xFF.toByte()
                bytes[i + 1] = 0xFF.toByte()
                bytes[i + 2] = 0xFF.toByte()
            }
        }
        val left = FacePriorityExposure.Box(0.0, 0.0, 0.5, 1.0)
        val right = FacePriorityExposure.Box(0.5, 0.0, 0.5, 1.0)
        val dark =
            FacePriorityExposure.medianEncoded(bytes, 8, 8, 32, listOf(left), MonitorTransfer.REC709)
        val bright =
            FacePriorityExposure.medianEncoded(bytes, 8, 8, 32, listOf(right), MonitorTransfer.REC709)
        val both =
            FacePriorityExposure.medianEncoded(
                bytes,
                8,
                8,
                32,
                listOf(left, right),
                MonitorTransfer.REC709,
            )
        assertTrue(dark != null && dark < 0.1)
        assertTrue(bright != null && bright > 0.9)
        assertTrue(both != null && abs(both - 0.5) < 0.15)
    }

    @Test
    fun intervalIsFastWhileAcquiring() {
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.interval(0.0, 0.0),
        )
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.interval(0.0, 2.4),
        )
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.intervalSince(0L, 0L),
        )
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.intervalSince(0L, 2_400L),
        )
    }

    @Test
    fun intervalSettlesAfterAcquireWindow() {
        assertEquals(
            FacePriorityExposure.SETTLE_INTERVAL,
            FacePriorityExposure.interval(0.0, 2.5),
        )
        assertEquals(
            FacePriorityExposure.SETTLE_INTERVAL,
            FacePriorityExposure.interval(0.0, 10.0),
        )
        assertEquals(
            FacePriorityExposure.SETTLE_INTERVAL,
            FacePriorityExposure.intervalSince(0L, 2_500L),
        )
    }

    @Test
    fun intervalIsFastBeforeAcquireStarts() {
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.interval(null, 0.0),
        )
        assertEquals(
            FacePriorityExposure.ACQUIRE_INTERVAL,
            FacePriorityExposure.intervalSince(null, 0L),
        )
    }

    @Test
    fun clampsToEvRange() {
        val transfer = MonitorTransfer.REC709
        val black = LiveColorScience.encode(0.18 / 64, transfer)
        val next = FacePriorityExposure.nextEV(EvComp(8), black, transfer)
        assertEquals(EvComp.MAX_THIRDS, next?.thirds)
    }
}
