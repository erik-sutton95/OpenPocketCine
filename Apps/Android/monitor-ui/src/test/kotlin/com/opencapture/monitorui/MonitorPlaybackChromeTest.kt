package com.opencapture.monitorui

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

class MonitorPlaybackChromeTest {
    @Test fun narrowLandscapeKeepsTransportClearOfTrailingOptions() {
        for (width in listOf(370f, 400f, 500f, 630f, 860f)) {
            val start = MonitorPlaybackLayout.transportStart(width)
            val transportEnd = start + MonitorPlaybackLayout.transportWidth
            val optionsStart = width - MonitorPlaybackLayout.actionsWidth
            assertTrue("Transport stays on screen at $width", start >= 0f)
            assertTrue("Transport and options must not overlap at $width",
                transportEnd + MonitorPlaybackLayout.FOOTER_GAP <= optionsStart)
        }
    }

    @Test fun wideLandscapeCentersTransport() {
        val width = 630f
        assertEquals(width / 2f,
            MonitorPlaybackLayout.transportStart(width) + MonitorPlaybackLayout.transportWidth / 2f, 0.01f)
    }
}
