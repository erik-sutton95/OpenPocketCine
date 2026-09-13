package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorDurationDialTest {
    @Test fun stepsHalfSecondsInsideTheInjectedRange() {
        val range = MonitorDurationDialMetrics.MIN..MonitorDurationDialMetrics.MAX
        assertEquals(5.5, MonitorDurationDialMetrics.afterDrag(5.0, -12f, range))
        assertEquals(4.5, MonitorDurationDialMetrics.afterDrag(5.0, 12f, range))
        assertEquals(0.5, MonitorDurationDialMetrics.afterDrag(5.0, 1000f, range))
        assertEquals(120.0, MonitorDurationDialMetrics.afterDrag(5.0, -4000f, range))
        assertEquals(180f, MonitorDurationDialMetrics.WIDTH)
        assertEquals(44f, MonitorDurationDialMetrics.HEIGHT)
        assertEquals(0.5, MonitorDurationDialMetrics.STEP)
    }

    @Test fun snapHonorsARaisedFloorWithoutAnIdleClock() {
        assertEquals(3.0, MonitorDurationDialMetrics.snap(2.4, 3.0..120.0))
        assertEquals("5s", MonitorDurationDialMetrics.label(5.0))
        assertEquals("5.5s", MonitorDurationDialMetrics.label(5.5))
    }

    @Test fun staleGenerationDoesNotCommit() {
        assertEquals(true, MonitorDurationDialMetrics.accept(3, 3, true))
        assertEquals(false, MonitorDurationDialMetrics.accept(3, 4, true))
        assertEquals(false, MonitorDurationDialMetrics.accept(4, 4, false))
    }

    @Test fun invalidInputsAndZeroSpanStayFiniteAndAccessible() {
        val fixed = MonitorDurationDialMetrics.Scale(4.0..4.0, 0.0)
        assertEquals(0, fixed.accessibilitySteps)
        assertEquals(4.0, fixed.snap(Double.NaN))
        assertEquals(0f, fixed.position(Double.POSITIVE_INFINITY))
        val reversed = MonitorDurationDialMetrics.Scale(6.0..2.0, Double.NaN)
        assertEquals(2.0..6.0, reversed.range)
        assertEquals(0.5, reversed.step)
        val invalid = MonitorDurationDialMetrics.Scale(Double.NaN..Double.POSITIVE_INFINITY, -1.0)
        assertEquals(0.5..120.0, invalid.range)
        assertEquals(5.0, MonitorDurationDialMetrics.afterDrag(5.0, Float.NaN))
        assertEquals(3.5, MonitorDurationDialMetrics.snap(3.32, 3.25..10.25))
    }
}
