package com.opencapture.openpocketcine

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
fun Modifier.monitorGlass(shape: Shape = ChromeShape): Modifier = glass(shape)

@Composable
fun Modifier.chromePressable(enabled: Boolean = true): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed && enabled) 0.6f else 1f, tween(120), label = "chrome-press-a")
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, tween(120), label = "chrome-press-s")
    return this
        .graphicsLayer {
            this.alpha = alpha
            scaleX = scale
            scaleY = scale
        }
        .then(Modifier)
}

fun Modifier.liveModuleFrame(rect: ChromeRect): Modifier =
    offset(rect.x.dp, rect.y.dp).size(rect.width.dp, rect.height.dp)

/** Occupies [rect] and seats wrapping chrome (InfoPill, capture strip) like iOS `alignment`. */
fun Modifier.liveModuleFrame(rect: ChromeRect, alignment: Alignment): Modifier =
    liveModuleFrame(rect).wrapContentSize(align = alignment)

/**
 * Measures unbounded then scales down to [maxWidth] — iOS `minimumScaleFactor` for the
 * info-pill so chips compress instead of wrapping when the deck is tight.
 */
@Composable
fun FitScale(maxWidth: Dp, content: @Composable () -> Unit) {
    Layout(content) { measurables, _ ->
        val measurable = measurables.firstOrNull() ?: return@Layout layout(0, 0) {}
        val placeable = measurable.measure(Constraints())
        val maxPx = maxWidth.roundToPx()
        val scale = if (placeable.width > maxPx) maxPx / placeable.width.toFloat() else 1f
        val width = (placeable.width * scale).toInt()
        val height = (placeable.height * scale).toInt()
        layout(width, height) {
            placeable.placeWithLayer(0, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0f)
            }
        }
    }
}

/** Landscape top deck (OpenZCine `InfoPill` / iOS `GlassDeck`): glass hugs the nested chips. */
@Composable
fun InfoPill(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier = modifier.wrapContentWidth().monitorGlass().padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/**
 * Landscape capture strip shell (OpenZCine `MonitorCaptureStrip` / iOS `captureBarFrame`).
 * Glass hugs the readouts at 58dp; the host slot trailing-aligns this pill.
 */
@Composable
fun CaptureStripShell(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier =
            modifier
                .height(LiveDesign.CONTROL_HEIGHT_DP.dp)
                .wrapContentWidth()
                .monitorGlass()
                .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun Modifier.chromeClickable(
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val haptics = LocalOperatorHaptics.current
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed && enabled) 0.6f else 1f, tween(120), label = "chrome-a")
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, tween(120), label = "chrome-s")
    val press =
        Modifier.graphicsLayer {
            this.alpha = alpha
            scaleX = scale
            scaleY = scale
        }
    val clicks =
        if (onLongClick != null) {
            Modifier.combinedClickable(
                enabled = enabled,
                interactionSource = interaction,
                indication = null,
                onClick = {
                    haptics.selection()
                    onClick()
                },
                onLongClick = {
                    haptics.longPress()
                    onLongClick()
                },
            )
        } else {
            Modifier.clickable(
                enabled = enabled,
                interactionSource = interaction,
                indication = null,
                onClick = {
                    haptics.selection()
                    onClick()
                },
            )
        }
    return this.then(press).then(clicks)
}

object LiveChromeMetrics {
    const val LOCK = LiveDesign.LOCK_SIZE_DP
    const val AUX = LiveDesign.AUX_SIZE_DP
    const val RECORD = LiveDesign.RECORD_SIZE_DP
    const val DISP_W = LiveDesign.DISP_WIDTH_DP
    const val DISP_H = LiveDesign.DISP_HEIGHT_DP
    const val TOP_DECK_H = LiveDesign.TOP_DECK_HEIGHT_DP
    const val TOP_DECK_SIDE = 10f
    const val TOP_DECK_GAP = 12f
    const val BOTTOM_INSET = 14f
    const val BOTTOM_GAP = 12f
    const val RAIL_W = LiveDesign.RAIL_WIDTH_DP
    const val CHROME_TOP = 14f
    const val CHROME_LEADING = 16f
    const val CHROME_BOTTOM = 12f
    const val CHROME_TRAILING = 18f
    const val FEED_ASPECT = 16f / 9f
    const val CUTOUT_MIN = 50f
    const val CLASSIC_NOTCH_SHIFT = 10f
    const val BATTERY_PILL_W = 48f
    const val BATTERY_PILL_H = 40f
    const val BATTERY_PILL_LEADING = 8f
    const val BATTERY_PILL_GAP = 6f
    const val BATTERY_INLINE_GAP = 12f
    const val BATTERY_INLINE_W = 52f
    const val ZOOM_INSET = 10f
    const val ZOOM = LiveDesign.ZOOM_CHIP_DP
    const val STICK = LiveDesign.GIMBAL_STICK_DP
    const val KNOB = LiveDesign.GIMBAL_KNOB_DP
    const val STICK_INSET = 16f
    const val STICK_GAP = 8f
    const val FOCUS_RESET = LiveDesign.FOCUS_RESET_DP
    const val FOCUS_RESET_GAP = 24f
    const val POPUP_GAP = 10f
    const val TOP_PICKER_GAP = 8f
    const val CONTROL_H = LiveDesign.CONTROL_HEIGHT_DP
    /** Caps the info-pill slot so fillMaxSize glass cannot stretch across a tablet band. */
    const val INFO_PILL_HUG = 800f
    /** Six Pocket cells (ISO…AUDIO) + 12+12 strip pad. Trailing-aligned in the 2/3 capture slot. */
    const val CAPTURE_HUG = 512f
}

