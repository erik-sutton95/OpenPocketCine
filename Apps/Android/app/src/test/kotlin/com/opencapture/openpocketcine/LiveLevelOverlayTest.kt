package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorLevelDisplay
import com.opencapture.monitorui.MonitorLevelGeometry
import com.opencapture.monitorui.MonitorScopeRect
import com.opencapture.opencine.motion.WorldLevelSnap
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The level geometry and labels the mounted shared surface draws (camera-controls MonitorOperatorLevelOverlay). */
class LiveLevelOverlayTest {
    private fun MonitorScopeRect.inside(o: MonitorScopeRect) = minX >= o.minX && maxX <= o.maxX && minY >= o.minY && maxY <= o.maxY

    @Test
    fun stripsSitEquidistantFromTheFeedCentre() {
        val viewport = MonitorScopeRect(0f, 0f, 390f, 844f)
        for ((feed, portrait) in listOf(
            MonitorScopeRect(0f, 0f, 844f, 390f) to false,
            MonitorScopeRect(-200f, 120f, 790f, 444f) to true,
            MonitorScopeRect(0f, 200f, 390f, 219f) to true,
        )) {
            val visible = MonitorLevelGeometry.visible(feed, viewport)
            val frames = MonitorLevelGeometry.frames(feed, viewport, portrait)
            assertTrue(frames.roll.inside(visible), "$feed")
            val tilt = frames.tilt
            assertTrue(tilt.inside(visible), "$feed")
            assertEquals(MonitorLevelGeometry.THICKNESS, tilt.width)
            assertEquals(visible.midY, tilt.midY, 0.001f)
            val offset = minOf(frames.roll.midY - visible.midY, visible.maxX - 6f - MonitorLevelGeometry.THICKNESS / 2f - visible.midX)
            assertEquals(offset, tilt.midX - visible.midX, 0.001f)
            assertEquals(MonitorLevelGeometry.THICKNESS, frames.roll.height)
            assertEquals(visible.midX, frames.roll.midX)
            assertEquals(visible.maxY - if (portrait) MonitorLevelGeometry.ROLL_LIFT_PORTRAIT else MonitorLevelGeometry.ROLL_LIFT_LANDSCAPE, frames.roll.midY)
        }
    }

    @Test
    fun labelsMatchTheEvMeter() {
        assertEquals("\u2014", MonitorLevelGeometry.label(null, "\u2014"))
        assertEquals("+0.0°", MonitorLevelGeometry.label(0.04))
        assertEquals("-2.4°", MonitorLevelGeometry.label(-2.35))
        assertEquals("Level, No level data",
            MonitorLevelGeometry.accessibilityLabel(MonitorLevelDisplay.Unavailable, WorldLevelSnap.NO_LEVEL_DATA))
        assertEquals("Level, roll +1.5°, tilt -0.3°",
            MonitorLevelGeometry.accessibilityLabel(MonitorLevelDisplay.Gauges(1.5, -0.3), WorldLevelSnap.NO_LEVEL_DATA))
    }
}
