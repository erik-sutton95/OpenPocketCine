package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.LevelMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LiveLevelOverlayTest {
    private fun ChromeRect.inside(o: ChromeRect) = minX >= o.minX && maxX <= o.maxX && minY >= o.minY && maxY <= o.maxY

    @Test
    fun evStripsStayOnTheVisibleFeedWithTiltMirroredOntoTheRight() {
        val viewport = ChromeRect(0f, 0f, 390f, 844f)
        for ((feed, portrait) in listOf(
            ChromeRect(0f, 0f, 844f, 390f) to false,
            ChromeRect(-200f, 120f, 790f, 444f) to true,
            ChromeRect(0f, 200f, 390f, 219f) to true,
        )) {
            val visible = LiveLevel.visible(feed, viewport)
            val frames = LiveLevel.frames(feed, viewport, portrait)
            val ev = assertNotNull(CameraExposureMeter.frame(visible, PocketDispMode.LIVE))
            assertTrue(frames.roll.inside(visible), "$feed")
            val tilt = assertNotNull(frames.tilt)
            assertEquals(visible.maxX - 6f, tilt.maxX, "mirrors EV onto the right edge")
            assertEquals(ev.y, tilt.y)
            assertEquals(ev.height, tilt.height)
            assertEquals(LiveLevel.THICKNESS, frames.roll.height)
            assertEquals(visible.midX, frames.roll.midX)
            assertEquals(visible.maxY - if (portrait) 30f else 104f, frames.roll.midY)
            // Joystick cluster in the lower right: move up before shortening.
            val cluster = ChromeRect(visible.maxX - 120f, visible.midY, 110f, visible.maxY - visible.midY)
            LiveLevel.frames(feed, viewport, portrait, cluster).tilt?.let { clear ->
                assertTrue(clear.maxY <= cluster.minY - 12f, "$feed")
                assertEquals(visible.maxX - 6f, clear.maxX)
            }
        }
    }

    @Test
    fun labelsMatchTheEvMeter() {
        assertEquals("—", LiveLevel.label(null))
        assertEquals("+0.0°", LiveLevel.label(0.04))
        assertEquals("-2.4°", LiveLevel.label(-2.35))
        assertEquals("Level, No level data", LiveLevel.accessibilityLabel(LevelMode.Unavailable))
        assertEquals("Level, roll +1.5°, tilt -0.3°", LiveLevel.accessibilityLabel(LevelMode.Gauges(1.5, -0.3)))
    }
}