/**
 * The iPhone Dynamic Island's landscape leading safe-area inset, in points/dp —
 * the canonical iOS geometry throughout the layout tests (`LiveMonitorLayout`
 * 874×402 with leading 59). `feedFrame` turns it into a left chrome lane: the
 * feed starts at x = 59 while the fixed-margin lock button (chrome insets
 * ignore the safe area; lock spans x 16–56) sits beside it.
 */
internal const val IOS_ISLAND_LANE_DP = 59f

/**
 * The bottom inset handed to the portrait zone map while Android's system bars
 * are hidden. Sticky immersive can report a zero bottom inset, but the physical
 * gesture area is still present. This floor keeps the record control above that
 * edge after the shared layout reclaims its 14dp system-bar lift.
 */
internal const val PORTRAIT_SYSTEM_RAIL_BOTTOM_INSET_DP = 30f

/**
 * Leading inset handed to the zone map, in dp: the display cutout floored at
 * [IOS_ISLAND_LANE_DP], plus any transient system-bar lane on this edge.
 *
 * Devices whose punch-hole resolves below the core's 50dp cutout threshold
 * would otherwise run the feed edge-to-edge, putting the lock button and
 * battery rail ON the image. Flooring the cutout at the iPhone island lane
 * synthesizes the iOS composition — feed right of the chrome — as a
 * platform-adapter decision, keeping the layout math platform-blind. The
 * floor is a MINIMUM under the physical cutout only; a transient bar on this
 * edge still ADDS its lane on top so the feed clears the overlay.
 */
internal fun monitorLeadingInsetDp(cutoutDp: Float, transientBarDp: Float): Float =
    maxOf(cutoutDp, IOS_ISLAND_LANE_DP) + maxOf(0f, transientBarDp - cutoutDp)

/**
 * Bottom inset handed to the zone map, in dp.
 *
 * Sticky immersive mode can report no Android navigation-bar inset even
 * though a device still reserves its gesture area at the physical bottom.
 * Keep a portrait-only floor so the fixed system rail and its record button
 * never touch that edge; a real, larger system-bar/cutout inset still wins.
 */
internal fun monitorBottomInsetDp(rawInsetDp: Float, isPortrait: Boolean): Float =
    if (isPortrait) {
        maxOf(rawInsetDp, PORTRAIT_SYSTEM_RAIL_BOTTOM_INSET_DP)
    } else {
        rawInsetDp
    }

data class ChromeRect(val x: Float, val y: Float, val width: Float, val height: Float) {
    val minX: Float get() = x
    val minY: Float get() = y
    val maxX: Float get() = x + width
    val maxY: Float get() = y + height
    val midX: Float get() = x + width / 2f
    val midY: Float get() = y + height / 2f
    val isEmpty: Boolean get() = width <= 1f || height <= 1f

    fun inset(dx: Float, dy: Float): ChromeRect =
        ChromeRect(
            x + dx,
            y + dy,
            (width - 2f * dx).coerceAtLeast(0f),
            (height - 2f * dy).coerceAtLeast(0f),
        )

    fun intersects(other: ChromeRect): Boolean =
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
}

