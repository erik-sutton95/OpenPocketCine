package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.lut.LutExposureCompensation
import com.opencapture.openpocketcine.media.MediaLibraryQuery
import com.opencapture.openpocketcine.session.CamFov
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
        assertEquals("+2.0", underCommaLocale { NDFilterRecommendation.stopsLabel(2.0) })
        assertEquals("−1.5", underCommaLocale { NDFilterRecommendation.stopsLabel(-1.5) })
        assertEquals("ND 1.5", underCommaLocale { NDFilterRecommendation.densityLabel(5.0) })
    }

    @Test
    fun lutExposureLabelKeepsTheDecimalPoint() {
        assertEquals("+1.5", underCommaLocale { LutExposureCompensation.label(1.5) })
        assertEquals("−2.0", underCommaLocale { LutExposureCompensation.label(-2.0) })
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
