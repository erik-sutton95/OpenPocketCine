package com.opencapture.openpocketcine

import com.opencapture.opencine.media.MonitorNDFilterRecommendation
import com.opencapture.opencine.media.FrameRateSampler
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.media.MonitorLUTExposureCompensation
import com.opencapture.opencine.vocabulary.MediaLibraryQuery
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Operator readouts are a fixed notation, not prose: the decimal point is part of
 * the iOS parity contract and a `YYYYMMDD` key is an identifier. A comma default
 * locale must not reach either. CI runs on `en-US`, so only an explicit swap of
 * `Locale.getDefault()` can catch a bare `String.format` regression.
 */
class LocaleIndependentFormattingTest {
    private fun <T> underCommaLocale(body: () -> T): T {
        val previous = Locale.getDefault()
        Locale.setDefault(Locale.GERMANY)
        try {
            return body()
        } finally {
            Locale.setDefault(previous)
        }
    }

    @Test
    fun zoomLabelKeepsTheDecimalPoint() {
        assertEquals("2.3×", underCommaLocale { CamFov.displayLabel(2.29) })
        assertEquals("5.4×", underCommaLocale { CamFov.displayLabel(5.36) })
    }

    @Test
    fun ndLabelsKeepTheDecimalPoint() {
        assertEquals("+2.0", underCommaLocale { MonitorNDFilterRecommendation.stopsLabel(2.0, "\u2014") })
        assertEquals("−1.5", underCommaLocale { MonitorNDFilterRecommendation.stopsLabel(-1.5, "\u2014") })
        assertEquals("ND 1.5", underCommaLocale { MonitorNDFilterRecommendation.densityLabel(5.0, "\u2014") })
    }

    @Test
    fun lutExposureLabelKeepsTheDecimalPoint() {
        assertEquals("+1.5", underCommaLocale { MonitorLUTExposureCompensation.label(1.5) })
        assertEquals("−2.0", underCommaLocale { MonitorLUTExposureCompensation.label(-2.0) })
    }

    @Test
    fun frameRateReadoutKeepsTheDecimalPoint() {
        val sampler = FrameRateSampler()
        sampler.recordFrameRate(59.94)
        assertEquals("59.94", underCommaLocale { sampler.formatted })
    }

    /** A localized zero digit would corrupt the grouping key, not just its look. */
    @Test
    fun mediaDateKeyStaysAsciiDigits() {
        val key = underCommaLocale { MediaLibraryQuery.dateKeyFromMillis(1_757_548_800_000L) }
        assertEquals("20250911", key)
        assertEquals(8, key.count { it in '0'..'9' })
    }
}
