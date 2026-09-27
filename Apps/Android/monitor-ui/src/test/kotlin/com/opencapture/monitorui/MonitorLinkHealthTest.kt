package com.opencapture.monitorui

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
        for ((score, band) in listOf(
            49 to MonitorLinkHealth.Band.POOR,
            50 to MonitorLinkHealth.Band.WATCH,
            79 to MonitorLinkHealth.Band.WATCH,
            80 to MonitorLinkHealth.Band.STABLE,
            MonitorLinkHealth.score(1) to MonitorLinkHealth.Band.POOR,
            MonitorLinkHealth.score(2) to MonitorLinkHealth.Band.WATCH,
            MonitorLinkHealth.score(3) to MonitorLinkHealth.Band.WATCH,
            MonitorLinkHealth.score(4) to MonitorLinkHealth.Band.STABLE,
        )) assertEquals(band, MonitorLinkHealth.band(score), "band($score)")
        for ((score, color) in listOf(
            49 to MonitorLinkHealth.poor,
            50 to MonitorLinkHealth.watch,
            75 to MonitorLinkHealth.watch,
            80 to MonitorLinkHealth.stable,
            100 to MonitorLinkHealth.stable,
        )) assertEquals(color, MonitorLinkHealth.color(score), "color($score)")
    }
}