data class LiveMonitorLayout(
    val viewportWidth: Float,
    val viewportHeight: Float,
    val feed: ChromeRect,
    val picture: ChromeRect,
    val lock: ChromeRect,
    val battery: ChromeRect,
    val topDeck: ChromeRect,
    val assist: ChromeRect,
    val capture: ChromeRect,
    val rail: ChromeRect,
    val settings: ChromeRect,
    val media: ChromeRect,
    val record: ChromeRect,
    val disp: ChromeRect,
    val isWidthConstrained: Boolean,
    val showsBottomBars: Boolean,
    val safeLeading: Float,
    val safeTrailing: Float,
    val safeTop: Float,
    val safeBottom: Float,
) {
    val onFeed: ChromeRect
        get() = if (picture.width > 1f) picture else feed

    val zoomButton: ChromeRect
        get() {
            val size = LiveChromeMetrics.ZOOM
            val inset = LiveChromeMetrics.ZOOM_INSET
            val clear = 8f
            val well = feed
            return if (record.midX >= well.midX) {
                val trailing = min(well.maxX - inset, record.minX - clear)
                ChromeRect(trailing - size, record.midY - size / 2f, size, size)
            } else {
                val leading = max(well.minX + inset, record.maxX + clear)
                ChromeRect(leading, record.midY - size / 2f, size, size)
            }
        }

    val gimbalStick: ChromeRect
        get() {
            val size = LiveChromeMetrics.STICK
            val inset = LiveChromeMetrics.STICK_INSET
            val gap = LiveChromeMetrics.STICK_GAP
            var barTop = Float.POSITIVE_INFINITY
            if (showsBottomBars) {
                if (assist.height > 1f) barTop = min(barTop, assist.minY)
                if (capture.height > 1f) barTop = min(barTop, capture.minY)
            }
            val well = feed
            val floorY = if (barTop < Float.POSITIVE_INFINITY) min(well.maxY - inset, barTop - gap) else well.maxY - inset
            var x = well.maxX - inset - size
            var y = floorY - size
            x = min(max(x, well.minX + inset), max(well.minX, well.maxX - inset - size))
            y = min(max(y, well.minY + inset), max(well.minY, well.maxY - inset - size))
            var rect = ChromeRect(x, y, size, size)
            val zoom = zoomButton
            if (zoom.width > 1f && rect.intersects(zoom.inset(-gap, -gap))) {
                rect = rect.copy(y = zoom.maxY + gap)
            }
            if (record.width > 1f && rect.intersects(record.inset(-gap, -gap))) {
                rect = rect.copy(x = record.minX - gap - size)
            }
            return rect
        }

    val focusReset: ChromeRect
        get() {
            val size = LiveChromeMetrics.FOCUS_RESET
            if (viewportHeight > viewportWidth) {
                val well = onFeed
                return ChromeRect(well.maxX - size - 10f, well.maxY - size - 10f, size, size)
            }
            val towardFeed =
                if (battery.midX < feed.midX) {
                    battery.maxX + LiveChromeMetrics.FOCUS_RESET_GAP
                } else {
                    battery.minX - LiveChromeMetrics.FOCUS_RESET_GAP
                }
            val baseY = (if (assist.height > 1f) assist.minY else viewportHeight) - 30f
            return ChromeRect(towardFeed - size / 2f, baseY - size / 2f, size, size)
        }

    companion object {
        fun fit(
            viewportWidth: Float,
            viewportHeight: Float,
            safeLeading: Float,
            safeTrailing: Float,
            safeTop: Float,
            safeBottom: Float,
            showsBottomBars: Boolean,
        ): LiveMonitorLayout {
            val vw = max(0f, viewportWidth)
            val vh = max(0f, viewportHeight)
            val constrained = isWidthConstrained(vw, vh)
            val chrome = chromeRect(vw, vh)
            val feed = feedFrame(vw, vh, safeLeading, safeTrailing)
            val picture = feed
            val lock = lockRect(chrome)
            val battery = batteryRect(chrome, lock, constrained)
            val rail = rightRailRect(vw, chrome, feed)
            val slots =
                if (constrained) constrainedSlots(vh, chrome, lock)
                else railSlots(rail, if (showsBottomBars) LiveChromeMetrics.CONTROL_H else 0f)
            val bars = bottomBand(vw, vh, chrome, constrained)
            var layout =
                LiveMonitorLayout(
                    viewportWidth = vw,
                    viewportHeight = vh,
                    feed = feed,
                    picture = picture,
                    lock = lock,
                    battery = battery,
                    topDeck = ChromeRect(0f, 0f, 0f, 0f),
                    assist = bars.first,
                    capture = bars.second,
                    rail = rail,
                    settings = slots.settings,
                    media = slots.media,
                    record = slots.record,
                    disp = slots.disp,
                    isWidthConstrained = constrained,
                    showsBottomBars = showsBottomBars,
                    safeLeading = safeLeading,
                    safeTrailing = safeTrailing,
                    safeTop = safeTop,
                    safeBottom = safeBottom,
                )
            layout =
                layout.copy(
                    topDeck =
                        topDeckRect(layout.feed, layout.lock, layout.battery, layout.rail, constrained),
                )
            return layout
        }

        fun isWidthConstrained(vw: Float, vh: Float, aspect: Float = LiveChromeMetrics.FEED_ASPECT): Boolean =
            vh <= vw && vh * aspect > vw + 0.5f

        private fun chromeRect(vw: Float, vh: Float): ChromeRect =
            ChromeRect(
                LiveChromeMetrics.CHROME_LEADING,
                LiveChromeMetrics.CHROME_TOP,
                max(0f, vw - LiveChromeMetrics.CHROME_LEADING - LiveChromeMetrics.CHROME_TRAILING),
                max(0f, vh - LiveChromeMetrics.CHROME_TOP - LiveChromeMetrics.CHROME_BOTTOM),
            )

        private fun feedFrame(vw: Float, vh: Float, safeLeading: Float, safeTrailing: Float): ChromeRect {
            val aspect = LiveChromeMetrics.FEED_ASPECT
            if (vh > vw) return ChromeRect(0f, 0f, vw, vw / aspect)
            val width = vh * aspect
            if (width > vw + 0.5f) {
                val height = vw / aspect
                return ChromeRect(0f, (vh - height) / 2f, vw, height)
            }
            val remaining = max(0f, vw - width)
            val leadCut = if (safeLeading >= LiveChromeMetrics.CUTOUT_MIN) safeLeading else 0f
            val trailCut = if (safeTrailing >= LiveChromeMetrics.CUTOUT_MIN) safeTrailing else 0f
            val leadingInset = if (trailCut > leadCut) 0f else leadCut
            val x =
                if (isClassicNotch(safeLeading, safeTrailing)) {
                    val available = max(0f, remaining - max(0f, safeLeading) - max(0f, safeTrailing))
                    val shift = min(LiveChromeMetrics.CLASSIC_NOTCH_SHIFT, available)
                    min(remaining, safeLeading + shift)
                } else {
                    min(remaining, leadingInset)
                }
            return ChromeRect(x, 0f, width, vh)
        }

        private fun isClassicNotch(leading: Float, trailing: Float): Boolean {
            val minimum = min(max(0f, leading), max(0f, trailing))
            val maximum = max(max(0f, leading), max(0f, trailing))
            return minimum >= 40f && maximum <= 50f && abs(leading - trailing) < 4f
        }

        private fun lockRect(chrome: ChromeRect): ChromeRect {
            val size = LiveChromeMetrics.LOCK
            return ChromeRect(
                chrome.minX,
                chrome.minY + (LiveChromeMetrics.TOP_DECK_H - size) / 2f,
                size,
                size,
            )
        }

        private fun batteryRect(chrome: ChromeRect, lock: ChromeRect, constrained: Boolean): ChromeRect {
            if (constrained) {
                return ChromeRect(
                    chrome.minX + LiveChromeMetrics.LOCK + LiveChromeMetrics.BATTERY_INLINE_GAP,
                    lock.minY,
                    LiveChromeMetrics.BATTERY_INLINE_W,
                    LiveChromeMetrics.LOCK,
                )
            }
            return ChromeRect(
                LiveChromeMetrics.BATTERY_PILL_LEADING,
                lock.maxY + LiveChromeMetrics.BATTERY_PILL_GAP,
                LiveChromeMetrics.BATTERY_PILL_W,
                LiveChromeMetrics.BATTERY_PILL_H,
            )
        }

        private fun rightRailRect(vw: Float, chrome: ChromeRect, feed: ChromeRect): ChromeRect {
            val railWidth = min(chrome.width, LiveChromeMetrics.RAIL_W)
            val laneX = min(vw, max(0f, feed.maxX))
            val laneWidth = max(0f, vw - laneX)
            return if (laneWidth >= railWidth) {
                ChromeRect(laneX + (laneWidth - railWidth) / 2f, chrome.minY, railWidth, chrome.height)
            } else {
                ChromeRect(chrome.maxX - railWidth, chrome.minY, railWidth, chrome.height)
            }
        }

        private data class RailSlots(
            val settings: ChromeRect,
            val media: ChromeRect,
            val record: ChromeRect,
            val disp: ChromeRect,
        )

        private fun railSlots(rail: ChromeRect, bottomBarHeight: Float): RailSlots {
            val aux = LiveChromeMetrics.AUX
            val rec = LiveChromeMetrics.RECORD
            val dispW = LiveChromeMetrics.DISP_W
            val dispH = LiveChromeMetrics.DISP_H
            val recordCenterX = max(rec / 2f, rail.width - rec / 2f)
            val settingsCenterY = aux / 2f
            val recordCenterY = rail.height / 2f
            val mediaCenterY = (settingsCenterY + aux / 2f + recordCenterY - rec / 2f) / 2f
            val bottomBarTop = max(0f, rail.height - max(0f, bottomBarHeight))
            val dispHalf = dispH / 2f
            val clearOfRecord = recordCenterY + rec / 2f + dispHalf
            val displayCenterY =
                if (bottomBarHeight > 0f) (recordCenterY + rec / 2f + bottomBarTop) / 2f
                else max(clearOfRecord, rail.height - dispHalf)

            fun slot(cx: Float, cy: Float, w: Float, h: Float) =
                ChromeRect(rail.minX + cx - w / 2f, rail.minY + cy - h / 2f, w, h)

            return RailSlots(
                settings = slot(recordCenterX, settingsCenterY, aux, aux),
                media = slot(recordCenterX, mediaCenterY, aux, aux),
                record = slot(recordCenterX, recordCenterY, rec, rec),
                disp = slot(recordCenterX, displayCenterY, dispW, dispH),
            )
        }

        private fun constrainedSlots(vh: Float, chrome: ChromeRect, lock: ChromeRect): RailSlots {
            val aux = LiveChromeMetrics.AUX
            val gap = LiveChromeMetrics.BOTTOM_GAP
            val bandCenterY = chrome.minY + LiveChromeMetrics.TOP_DECK_H / 2f
            val settings = ChromeRect(chrome.maxX - aux, bandCenterY - aux / 2f, aux, aux)
            val media = ChromeRect(settings.minX - gap - aux, bandCenterY - aux / 2f, aux, aux)
            val rec = LiveChromeMetrics.RECORD
            val recordBottom = vh - LiveChromeMetrics.BOTTOM_INSET
            val record = ChromeRect(chrome.maxX - rec, recordBottom - rec, rec, rec)
            val disp =
                ChromeRect(
                    record.minX - gap - LiveChromeMetrics.DISP_W,
                    record.midY - LiveChromeMetrics.DISP_H / 2f,
                    LiveChromeMetrics.DISP_W,
                    LiveChromeMetrics.DISP_H,
                )
            return RailSlots(settings, media, record, disp)
        }

        private fun topDeckRect(
            feed: ChromeRect,
            lock: ChromeRect,
            battery: ChromeRect,
            rail: ChromeRect,
            constrained: Boolean,
        ): ChromeRect {
            val gap = LiveChromeMetrics.TOP_DECK_GAP
            val side = LiveChromeMetrics.TOP_DECK_SIDE
            var left = feed.minX + side
            var right = feed.maxX - side
            val clusterRight = max(lock.maxX, battery.maxX)
            val clusterLeft = min(lock.minX, battery.minX)
            if (clusterRight < feed.midX) left = max(left, clusterRight + gap)
            if (clusterLeft > feed.midX) right = min(right, clusterLeft - gap)
            if (constrained) {
                val reserved = 2f * LiveChromeMetrics.AUX + 2f * LiveChromeMetrics.BOTTOM_GAP
                val inset = side + reserved + gap
                left = max(left, feed.minX + inset)
                right = min(right, feed.maxX - inset)
            } else if (rail.midX > feed.midX) {
                right = min(right, rail.minX - gap)
            } else {
                left = max(left, rail.maxX + gap)
            }
            val band = max(0f, right - left)
            // Center a content-capped pill in the feed-anchored band (iOS positions
            // LiveTopChrome at topDeck.mid; OpenZCine FitScale-centres InfoPill).
            val hug = min(band, LiveChromeMetrics.INFO_PILL_HUG)
            return ChromeRect(
                left + (band - hug) / 2f,
                LiveChromeMetrics.CHROME_TOP,
                hug,
                LiveChromeMetrics.TOP_DECK_H,
            )
        }

        private fun bottomBand(
            @Suppress("UNUSED_PARAMETER") vw: Float,
            vh: Float,
            chrome: ChromeRect,
            constrained: Boolean,
        ): Pair<ChromeRect, ChromeRect> {
            val reserved =
                LiveChromeMetrics.RECORD + LiveChromeMetrics.DISP_W + 2f * LiveChromeMetrics.BOTTOM_GAP
            val barsWidth = if (constrained) max(0f, chrome.width - reserved) else chrome.width
            val gap = LiveChromeMetrics.BOTTOM_GAP
            val assistWidth = max(0f, (barsWidth - gap) / 3f)
            val captureWidth = max(0f, barsWidth - gap - assistWidth)
            val y = vh - LiveChromeMetrics.BOTTOM_INSET - LiveChromeMetrics.CONTROL_H
            val assist = ChromeRect(chrome.minX, y, assistWidth, LiveChromeMetrics.CONTROL_H)
            val captureSlot = ChromeRect(assist.maxX + gap, y, captureWidth, LiveChromeMetrics.CONTROL_H)
            // OpenZCine trailing-aligns the measured glass pill in the zone slot
            // (`contentAlignment = CenterEnd`). LiveViewScreen still fillMaxSize-glasses
            // this module, so the slot itself is content-capped on the trailing edge.
            val hug = min(captureSlot.width, LiveChromeMetrics.CAPTURE_HUG)
            val capture = ChromeRect(captureSlot.maxX - hug, y, hug, LiveChromeMetrics.CONTROL_H)
            return assist to capture
        }
    }
}

