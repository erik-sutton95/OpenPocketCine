package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NDFilterRecommendationTest {
    /** A null field is not asserted for that case. */
    private data class SuggestionCase(
        val why: String,
        val pictureStops: Double,
        val ndStops: Int,
        val ndLabel: String,
        val stopsLabel: String? = null,
        val needsGlass: Boolean? = null,
        val opticalFactor: Int? = null,
    )

    @Test
    fun suggestionRoundsHotStopsOntoTheOpticalLadder() {
        val none = "\u2014"
        val cases = listOf(
            SuggestionCase("middle gray needs no glass", 0.0, 0, none, "0.0", needsGlass = false),
            SuggestionCase("two stops hot is ND4", 2.0, 2, "ND4", "+2.0", needsGlass = true, opticalFactor = 4),
            SuggestionCase("five stops hot is ND32", 5.0, 5, "ND32", "+5.0"),
            SuggestionCase("2.3 rounds to ND4", 2.3, 2, "ND4", "+2.3"),
            SuggestionCase("half stop rounds up to ND2", 0.5, 1, "ND2"),
            SuggestionCase("under exposure does not suggest ND", -1.5, 0, none, "−1.5", needsGlass = false),
            SuggestionCase("ten stop cap is ND1000 not ND1024", 12.0, 10, "ND1000", opticalFactor = 1_000),
        )
        for (case in cases) {
            val rec = NDFilterRecommendation.suggestion(case.pictureStops)
            assertEquals(case.ndStops, rec.ndStops, case.why)
            assertEquals(case.ndLabel, rec.ndLabel, case.why)
            case.stopsLabel?.let { assertEquals(it, rec.stopsLabel, case.why) }
            case.needsGlass?.let { assertEquals(it, rec.needsGlass, case.why) }
            case.opticalFactor?.let { assertEquals(it, rec.opticalFactor, case.why) }
        }
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

    @Test
    fun densityIsThreeTenthsPerStop() {
        assertEquals("ND 0.0", NDFilterRecommendation.densityLabel(0.0))
        assertEquals("ND 0.3", NDFilterRecommendation.densityLabel(1.0))
        assertEquals("ND 0.4", NDFilterRecommendation.densityLabel(4.0 / 3.0))
        assertEquals("ND 1.5", NDFilterRecommendation.densityLabel(5.0))
        assertEquals("ND −0.3", NDFilterRecommendation.densityLabel(-1.0))
    }

    @Test
    fun chipLabelFollowsNotation() {
        val hot = NDFilterRecommendation.suggestion(5.0)
        assertEquals("+5.0", hot.chipLabel(NDFilterNotation.STOPS))
        assertEquals("ND32", hot.chipLabel(NDFilterNotation.FACTOR))
        assertEquals("ND 1.5", hot.chipLabel(NDFilterNotation.DENSITY))
        val tiffen = NDFilterRecommendation.suggestion(4.0 / 3.0)
        assertEquals("ND 0.4", tiffen.chipLabel(NDFilterNotation.DENSITY))
        assertEquals("ND2", tiffen.chipLabel(NDFilterNotation.FACTOR))
        val under = NDFilterRecommendation.suggestion(-1.5)
        assertEquals("—", under.chipLabel(NDFilterNotation.FACTOR))
        assertEquals("−1.5", under.chipLabel(NDFilterNotation.STOPS))
        assertEquals("Stops", NDFilterNotation.STOPS.editorLabel)
        assertEquals("ND32", NDFilterNotation.FACTOR.editorLabel)
        assertEquals("ND 0.3", NDFilterNotation.DENSITY.editorLabel)
        assertEquals(NDFilterNotation.FACTOR, NDFilterNotation.fromPersisted("factor"))
        assertEquals(NDFilterNotation.DENSITY, NDFilterNotation.fromEditorLabel("ND 0.3"))
    }
}
