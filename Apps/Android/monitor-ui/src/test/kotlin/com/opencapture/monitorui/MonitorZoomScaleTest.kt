package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorZoomScaleTest {
    @Test fun dialTicksAndLabelsUseHundredths() {
        assertEquals(1.53, MonitorZoomScale.quantized(1.534, maximum = 12.0), 1e-9)
        assertEquals(1.54, MonitorZoomScale.quantized(1.536, maximum = 12.0), 1e-9)
        assertEquals("1.53×", MonitorZoomScale.dialLabel(1.534, maximum = 12.0))
        assertEquals("1.00×", MonitorZoomScale.dialLabel(1.0, maximum = 12.0))
        assertTrue(MonitorZoomScale.isLabeledTick(1.5, maximum = 12.0))
        assertTrue(MonitorZoomScale.isLabeledTick(1.50, maximum = 12.0))
        assertFalse(MonitorZoomScale.isLabeledTick(1.53, maximum = 12.0))
        val ticks = MonitorZoomScale.minorTickPositions()
        assertEquals(19, ticks.size)
        assertEquals(0.0, ticks.first(), 1e-9)
        assertEquals(1.0, ticks.last(), 1e-9)
        assertEquals(ticks[1] - ticks[0], ticks[2] - ticks[1], 1e-9)
    }

    @Test fun continuousLogarithmicInputPreservesSmallStepsAcrossWholeStops() {
        for (stop in MonitorZoomScale.wholeStops.filter { it > 1.0 && it < 12.0 }) {
            val requested = (-20..20).map { stop + it * 0.0007 }
            val delivered = requested.map { value ->
                MonitorZoomScale.valueAt(MonitorZoomScale.position(value, 1.0, 12.0), 1.0, 12.0)
            }
            requested.zip(delivered).forEach { (request, value) -> assertEquals(request, value, 1e-12) }
            delivered.zipWithNext().forEach { (first, second) -> assertEquals(0.0007, second - first, 1e-12) }
        }
        assertEquals(1.0, MonitorZoomScale.valueAt(-0.1, 1.0, 3.0))
        assertEquals(3.0, MonitorZoomScale.valueAt(1.1, 1.0, 3.0))
    }
}
