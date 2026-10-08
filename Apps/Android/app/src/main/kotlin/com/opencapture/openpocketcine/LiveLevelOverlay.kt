package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MonitorLevelDisplay
import com.opencapture.monitorui.MonitorLevelGeometry
import com.opencapture.monitorui.MonitorLevelOverlay
import com.opencapture.monitorui.MonitorScopeRect
import com.opencapture.opencine.motion.LevelMode
import com.opencapture.opencine.motion.LevelReading
import com.opencapture.opencine.motion.WorldLevelSnap
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.delay

/** Camera attitude sampling and the existing app-facing compatibility surface. */
internal object LiveLevel {
    const val REFRESH_MS = 100L
    const val THICKNESS = MonitorLevelGeometry.THICKNESS
    const val MAX_LENGTH = MonitorLevelGeometry.MAX_LENGTH
    const val SPAN = MonitorLevelGeometry.SPAN
    const val THRESHOLD = MonitorLevelGeometry.THRESHOLD
    const val BUBBLE_SPAN = MonitorLevelGeometry.BUBBLE_SPAN
    const val BUBBLE_RADIUS = MonitorLevelGeometry.BUBBLE_RADIUS
    const val BAND = MonitorLevelGeometry.BAND
    const val ROLL_LIFT_LANDSCAPE = MonitorLevelGeometry.ROLL_LIFT_LANDSCAPE
    const val ROLL_LIFT_PORTRAIT = MonitorLevelGeometry.ROLL_LIFT_PORTRAIT
    val good = MonitorLevelGeometry.good

    fun visible(feed: MonitorRect, viewport: MonitorRect): MonitorRect =
        MonitorLevelGeometry.visible(feed.levelRect(), viewport.levelRect()).chromeRect()

    data class Frames(val roll: MonitorRect, val tilt: MonitorRect)

    fun frames(feed: MonitorRect, viewport: MonitorRect, portrait: Boolean): Frames {
        val frames = MonitorLevelGeometry.frames(feed.levelRect(), viewport.levelRect(), portrait)
        return Frames(frames.roll.chromeRect(), frames.tilt.chromeRect())
    }

    fun label(value: Double?): String =
        if (value == null) "\u2014" else String.format(Locale.ROOT, "%+.1f°", if (abs(value) < 0.05) 0.0 else value)

    fun accessibilityLabel(mode: LevelMode): String =
        MonitorLevelGeometry.accessibilityLabel(mode.display(), WorldLevelSnap.NO_LEVEL_DATA)
}

private fun MonitorRect.levelRect() = MonitorScopeRect(x, y, width, height)
private fun MonitorScopeRect.chromeRect() = MonitorRect(x, y, width, height)
private fun LevelMode.display(): MonitorLevelDisplay = when (this) {
    LevelMode.Unavailable -> MonitorLevelDisplay.Unavailable
    is LevelMode.Gauges -> MonitorLevelDisplay.Gauges(rollDeg, tiltDeg)
    is LevelMode.Bubble -> MonitorLevelDisplay.Bubble(xDeg, yDeg)
}

@Composable
internal fun LiveLevelOverlay(reading: LevelReading, viewFlip: Boolean, feed: MonitorRect, viewport: MonitorRect,
    portrait: Boolean, modifier: Modifier = Modifier) {
    com.opencapture.opencine.cameracontrols.MonitorOperatorLevelOverlay(reading, viewFlip, feed, viewport, portrait, modifier)
}
