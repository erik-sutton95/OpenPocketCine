package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MonitorDrumSelectionTest {
    @Test fun releaseCommitsNearestValueAndLeftwardTravelAdvances() {
        assertEquals(4, MonitorDrumSelection.settledIndex(3f, -56f, 8))
        assertEquals(2, MonitorDrumSelection.settledIndex(3f, 56f, 8))
        assertEquals(3, MonitorDrumSelection.settledIndex(3f, -27f, 8))
        assertEquals(4, MonitorDrumSelection.settledIndex(3f, -29f, 8))
    }
    @Test fun boundedOrMissingCameraChoicesNeverProduceInvalidIndex() {
        assertNull(MonitorDrumSelection.settledIndex(0f, 100f, 0))
        assertEquals(0, MonitorDrumSelection.settledIndex(0f, 999f, 1))
        assertEquals(7, MonitorDrumSelection.settledIndex(3f, -9999f, 8))
        assertEquals(0, MonitorDrumSelection.settledIndex(Float.NaN, Float.POSITIVE_INFINITY, 8))
    }
    @Test fun elasticProjectionPreservesDetentsAndContinuousOrdering() {
        var previous = -1f
        for (step in 0..1000) {
            val value = step / 100f
            val projected = MonitorDrumSelection.projectedPosition(value)
            assertTrue(projected > previous)
            previous = projected
            if (step % 100 == 0) assertEquals(value, projected, .0001f)
        }
    }
    @Test fun catalogColumnPolicyUsesEveryApprovedSize() {
        assertEquals(listOf(3, 2, 1), MonitorThumbnailSize.entries.map { monitorCatalogColumns(it, false) })
        assertEquals(listOf(5, 4, 2), MonitorThumbnailSize.entries.map { monitorCatalogColumns(it, true) })
    }
}
