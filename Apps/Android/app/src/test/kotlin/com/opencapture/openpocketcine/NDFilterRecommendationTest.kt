package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.LiveColorScience
import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NDFilterRecommendationTest {
    @Test
    fun oneEightyAtNativeNeedsNoGlass() {
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            ),
        )
    }

    @Test
    fun fourStopsOfShutterIsND16() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 768,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        assertEquals(4, rec?.stops)
        assertEquals(16, rec?.opticalFactor)
        assertEquals("ND16", rec?.label)
        assertEquals("Try ND16 so 180° holds", rec?.line)
    }

    @Test
    fun fiveStopsOfShutterIsND32() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 1_536,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        assertEquals(5, rec?.stops)
        assertEquals("ND32", rec?.label)
        assertEquals("Try ND32 so 180° holds", rec?.line)
    }

    @Test
    fun twoThousandthsRoundsToNearestStop() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 2_000,
                fps = 24,
                iso = 1_600,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG2,
            )
        assertEquals(5, rec?.stops)
        assertEquals("ND32", rec?.label)
    }

    @Test
    fun isoAboveNativeAddsStops() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 1_600,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        assertEquals(2, rec?.stops)
        assertEquals("ND4", rec?.label)
    }

    @Test
    fun rec709IgnoresISOWhenThereIsNoNative() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 384,
                fps = 24,
                iso = 6_400,
                isoIsAuto = false,
                transfer = MonitorTransfer.REC709,
            )
        assertEquals(3, rec?.stops)
        assertEquals("ND8", rec?.label)
    }

    @Test
    fun autoExpoNeverSuggests() {
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = false,
                shutterDenom = 2_000,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            ),
        )
    }

    @Test
    fun autoISODoesNotCountSensitivity() {
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 6_400,
                isoIsAuto = true,
                transfer = MonitorTransfer.DLOG,
            ),
        )
    }

    @Test
    fun twentyFiveFpsUsesOneFiftieth() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 400,
                fps = 25,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        assertEquals(3, rec?.stops)
        assertEquals("ND8", rec?.label)
    }

    @Test
    fun pictureOverexposureAddsStops() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
                pictureStops = 2.0,
            )
        assertEquals(2, rec?.stops)
        assertEquals("ND4", rec?.label)
    }

    @Test
    fun pictureDeadbandDoesNotNudge() {
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
                pictureStops = 0.3,
            ),
        )
    }

    @Test
    fun underexposedFastShutterNeedsLessND() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 768,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
                pictureStops = -2.0,
            )
        assertEquals(2, rec?.stops)
        assertEquals("ND4", rec?.label)
    }

    @Test
    fun tenStopCapIsND1000NotND1024() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 16_000,
                fps = 24,
                iso = 25_600,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        assertEquals(10, rec?.stops)
        assertEquals(1_000, rec?.opticalFactor)
        assertEquals("ND1000", rec?.label)
        assertEquals("Try ND1000 so 180° holds", rec?.line)
    }

    @Test
    fun halfStopRoundsUpToND2() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 48,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
                pictureStops = 0.5,
            )
        assertEquals(1, rec?.stops)
        assertEquals("ND2", rec?.label)
    }

    @Test
    fun missingShutterOrFpsIsSilent() {
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = -1,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            ),
        )
        assertNull(
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 2_000,
                fps = 0,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            ),
        )
    }

    @Test
    fun copyIsASuggestionNotASET() {
        val rec =
            NDFilterRecommendation.suggest(
                expoIsManual = true,
                shutterDenom = 384,
                fps = 24,
                iso = 400,
                isoIsAuto = false,
                transfer = MonitorTransfer.DLOG,
            )
        val line = requireNotNull(rec).line
        assertEquals(true, line.startsWith("Try "))
        assertEquals(false, line.contains("set", ignoreCase = true))
    }

    @Test
    fun histogramMedianMapsToPictureStops() {
        val gray = (MonitorTransfer.DLOG.middleGrayEncoded * 255).roundToInt()
        val bins = IntArray(256)
        bins[gray] = 1_000
        val stops = requireNotNull(
            NDFilterRecommendation.pictureStops(bins, MonitorTransfer.DLOG),
        )
        assertTrue(abs(stops) < 0.15)

        val plusTwo = LiveColorScience.encode(0.18 * 4, MonitorTransfer.DLOG)
        val hot = IntArray(256)
        hot[(plusTwo * 255).roundToInt().coerceIn(0, 255)] = 1_000
        val over = requireNotNull(
            NDFilterRecommendation.pictureStops(hot, MonitorTransfer.DLOG),
        )
        assertTrue(abs(over - 2) < 0.15)
    }

    @Test
    fun emptyHistogramIsNotAMeter() {
        assertNull(NDFilterRecommendation.pictureStops(IntArray(256), MonitorTransfer.DLOG2))
        assertNull(NDFilterRecommendation.pictureStops(IntArray(0), MonitorTransfer.REC709))
    }

    @Test
    fun labelsFollowTheOpticalLadder() {
        assertEquals("ND2", NDFilterRecommendation.label(1))
        assertEquals("ND8", NDFilterRecommendation.label(3))
        assertEquals("ND32", NDFilterRecommendation.label(5))
        assertEquals("ND1000", NDFilterRecommendation.label(10))
        assertEquals(1_000, NDFilterRecommendation.opticalFactor(10))
    }
}