internal object LiveSessionBridge {
    fun call(target: Any, name: String, vararg args: Any?): Boolean {
        val method =
            target.javaClass.methods.firstOrNull { it.name == name && it.parameterCount == args.size }
                ?: return false
        val coerced =
            method.parameterTypes
                .mapIndexed { i, type ->
                    val arg = args[i] ?: return@mapIndexed null
                    when (type) {
                        java.lang.Float.TYPE,
                        java.lang.Float::class.java,
                        -> (arg as Number).toFloat()
                        java.lang.Double.TYPE,
                        java.lang.Double::class.java,
                        -> (arg as Number).toDouble()
                        Integer.TYPE,
                        java.lang.Integer::class.java,
                        -> (arg as Number).toInt()
                        java.lang.Boolean.TYPE,
                        java.lang.Boolean::class.java,
                        -> arg as Boolean
                        else -> arg
                    }
                }
                .toTypedArray()
        return runCatching {
                method.invoke(target, *coerced)
                true
            }
            .getOrDefault(false)
    }
}

@Composable
fun LockButton(locked: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val tint = if (locked) LiveDesign.accent else LiveDesign.text.copy(alpha = 0.86f)
    Box(
        modifier
            .size(LiveDesign.LOCK_SIZE_DP.dp)
            .monitorGlass()
            .then(
                if (locked) Modifier.border(1.5.dp, LiveDesign.accent.copy(alpha = 0.75f), ChromeShape)
                else Modifier,
            )
            .chromeClickable(onClick = onClick)
            .semantics {
                contentDescription = if (locked) "Unlock monitor controls" else "Lock monitor controls"
                role = Role.Switch
                toggleableState = ToggleableState(locked)
            },
        contentAlignment = Alignment.Center,
    ) {
        PadlockGlyph(tint = tint, filled = locked, modifier = Modifier.size(13.dp, 17.dp))
    }
}

