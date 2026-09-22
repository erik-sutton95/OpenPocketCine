package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.LiveColorScience
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.openpocketcine.feed.ScopeSamples
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EVMeterReadingTest {
    @Test fun grayBrighterAndDarkerPicturesReadSignedStopsAcrossTransfers() {
        for (transfer in MonitorTransfer.entries) {
            val gray = EVMeterReading.from(picture(.18, transfer))
            val bright = EVMeterReading.from(picture(.36, transfer))
            val dark = EVMeterReading.from(picture(.09, transfer))
            assertEquals(0.0, gray.stops!!, .05, transfer.name)
            assertEquals(1.0, bright.stops!!, .05, transfer.name)
            assertEquals(-1.0, dark.stops!!, .05, transfer.name)
            assertEquals("0.0", gray.label)
            assertEquals("+1.0", bright.label)
            assertEquals("−1.0", dark.label)
        }
    }

    @Test fun aSmallBrightHighlightDoesNotReplaceMedianPictureBrightness() {
        val bundle = picture(.18, MonitorTransfer.REC709)
        bundle.samples.histogramLuma[255] = 4
        assertEquals("0.0", EVMeterReading.from(bundle).label)
    }

    @Test fun noPictureBlackAndInvalidReadingsHaveNoNeedleOrFakeZero() {
        val readings = listOf(
            EVMeterReading.from(ScopeAssistBundle.EMPTY),
            EVMeterReading.from(picture(0.0, MonitorTransfer.REC709)),
            EVMeterReading(null),
            EVMeterReading(Double.NaN),
            EVMeterReading(Double.POSITIVE_INFINITY),
            EVMeterReading(Double.NEGATIVE_INFINITY),
        )
        for (reading in readings) {
            assertNull(reading.stops)
            assertNull(reading.needleFraction)
            assertEquals("—", reading.label)
            assertEquals("Exposure meter, unavailable", reading.accessibilityLabel)
        }
    }

    @Test fun needleClampsWithoutTruncatingTheNumber() {
        assertEquals(0.5f, EVMeterReading(0.0).needleFraction)
        assertEquals(0.25f, EVMeterReading(-1.5).needleFraction)
        assertEquals(0.75f, EVMeterReading(1.5).needleFraction)
        assertEquals(0f, EVMeterReading(-5.2).needleFraction)
        assertEquals(1f, EVMeterReading(6.4).needleFraction)
        assertEquals("−5.2", EVMeterReading(-5.2).label)
        assertEquals("+6.4", EVMeterReading(6.4).label)
    }

    @Test fun dLogMIsExplicitlyEstimatedInVisualAndAccessibleReadouts() {
        val estimated = EVMeterReading.from(picture(.36, MonitorTransfer.DLOGM))
        assertTrue(estimated.estimated)
        assertEquals("EV ≈", estimated.title)
        assertTrue(estimated.accessibilityLabel.contains("approximately +1.0"))
        val normal = EVMeterReading.from(picture(.36, MonitorTransfer.REC709))
        assertFalse(normal.estimated)
        assertEquals("EV", normal.title)
        assertFalse(normal.accessibilityLabel.contains("approximately"))
    }

    @Test fun sourceResetClearsThePreviousMeasurement() {
        val state = LiveAssistState()
        state.acceptScopeBundle(picture(.36, MonitorTransfer.REC709))
        assertEquals("+1.0", EVMeterReading.from(state.scopeBundle).label)
        state.acceptScopeBundle(ScopeAssistBundle.EMPTY)
        assertNull(EVMeterReading.from(state.scopeBundle).stops)
    }

    private fun picture(linear: Double, transfer: MonitorTransfer): ScopeAssistBundle {
        val code = (LiveColorScience.encode(linear, transfer) * 255.0).roundToInt()
        val luma = IntArray(256).also { it[code] = 9 }
        return ScopeAssistBundle(
            revision = 1,
            samples = ScopeSamples.EMPTY.copy(histogramLuma = luma),
            transfer = transfer,
        )
    }
}
