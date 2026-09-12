package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorAssistUsageTest {
    @Test fun equalScoresKeepCatalogOrderAndUnseenToolsStartAtZero() {
        assertEquals(listOf("peak", "false", "lut", "zebra", "extension"),
            MonitorAssistUsage.ranked(listOf("lut", "peak", "false", "zebra", "extension"),
                mapOf("peak" to 6, "false" to 5, "lut" to 4, "zebra" to 4)))
    }

    @Test fun actionsIncrementTheirBaselineWithoutChangingUnrelatedScores() {
        val seed = mapOf("peak" to 6, "false" to 5, "wave" to 3)
        var counts = seed
        repeat(4) { counts = MonitorAssistUsage.recording("wave", counts) }
        assertEquals(listOf("wave", "peak", "false"), MonitorAssistUsage.ranked(listOf("peak", "false", "wave"), counts))
        assertEquals(6, counts["peak"])
        assertEquals(3, seed["wave"])
    }
}
