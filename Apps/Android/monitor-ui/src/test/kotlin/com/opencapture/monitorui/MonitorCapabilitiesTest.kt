package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorCapabilitiesTest {
    @Test
    fun availableControlsMatchSharedSnapshot() {
        val capability = MonitorCapabilities(zoom = true, focus = true, iris = true, audio = true)
        assertEquals(
            setOf(
                MonitorControlRole.ZOOM,
                MonitorControlRole.FOCUS,
                MonitorControlRole.IRIS,
                MonitorControlRole.AUDIO,
            ),
            capability.availableControls,
        )
        assertFalse(capability.availableControls.contains(MonitorControlRole.GIMBAL))
    }

    @Test
    fun headTrackingRequiresGimbal() {
        assertFalse(MonitorCapabilities(headTracking = true).availableControls.contains(MonitorControlRole.HEAD_TRACKING))
        assertTrue(
            MonitorCapabilities(gimbal = true, headTracking = true)
                .availableControls.contains(MonitorControlRole.HEAD_TRACKING),
        )
    }

    @Test
    fun optionalSlotsTravelWithTheSnapshot() {
        val full = MonitorCapabilities(
            gimbal = true, zoom = true, focus = true, iris = true, audio = true,
            headTracking = true, clipDelete = true, clipStar = true,
            requiresInternetHop = true, timecode = true,
        )
        assertTrue(full.clipDelete)
        assertTrue(full.clipStar)
        assertTrue(full.requiresInternetHop)
        assertTrue(full.timecode)
    }
}
