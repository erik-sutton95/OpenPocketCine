package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorDialHapticTest {
    @Test
    fun coarseDrumsTickEveryNeighbor() {
        assertTrue(MonitorDialHaptic.shouldTick("172°", "180°", 15))
        assertTrue(MonitorDialHaptic.shouldTick("144°", "172°", 15))
        assertFalse(MonitorDialHaptic.shouldTick("180°", "180°", 15))
    }

    @Test
    fun denseKelvinOnlyTicksRoundStops() {
        assertTrue(MonitorDialHaptic.shouldTick("5500K", "5600K", 81))
        assertFalse(MonitorDialHaptic.shouldTick("5500K", "5700K", 81))
        assertTrue(MonitorDialHaptic.isMajor("3200K"))
        assertFalse(MonitorDialHaptic.isMajor("3300K"))
    }

    @Test
    fun zoomHundredthsStaySilentUntilAWholeStop() {
        val stops = MonitorZoomScale.wholeStops
        assertFalse(MonitorDialHaptic.shouldTick(1.00, 1.01, stops))
        assertTrue(MonitorDialHaptic.shouldTick(2.97, 3.00, stops))
        assertTrue(MonitorDialHaptic.shouldTick(5.8, 6.1, stops))
        assertTrue(MonitorDialHaptic.shouldTick(5.5, 6.0, stops))
        assertFalse(MonitorDialHaptic.shouldTick(5.0, 5.5, stops))
        assertFalse(MonitorDialHaptic.shouldTick(4.9, 5.0, stops))
    }

    @Test
    fun durationTicksWholeSecondsOnly() {
        assertTrue(MonitorDialHaptic.shouldTick(1.5, 2.0))
        assertFalse(MonitorDialHaptic.shouldTick(1.0, 1.5))
        assertTrue(MonitorDialHaptic.shouldTick(4.5, 5.0))
    }

    @Test
    fun denseShutterSpeedOnlyTicksRoundDenoms() {
        assertTrue(MonitorDialHaptic.shouldTick("1/49", "1/50", 40))
        assertFalse(MonitorDialHaptic.shouldTick("1/47", "1/49", 40))
        assertTrue(MonitorDialHaptic.isMajor("1/48"))
        assertFalse(MonitorDialHaptic.isMajor("1/47"))
    }
}
