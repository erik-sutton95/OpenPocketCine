package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.LevelMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LiveLevelOverlayTest {
    private fun ChromeRect.inside(o: ChromeRect) = minX >= o.minX && maxX <= o.maxX && minY >= o.minY && maxY <= o.maxY

    @Test
    fun stripsSitEquidistantFromTheFeedCentre() {
        val viewport = ChromeRect(0f, 0f, 390f, 844f)
        for ((feed, portrait) in listOf(
            ChromeRect(0f, 0f, 844f, 390f) to false,
            ChromeRect(-200f, 120f, 790f, 444f) to true,
            ChromeRect(0f, 200f, 390f, 219f) to true,
        )) {
            val visible = LiveLevel.visible(feed, viewport)
            val frames = LiveLevel.frames(feed, viewport, portrait)
            assertTrue(frames.roll.inside(visible), "$feed")
            val tilt = frames.tilt
            assertTrue(tilt.inside(visible), "$feed")
            assertEquals(LiveLevel.THICKNESS, tilt.width)
            assertEquals(visible.midY, tilt.midY, 0.001f)
            val offset = minOf(frames.roll.midY - visible.midY, visible.maxX - 6f - LiveLevel.THICKNESS / 2f - visible.midX)
            assertEquals(offset, tilt.midX - visible.midX, 0.001f)
            assertEquals(LiveLevel.THICKNESS, frames.roll.height)
            assertEquals(visible.midX, frames.roll.midX)
            assertEquals(visible.maxY - if (portrait) LiveLevel.ROLL_LIFT_PORTRAIT else LiveLevel.ROLL_LIFT_LANDSCAPE, frames.roll.midY)
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