@Composable
fun DispButton(
    clean: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    Column(
        modifier
            .width(LiveDesign.DISP_WIDTH_DP.dp)
            .height(LiveDesign.DISP_HEIGHT_DP.dp)
            .monitorGlass()
            .chromeClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics {
                contentDescription = if (clean) "DISP 2 clean" else "DISP 1 live"
                role = Role.Button
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
    ) {
        Text(
            "DISP",
            color = if (clean) LiveDesign.text else LiveDesign.info,
            style = LiveType.ui(12f, FontWeight.Bold),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(
                Modifier.size(width = 14.dp, height = 3.dp)
                    .clip(CircleShape)
                    .background(if (!clean) LiveDesign.info else LiveDesign.hairlineStrong),
            )
            Box(
                Modifier.size(width = 14.dp, height = 3.dp)
                    .clip(CircleShape)
                    .background(if (clean) LiveDesign.info else LiveDesign.hairlineStrong),
            )
        }
    }
}

@Composable
fun AuxCircleButton(modifier: Modifier = Modifier, onClick: () -> Unit, glyph: @Composable (Color) -> Unit) {
    Box(
        modifier
            .size(LiveDesign.AUX_SIZE_DP.dp)
            .monitorGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { role = Role.Button },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size((LiveDesign.AUX_SIZE_DP * 0.36f).dp),
            contentAlignment = Alignment.Center,
        ) {
            glyph(LiveDesign.text.copy(alpha = 0.86f))
        }
    }
}

@Composable
fun RecordButton(
    recording: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    confirm: Boolean = false,
    onClick: () -> Unit,
) {
    var confirmOpen by remember { mutableStateOf(false) }
    if (confirmOpen) {
        AlertDialog(
            onDismissRequest = { confirmOpen = false },
            title = {
                Text(
                    if (recording) "Stop recording?" else "Start recording?",
                    color = LiveDesign.text,
                    style = LiveType.ui(16f, FontWeight.SemiBold),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmOpen = false
                        onClick()
                    },
                ) {
                    Text(
                        if (recording) "Stop" else "Start",
                        color = if (recording) LiveDesign.rec else LiveDesign.accent,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmOpen = false }) {
                    Text("Cancel", color = LiveDesign.muted)
                }
            },
            containerColor = LiveDesign.surface,
        )
    }
    Box(
        modifier
            .size(LiveDesign.RECORD_SIZE_DP.dp)
            .then(if (recording && !enabled) Modifier.graphicsLayer { alpha = 0.72f } else Modifier)
            .shadow(2.dp, CircleShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.40f))
            .chromeClickable(enabled = enabled, onClick = { if (confirm) confirmOpen = true else onClick() })
            .semantics {
                contentDescription = if (recording) "Stop recording" else "Start recording"
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        RecordLamp(recording = recording)
    }
}

