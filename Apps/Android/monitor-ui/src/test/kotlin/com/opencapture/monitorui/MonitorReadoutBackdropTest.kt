package com.opencapture.monitorui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MonitorReadoutBackdropTest {
    @Test fun complementRoutesEveryPointToEitherItsOriginalReadoutOrOneDismissRegion() {
        val viewport = Rect(10f, 20f, 210f, 180f)
        val holes = listOf(Rect(0f, 30f, 90f, 60f), Rect(70f, 40f, 150f, 80f),
            Rect(100f, 130f, 180f, 200f), Rect(300f, 300f, 400f, 400f))
        val pieces = monitorDismissRegions(viewport, holes)
        // Sample interior points, including overlapping holes and clipped edges.
        for (x in 10 until 210) for (y in 20 until 180) {
            val point = Offset(x + .5f, y + .5f)
            val inReadout = holes.any { it.contains(point) }
            assertEquals(if (inReadout) 0 else 1, pieces.count { it.contains(point) }, "$point")
        }
        assertTrue(pieces.all { it.left >= viewport.left && it.top >= viewport.top &&
            it.right <= viewport.right && it.bottom <= viewport.bottom })
    }

    @Test fun emptyAndFullyCoveredViewportsHaveNoAccidentalInputRegions() {
        val viewport = Rect(0f, 0f, 100f, 100f)
        assertEquals(listOf(viewport), monitorDismissRegions(viewport, emptyList()))
        assertTrue(monitorDismissRegions(viewport, listOf(viewport)).isEmpty())
        assertTrue(monitorDismissRegions(Rect.Zero, emptyList()).isEmpty())
    }

    @Test fun removedOrMovedReadoutCannotLeaveAStaleHoleOrRemoveAnotherOwner() {
        val regions = MonitorReadoutRegions()
        val old = Any()
        val new = Any()
        val before = Rect(10f, 10f, 80f, 50f)
        val after = Rect(20f, 100f, 90f, 140f)
        regions.update(old, before)
        regions.update(new, after)
        regions.update(old, null)
        assertEquals(listOf(after), regions.snapshot())
        regions.update(new, before)
        assertEquals(listOf(before), regions.snapshot())
        regions.update(new, null)
        assertTrue(regions.snapshot().isEmpty())
    }

}
