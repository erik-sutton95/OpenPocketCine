package com.opencapture.openpocketcine

import com.opencapture.monitorui.portraitFillCropContent
import com.opencapture.opencine.runtime.GpuLiveLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import com.opencapture.monitorui.MonitorRect

/** Pure-JVM checks of the hardware glass gate. No runtime demote. */
class GlassTierTest {
    @Test
    fun scopePlateMatchesTheGpuPanelFill() {
        assertEquals(LiveDesign.scopePlate.red, GpuLiveLayout.PANEL_FILL_R, 0.001f)
        assertEquals(LiveDesign.scopePlate.alpha, GpuLiveLayout.PANEL_FILL_A, 0.01f)
    }

    @Test
    fun portraitFillCropContentKeepsTheWellHeight() {
        val wellH = 390f * 16f / 9f
        val content = portraitFillCropContent(MonitorRect(0f, 0f, 390f, wellH))
        assertEquals(wellH.toInt(), content.height.toInt())
    }
}