@Composable
private fun RecordLamp(recording: Boolean) {
    val transition = rememberInfiniteTransition(label = "recordPulse")
    val pulse by
        transition.animateFloat(
            initialValue = 0.22f,
            targetValue = 0.55f,
            animationSpec = infiniteRepeatable(tween(850), RepeatMode.Reverse),
            label = "recordGlow",
        )
    val glow = if (recording) pulse else 0f
    Canvas(Modifier.fillMaxSize()) {
        val d = size.minDimension
        val center = Offset(size.width / 2, size.height / 2)
        val ring = d * 0.50f
        val ringLine = max(2.dp.toPx(), d * 0.026f)
        if (recording) {
            drawCircle(LiveDesign.pocketRing.copy(alpha = glow), radius = d * 0.58f, center = center)
        }
        drawCircle(LiveDesign.recordWell, radius = d / 2f, center = center)
        drawCircle(Color.Black.copy(alpha = 0.55f), radius = d / 2f, center = center, style = Stroke(1.5.dp.toPx()))
        if (recording) {
            drawCircle(LiveDesign.pocketRing, radius = ring / 2f, center = center)
        } else {
            drawCircle(
                LiveDesign.pocketRing,
                radius = ring / 2f,
                center = center,
                style = Stroke(ringLine),
            )
        }
    }
}

@Composable
fun BatteryPair(
    phonePercent: Int,
    phoneCharging: Boolean,
    cameraPercent: Int,
    cameraCharging: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        BatteryOutlineRow(percent = phonePercent, charging = phoneCharging, camera = false)
        BatteryOutlineRow(percent = cameraPercent, charging = cameraCharging, camera = true)
    }
}

@Composable
private fun BatteryOutlineRow(percent: Int, charging: Boolean, camera: Boolean) {
    val tint =
        when {
            percent < 0 -> LiveDesign.faint
            percent <= 20 -> LiveDesign.rec
            percent <= 40 -> LiveDesign.amber
            else -> LiveDesign.good
        }
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(12.dp), contentAlignment = Alignment.Center) {
            if (camera) CameraGlyph(LiveDesign.muted, Modifier.size(12.dp, 10.dp))
            else PhoneGlyph(LiveDesign.muted, Modifier.size(7.dp, 11.dp))
        }
        Box(Modifier.size(28.dp, 16.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 1.2.dp.toPx()
                val bodyWidth = size.width - 3.dp.toPx()
                drawRoundRect(
                    tint.copy(alpha = 0.85f),
                    topLeft = Offset.Zero,
                    size = Size(bodyWidth, size.height),
                    cornerRadius = CornerRadius(3.5.dp.toPx()),
                    style = Stroke(stroke),
                )
                drawRoundRect(
                    tint.copy(alpha = 0.85f),
                    topLeft = Offset(bodyWidth, size.height * 0.28f),
                    size = Size(2.4.dp.toPx(), size.height * 0.44f),
                    cornerRadius = CornerRadius(1.dp.toPx()),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                if (charging) {
                    Text("⚡", color = tint, fontSize = 7.sp)
                }
                Text(
                    if (percent < 0) "—" else "$percent",
                    color = tint,
                    style = LiveType.ui(10f, FontWeight.Medium),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
fun CameraBatteryReadout(percent: Int, modifier: Modifier = Modifier) {
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CameraGlyph(LiveDesign.text, Modifier.size(12.dp, 10.dp))
        Text(
            if (percent in 0..100) "$percent%" else "—",
            color = LiveDesign.text,
            style = LiveType.ui(12f, FontWeight.SemiBold),
        )
    }
}

@Composable
fun TimecodeReadout(timecode: String?, modifier: Modifier = Modifier, portrait: Boolean = false) {
    val raw = timecode?.takeIf { it.isNotBlank() } ?: if (portrait) "00:00:00" else "--:--:--"
    val colon = raw.lastIndexOf(':')
    val head = if (colon >= 0) raw.substring(0, colon + 1) else raw
    val tail = if (colon >= 0) raw.substring(colon + 1) else ""
    if (portrait) {
        Text(
            raw,
            color = LiveDesign.text,
            style = LiveType.mono(15f, FontWeight.Normal),
            maxLines = 1,
            softWrap = false,
            modifier = modifier,
        )
        return
    }
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(color = LiveDesign.text)) { append("TC $head") }
            withStyle(SpanStyle(color = LiveDesign.accent)) { append(tail) }
        },
        style = LiveType.mono(20f, FontWeight.Medium),
        maxLines = 1,
        softWrap = false,
        modifier = modifier.wrapContentWidth(align = Alignment.Start, unbounded = true),
    )
}

