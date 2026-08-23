package com.opencapture.openpocketcine.lut

import kotlin.test.Test
import kotlin.test.assertEquals

class LutPickerMetricsTest {
    @Test
    fun landscapeDrumIsFifteenPercentTallerThanIOS() {
        assertEquals(168f, LutPickerMetrics.CONTENT_DP)
        assertEquals(28f, LutPickerMetrics.CAPTION_DP)
        assertEquals(52f, LutPickerMetrics.ROW_DP)
        assertEquals(4f, LutPickerMetrics.WHEEL_GAP_DP)
        assertEquals(136f, LutPickerMetrics.WHEEL_DP)
        assertEquals(0.12f, LutPickerMetrics.FADE_IN)
        assertEquals(0.88f, LutPickerMetrics.FADE_OUT)
        assertEquals(27f, LutPickerMetrics.CENTER_PT)
        assertEquals(20f, LutPickerMetrics.NEIGHBOR_PT)
        assertEquals(11f, LutPickerMetrics.SPLIT_TYPE_PT)
        assertEquals(13f, LutPickerMetrics.SPLIT_ICON_DP)
        assertEquals(27f, LutPickerMetrics.CLOSE_DP)
        val edge = (LutPickerMetrics.WHEEL_DP - LutPickerMetrics.ROW_DP) / 2f
        assertEquals(42f, edge)
    }
}
