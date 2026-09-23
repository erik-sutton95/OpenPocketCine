package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.LevelMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LiveLevelOverlayTest {
    @Test
    fun gaugeSeatsStayOnTheVisibleFeed() {
        val viewport = ChromeRect(0f, 0f, 390f, 844f)
        for ((feed, portrait) in listOf(
            ChromeRect(0f, 0f, 844f, 390f) to false,
            ChromeRect(-200f, 120f, 790f, 444f) to true,
            ChromeRect(0f, 200f, 390f, 219f) to true,
        )) {
            val seats = LiveLevel.seats(feed, viewport, portrait)
            val visible = LiveLevel.visible(feed, viewport)
            assertTrue(visible.contains(seats.roll.first, seats.roll.second), "$feed")
            assertTrue(visible.contains(seats.tilt.first, seats.tilt.second), "$feed")
            assertEquals(visible.midX, seats.roll.first)
            assertEquals(visible.maxX - 44f, seats.tilt.first)
            assertEquals(visible.maxY - if (portrait) 30f else 104f, seats.roll.second)
        }
    }

    @Test
    fun accessibilityNamesTheMissingDataState() {
        assertEquals("Level, No level data", LiveLevel.accessibilityLabel(LevelMode.Unavailable))
        assertEquals("Level, roll +1.5°, tilt -0.3°", LiveLevel.accessibilityLabel(LevelMode.Gauges(1.5, -0.3)))
    }
}