@Composable
fun RecChip(recording: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        modifier =
            Modifier
                .wrapContentWidth(unbounded = true)
                .chipGlass(CircleShape)
                .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(if (recording) LiveDesign.rec else LiveDesign.faint))
        Text(
            if (recording) "REC" else "STBY",
            color = if (recording) LiveDesign.text else LiveDesign.muted,
            style = LiveType.ui(11f, FontWeight.Bold),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
fun FpsChip(fps: String, bars: Int) {
    val tint =
        when {
            bars >= 3 -> LiveDesign.good
            bars == 2 -> LiveDesign.accent
            bars == 1 -> LiveDesign.rec
            else -> LiveDesign.faint
        }
    Row(
        modifier =
            Modifier
                .wrapContentWidth(unbounded = true)
                .chipGlass(CircleShape)
                .padding(horizontal = 11.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalBarsGlyph(bars = bars, tint = tint)
        Text(
            "FPS",
            color = LiveDesign.faint,
            style = LiveType.mono(8f, FontWeight.Bold),
            maxLines = 1,
            softWrap = false,
        )
        Text(
            fps,
            color = LiveDesign.text,
            style = LiveType.mono(12f, FontWeight.Medium),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
fun ReadoutPill(
    value: String,
    active: Boolean = false,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    icon: @Composable (Color) -> Unit,
) {
    val surface =
        if (active) {
            Modifier.background(LiveDesign.accentDim, CircleShape).border(1.dp, LiveDesign.accentDim, CircleShape)
        } else {
            Modifier.chipGlass(CircleShape)
        }
    Row(
        modifier =
            surface
                .wrapContentWidth(unbounded = true)
                .then(
                    if (onClick != null) {
                        Modifier.chromeClickable(enabled = enabled, onClick = onClick, onLongClick = onLongClick)
                    } else {
                        Modifier
                    },
                )
                .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon(if (active) LiveDesign.accent else LiveDesign.muted)
        Text(
            value.replace(" · ", "·"),
            color = if (active) LiveDesign.accent else LiveDesign.text,
            style = LiveType.mono(15f, FontWeight.Medium),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
fun CaptureSettingCell(
    label: String,
    value: String,
    widest: String,
    active: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val labelColor = if (active) LiveDesign.accent.copy(alpha = 0.85f) else LiveDesign.muted
    val valueColor = if (active) LiveDesign.accent else LiveDesign.text
    Column(
        modifier =
            Modifier
                .wrapContentWidth()
                .clip(ChromeShape)
                .background(if (active) LiveDesign.accentDim else Color.Transparent)
                .then(
                    if (active) Modifier.border(1.dp, LiveDesign.accentDim, ChromeShape) else Modifier,
                )
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 4.dp, vertical = 5.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(label, color = labelColor, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
        Box(contentAlignment = Alignment.Center) {
            Text(
                widest,
                color = Color.Transparent,
                style = LiveType.ui(17f, FontWeight.Medium),
                maxLines = 1,
            )
            Text(value, color = valueColor, style = LiveType.ui(17f, FontWeight.Medium), maxLines = 1)
        }
    }
}

@Composable
fun AssistToolChip(label: String, on: Boolean, enabled: Boolean, stub: Boolean, onClick: () -> Unit) {
    Column(
        modifier =
            Modifier.clip(ChromeShape)
                .background(if (on) LiveDesign.accentDim else Color.Transparent)
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 8.dp, vertical = 5.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(
            label,
            color = if (on) LiveDesign.accent else LiveDesign.muted,
            style = LiveType.mono(9f, FontWeight.Medium),
            maxLines = 1,
        )
        if (stub && on) {
            Text("local", color = LiveDesign.faint, style = LiveType.mono(7f), maxLines = 1)
        }
    }
}

@Composable
fun LiveGimbalStick(
    enabled: Boolean,
    onMove: (Float, Float) -> Unit,
    onRelease: () -> Unit,
    onRecenter: () -> Unit,
    onFlip: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val size = LiveDesign.GIMBAL_STICK_DP.dp
    val knob = LiveDesign.GIMBAL_KNOB_DP.dp
    var knobOffset by remember { mutableStateOf(Offset.Zero) }
    val scope = rememberCoroutineScope()
    var recenterJob by remember { mutableStateOf<Job?>(null) }
    Box(
        modifier
            .size(size)
            .semantics { contentDescription = "Gimbal stick" }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                val travel = (size.toPx() - knob.toPx()) / 2f
                var taps = 0
                var lastTap = 0L
                awaitEachGesture {
                    val down = awaitFirstDown()
                    var dragged = false
                    var translation = Offset.Zero
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (change.pressed) {
                            translation += change.positionChange()
                            val mag = hypot(translation.x, translation.y)
                            if (mag > 10f) {
                                dragged = true
                                taps = 0
                                recenterJob?.cancel()
                                val limited =
                                    if (mag > travel && mag > 0f) translation * (travel / mag) else translation
                                knobOffset = limited
                                val denom = if (travel > 0f) travel else 1f
                                onMove(limited.x / denom, -limited.y / denom)
                            }
                            change.consume()
                        } else {
                            break
                        }
                    }
                    if (dragged) {
                        knobOffset = Offset.Zero
                        onRelease()
                    } else {
                        knobOffset = Offset.Zero
                        val now = System.currentTimeMillis()
                        if (now - lastTap > 420L) taps = 0
                        taps += 1
                        lastTap = now
                        when (taps) {
                            2 -> {
                                recenterJob?.cancel()
                                recenterJob =
                                    scope.launch {
                                        delay(280)
                                        onRecenter()
                                        taps = 0
                                    }
                            }
                            3 -> {
                                recenterJob?.cancel()
                                recenterJob = null
                                taps = 0
                                onFlip()
                            }
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 2.dp.toPx()
            drawCircle(
                color = Color.White.copy(alpha = 0.30f),
                radius = size.toPx() / 2f - stroke / 2f,
                style = Stroke(width = stroke),
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.30f),
                radius = knob.toPx() / 2f,
                center = center + knobOffset,
            )
        }
    }
    LaunchedEffect(enabled) {
        if (!enabled) {
            recenterJob?.cancel()
            knobOffset = Offset.Zero
            onRelease()
        }
    }
}

@Composable
fun LiveFocusResetButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .size(LiveDesign.FOCUS_RESET_DP.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, LiveDesign.hairline, CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = "Recenter focus" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(18.dp)) {
            val c = center
            val r = size.minDimension / 2f
            drawCircle(LiveDesign.text, radius = r, style = Stroke(1.6.dp.toPx()))
            drawCircle(LiveDesign.text, radius = 2.dp.toPx())
            drawLine(LiveDesign.text, Offset(c.x, c.y - r), Offset(c.x, c.y - r + 4.dp.toPx()), 1.4.dp.toPx())
            drawLine(LiveDesign.text, Offset(c.x, c.y + r - 4.dp.toPx()), Offset(c.x, c.y + r), 1.4.dp.toPx())
            drawLine(LiveDesign.text, Offset(c.x - r, c.y), Offset(c.x - r + 4.dp.toPx(), c.y), 1.4.dp.toPx())
            drawLine(LiveDesign.text, Offset(c.x + r - 4.dp.toPx(), c.y), Offset(c.x + r, c.y), 1.4.dp.toPx())
        }
    }
}

@Composable
fun PadlockGlyph(tint: Color, filled: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val body =
            Path().apply {
                addRoundRect(
                    androidx.compose.ui.geometry.RoundRect(
                        left = w * 0.08f,
                        top = h * 0.42f,
                        right = w * 0.92f,
                        bottom = h * 0.96f,
                        radiusX = 2.dp.toPx(),
                        radiusY = 2.dp.toPx(),
                    ),
                )
            }
        if (filled) drawPath(body, tint)
        else drawPath(body, tint, style = Stroke(1.6.dp.toPx()))
        drawArc(
            color = tint,
            startAngle = 200f,
            sweepAngle = 140f,
            useCenter = false,
            topLeft = Offset(w * 0.22f, h * 0.04f),
            size = Size(w * 0.56f, h * 0.48f),
            style = Stroke(1.6.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}

@Composable
fun PhoneGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        drawRoundRect(tint, style = Stroke(1.3.dp.toPx()), cornerRadius = CornerRadius(1.6.dp.toPx()))
    }
}

@Composable
fun CameraGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        drawRoundRect(tint, style = Stroke(1.3.dp.toPx()), cornerRadius = CornerRadius(1.8.dp.toPx()))
        drawCircle(tint, radius = size.minDimension * 0.22f, style = Stroke(1.2.dp.toPx()))
    }
}

@Composable
fun GearGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val c = Offset(size.width / 2, size.height / 2)
        val r = size.minDimension * 0.28f
        drawCircle(tint, radius = r, center = c, style = Stroke(1.6.dp.toPx()))
        for (i in 0 until 6) {
            val a = Math.toRadians((i * 60).toDouble())
            val inner = r + 1.dp.toPx()
            val outer = size.minDimension * 0.46f
            drawLine(
                tint,
                Offset(c.x + (inner * kotlin.math.cos(a)).toFloat(), c.y + (inner * kotlin.math.sin(a)).toFloat()),
                Offset(c.x + (outer * kotlin.math.cos(a)).toFloat(), c.y + (outer * kotlin.math.sin(a)).toFloat()),
                2.dp.toPx(),
                StrokeCap.Round,
            )
        }
    }
}

@Composable
fun MediaGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        drawRoundRect(
            tint,
            topLeft = Offset(w * 0.12f, h * 0.22f),
            size = Size(w * 0.76f, h * 0.56f),
            cornerRadius = CornerRadius(2.dp.toPx()),
            style = Stroke(1.5.dp.toPx()),
        )
        drawLine(tint, Offset(w * 0.28f, h * 0.22f), Offset(w * 0.38f, h * 0.08f), 1.5.dp.toPx(), StrokeCap.Round)
        drawLine(tint, Offset(w * 0.38f, h * 0.08f), Offset(w * 0.72f, h * 0.08f), 1.5.dp.toPx(), StrokeCap.Round)
        drawLine(tint, Offset(w * 0.72f, h * 0.08f), Offset(w * 0.82f, h * 0.22f), 1.5.dp.toPx(), StrokeCap.Round)
    }
}

@Composable
fun VideoGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(14.dp, 11.dp)) {
        drawRoundRect(tint, style = Stroke(1.4.dp.toPx()), cornerRadius = CornerRadius(2.dp.toPx()))
        val path =
            Path().apply {
                moveTo(size.width * 0.42f, size.height * 0.32f)
                lineTo(size.width * 0.68f, size.height * 0.5f)
                lineTo(size.width * 0.42f, size.height * 0.68f)
                close()
            }
        drawPath(path, tint)
    }
}

