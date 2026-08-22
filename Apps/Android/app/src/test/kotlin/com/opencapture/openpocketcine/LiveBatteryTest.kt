package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Pins the live battery outline to iOS `LiveBatteryRow` (26×15, min-scale 0.65). */
class LiveBatteryTest {
    @Test
    fun cellMatchesIosPill() {
        assertEquals(26f, BATTERY_CELL_W_DP)
        assertEquals(15f, BATTERY_CELL_H_DP)
    }

    @Test
    fun threeDigitReadoutScalesToTheCell() {
        val scale = scaleToFitFactor(contentWidth = 32, contentHeight = 14, maxWidth = 22, maxHeight = 13)
        assertTrue(scale < 1f)
        assertTrue(scale >= 0.65f)
        assertEquals(22f / 32f, scale, 0.001f)
    }

    @Test
    fun alreadyFittingReadoutStaysIdentity() {
        assertEquals(1f, scaleToFitFactor(18, 10, 22, 13))
    }

    @Test
    fun extremeOverflowFloorsAtIosMinimumScale() {
        assertEquals(0.65f, scaleToFitFactor(80, 20, 22, 13))
    }
}
