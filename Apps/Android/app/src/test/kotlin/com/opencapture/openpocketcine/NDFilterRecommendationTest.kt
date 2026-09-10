package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NDFilterRecommendationTest {
    @Test
    fun middleGrayNeedsNoGlass() {
        val rec = NDFilterRecommendation.suggestion(0.0)
        assertEquals(0, rec.ndStops)
        assertEquals("—", rec.ndLabel)
        assertEquals("0.0", rec.stopsLabel)
        assertFalse(rec.needsGlass)
    }

    @Test
    fun twoStopsHotIsND4() {
        val rec = NDFilterRecommendation.suggestion(2.0)
        assertEquals(2, rec.ndStops)
        assertEquals(4, rec.opticalFactor)
        assertEquals("ND4", rec.ndLabel)
        assertEquals("+2.0", rec.stopsLabel)
        assertTrue(rec.needsGlass)
    }

    @Test
    fun fiveStopsHotIsND32() {
        val rec = NDFilterRecommendation.suggestion(5.0)
        assertEquals(5, rec.ndStops)
        assertEquals("ND32", rec.ndLabel)
        assertEquals("+5.0", rec.stopsLabel)
    }

    @Test
    fun twoPointThreeRoundsToND4() {
        val rec = NDFilterRecommendation.suggestion(2.3)
        assertEquals(2, rec.ndStops)
        assertEquals("ND4", rec.ndLabel)
        assertEquals("+2.3", rec.stopsLabel)
    }

    @Test
    fun halfStopRoundsUpToND2() {
        val rec = NDFilterRecommendation.suggestion(0.5)
        assertEquals(1, rec.ndStops)
        assertEquals("ND2", rec.ndLabel)
    }

    @Test
    fun underExposureDoesNotSuggestND() {
        val rec = NDFilterRecommendation.suggestion(-1.5)
        assertEquals(0, rec.ndStops)
        assertEquals("—", rec.ndLabel)
        assertEquals("−1.5", rec.stopsLabel)
        assertFalse(rec.needsGlass)
    }

    @Test
    fun tenStopCapIsND1000NotND1024() {
        val rec = NDFilterRecommendation.suggestion(12.0)
        assertEquals(10, rec.ndStops)
        assertEquals(1_000, rec.opticalFactor)
        assertEquals("ND1000", rec.ndLabel)
    }

    @Test
    fun histogramMedianMapsToPictureStops() {
        val gray = (MonitorTransfer.DLOG.middleGrayEncoded * 255).roundToInt()
        val bins = IntArray(256)
        bins[gray] = 1_000
        val rec = NDFilterRecommendation.reading(bins, MonitorTransfer.DLOG)
        assertTrue(rec != null)
        assertTrue(abs(rec!!.pictureStops) < 0.15)
        assertEquals(0, rec.ndStops)
    }

    @Test
    fun emptyHistogramIsNotAMeter() {
        assertNull(NDFilterRecommendation.reading(IntArray(256), MonitorTransfer.DLOG2))
        assertNull(NDFilterRecommendation.reading(IntArray(0), MonitorTransfer.REC709))
    }

    @Test
    fun labelsFollowTheOpticalLadder() {
        assertEquals("—", NDFilterRecommendation.ndLabel(0))
        assertEquals("ND2", NDFilterRecommendation.ndLabel(1))
        assertEquals("ND8", NDFilterRecommendation.ndLabel(3))
        assertEquals("ND32", NDFilterRecommendation.ndLabel(5))
        assertEquals("ND1000", NDFilterRecommendation.ndLabel(10))
        assertEquals("0.0", NDFilterRecommendation.stopsLabel(0.0))
        assertEquals("+2.3", NDFilterRecommendation.stopsLabel(2.3))
        assertEquals("−1.0", NDFilterRecommendation.stopsLabel(-1.0))
    }
}