@Composable
fun ColorGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(12.dp)) {
        drawCircle(tint, radius = size.minDimension / 2, style = Stroke(1.4.dp.toPx()))
        drawCircle(tint, radius = size.minDimension * 0.18f)
    }
}

@Composable
fun SdCardGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(11.dp, 14.dp)) {
        val path =
            Path().apply {
                moveTo(size.width * 0.15f, 0f)
                lineTo(size.width * 0.62f, 0f)
                lineTo(size.width, size.height * 0.22f)
                lineTo(size.width, size.height)
                lineTo(0f, size.height)
                lineTo(0f, size.height * 0.18f)
                close()
            }
        drawPath(path, tint, style = Stroke(1.3.dp.toPx()))
    }
}

@Composable
fun SignalBarsGlyph(bars: Int, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(12.dp, 10.dp)) {
        val gap = 1.6.dp.toPx()
        val w = (size.width - gap * 3) / 4f
        for (i in 0 until 4) {
            val h = size.height * (0.35f + i * 0.22f)
            val color = if (i < bars) tint else tint.copy(alpha = 0.22f)
            drawRoundRect(
                color,
                topLeft = Offset(i * (w + gap), size.height - h),
                size = Size(w, h),
                cornerRadius = CornerRadius(0.8.dp.toPx()),
            )
        }
    }
}
