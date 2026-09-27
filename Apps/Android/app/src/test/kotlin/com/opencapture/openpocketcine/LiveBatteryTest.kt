package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Pins the live battery outline to iOS `LiveBatteryRow` (26×15, min-scale 0.65). */
class LiveBatteryTest {
    @Test
    fun readoutScalesToTheCellAndFloorsAtIosMinimum() {
        // (name, contentWidth, contentHeight, expected scale) into a 22x13 cell.
        val cases = listOf(
            Triple("three-digit readout scales to the cell", 32 to 14, 22f / 32f),
            Triple("already fitting readout stays identity", 18 to 10, 1f),
            Triple("extreme overflow floors at iOS minimum", 80 to 20, 0.65f),
        )
        for ((name, content, expected) in cases) {
            val scale = scaleToFitFactor(content.first, content.second, 22, 13)
            assertEquals(expected, scale, 0.001f, name)
            assertTrue(scale in 0.65f..1f, name)
        }
    }
}
