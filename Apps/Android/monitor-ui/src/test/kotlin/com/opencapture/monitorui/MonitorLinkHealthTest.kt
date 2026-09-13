package com.opencapture.monitorui

import androidx.compose.ui.graphics.Color
import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorLinkHealthTest {
    @Test fun scoreIsClampedBarsTimes25() {
        assertEquals(0, MonitorLinkHealth.score(0))
        assertEquals(25, MonitorLinkHealth.score(1))
        assertEquals(50, MonitorLinkHealth.score(2))
        assertEquals(75, MonitorLinkHealth.score(3))
        assertEquals(100, MonitorLinkHealth.score(4))
        assertEquals(0, MonitorLinkHealth.score(-2))
        assertEquals(100, MonitorLinkHealth.score(9))
    }

    @Test fun bandsSplitAt50And80() {
        assertEquals(MonitorLinkHealth.Band.POOR, MonitorLinkHealth.band(49))
        assertEquals(MonitorLinkHealth.Band.WATCH, MonitorLinkHealth.band(50))
        assertEquals(MonitorLinkHealth.Band.WATCH, MonitorLinkHealth.band(79))
        assertEquals(MonitorLinkHealth.Band.STABLE, MonitorLinkHealth.band(80))
        assertEquals(MonitorLinkHealth.Band.POOR, MonitorLinkHealth.band(MonitorLinkHealth.score(1)))
        assertEquals(MonitorLinkHealth.Band.WATCH, MonitorLinkHealth.band(MonitorLinkHealth.score(2)))
        assertEquals(MonitorLinkHealth.Band.WATCH, MonitorLinkHealth.band(MonitorLinkHealth.score(3)))
        assertEquals(MonitorLinkHealth.Band.STABLE, MonitorLinkHealth.band(MonitorLinkHealth.score(4)))
    }

    @Test fun paletteMatchesDashScaleBands() {
        assertEquals(Color(0.18f, 0.78f, 0.42f), MonitorLinkHealth.stable)
        assertEquals(Color(0.96f, 0.52f, 0.12f), MonitorLinkHealth.watch)
        assertEquals(MonitorPalette.recording, MonitorLinkHealth.poor)
        assertEquals(MonitorLinkHealth.poor, MonitorLinkHealth.color(49))
        assertEquals(MonitorLinkHealth.watch, MonitorLinkHealth.color(50))
        assertEquals(MonitorLinkHealth.watch, MonitorLinkHealth.color(75))
        assertEquals(MonitorLinkHealth.stable, MonitorLinkHealth.color(80))
        assertEquals(MonitorLinkHealth.stable, MonitorLinkHealth.color(100))
    }
}
