package com.opencapture.openpocketcine.settings

import androidx.compose.ui.graphics.Color
import com.opencapture.opencine.media.MonitorPeakingColor
import com.opencapture.opencine.media.MonitorZebraPaint
import com.opencapture.openpocketcine.LiveDesign
import org.junit.Assert.assertEquals
import org.junit.Test

/** Kept fix: a colour dot shows what its overlay paints, never the app accent under another colour's name. */
class SettingsPaletteTest {
    private fun paint(rgb: Triple<Double, Double, Double>) =
        Color(rgb.first.toFloat(), rgb.second.toFloat(), rgb.third.toFloat())

    @Test
    fun namedDotsShowTheirPaint() {
        val midtone = SettingsPalette.midtone.associate { it.name to it.color }
        assertEquals(paint(MonitorZebraPaint.CYAN.rgb), midtone.getValue("Cyan"))
        assertEquals(LiveDesign.amber, midtone.getValue("Amber"))
        assertEquals(LiveDesign.amber, SettingsPalette.highlight.single { it.name == "Amber" }.color)
        assertEquals(paint(MonitorPeakingColor.BLUE.rgb), SettingsPalette.peaking.single { it.name == "Blue" }.color)
    }
}
