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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
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
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import com.opencapture.openpocketcine.core.ConnectionPhase
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
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
fun Modifier.monitorGlass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

/** iOS `CloseButton` on live picker / assist cards — 34dp glass circle. */
@Composable
fun LivePopupCloseButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
) {
    Box(
        modifier
            .size(size)
            .glass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = OpcIcon.X,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(size * 0.38f),
        )
    }
}

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

/**
 * Uniform scale-to-fit, centered. Floor matches iOS `minimumScaleFactor(0.65)`
 * on the battery readout so "100" + bolt stay inside the outline.
 */
internal fun scaleToFitFactor(
    contentWidth: Int,
    contentHeight: Int,
    maxWidth: Int,
    maxHeight: Int,
    minScale: Float = 0.65f,
): Float {
    if (contentWidth <= 0 || contentHeight <= 0 || maxWidth <= 0 || maxHeight <= 0) return 1f
    val scaleX = if (contentWidth > maxWidth) maxWidth / contentWidth.toFloat() else 1f
    val scaleY = if (contentHeight > maxHeight) maxHeight / contentHeight.toFloat() else 1f
    return min(scaleX, scaleY).coerceIn(minScale, 1f)
}

@Composable
private fun ScaleToFit(
    minScale: Float,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Layout(content, modifier) { measurables, constraints ->
        val measurable = measurables.firstOrNull() ?: return@Layout layout(0, 0) {}
        val placeable = measurable.measure(Constraints())
        val maxW = if (constraints.hasBoundedWidth) constraints.maxWidth else placeable.width
        val maxH = if (constraints.hasBoundedHeight) constraints.maxHeight else placeable.height
        val scale = scaleToFitFactor(placeable.width, placeable.height, maxW, maxH, minScale)
        layout(maxW, maxH) {
            placeable.placeWithLayer(
                ((maxW - placeable.width * scale) / 2f).toInt(),
                ((maxH - placeable.height * scale) / 2f).toInt(),
            ) {
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
                .fillMaxWidth()
                .monitorGlass()
                .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/**
 * Landscape bottom row: capture hugs its chips on the trailing edge; the
 * view-assist bar fills the leftover so the 12 dp gutter is the only gap.
 */
@Composable
fun LiveBottomChromeBand(
    band: ChromeRect,
    showAssist: Boolean,
    showCapture: Boolean,
    modifier: Modifier = Modifier,
    assist: @Composable () -> Unit,
    capture: @Composable () -> Unit,
) {
    Layout(
        modifier = modifier.liveModuleFrame(band),
        content = {
            Box(Modifier.layoutId("capture")) { if (showCapture) capture() }
            Box(Modifier.layoutId("assist")) { if (showAssist) assist() }
        },
    ) { measurables, constraints ->
        val gap = LiveChromeMetrics.BOTTOM_GAP.dp.roundToPx()
        val hug = LiveChromeMetrics.CAPTURE_HUG.dp.roundToPx()
        val captureMeasurable = measurables.first { it.layoutId == "capture" }
        val assistMeasurable = measurables.first { it.layoutId == "assist" }
        val minAssist =
            if (showAssist) max(0, (constraints.maxWidth - gap) / 3) else 0
        val maxCapture =
            if (showCapture) {
                min(hug, constraints.maxWidth - minAssist - if (showAssist) gap else 0).coerceAtLeast(0)
            } else {
                0
            }
        val capturePlaceable =
            captureMeasurable.measure(
                Constraints(maxWidth = maxCapture, maxHeight = constraints.maxHeight),
            )
        val captureW = if (showCapture) capturePlaceable.width else 0
        val assistW =
            if (!showAssist) {
                0
            } else if (captureW == 0) {
                constraints.maxWidth
            } else {
                (constraints.maxWidth - captureW - gap).coerceAtLeast(minAssist)
            }
        val assistPlaceable =
            assistMeasurable.measure(
                Constraints.fixed(assistW.coerceAtLeast(0), constraints.maxHeight),
            )
        layout(constraints.maxWidth, constraints.maxHeight) {
            if (showAssist) assistPlaceable.place(0, 0)
            if (showCapture) capturePlaceable.place(constraints.maxWidth - capturePlaceable.width, 0)
        }
    }
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
    /** Compact-phone multiplier. `fit` / live view set this; tests leave it at 1. */
    var scale: Float = 1f

    val LOCK get() = LiveDesign.LOCK_SIZE_DP * scale
    val AUX get() = LiveDesign.AUX_SIZE_DP * scale
    val RECORD get() = LiveDesign.RECORD_SIZE_DP * scale
    val DISP_W get() = LiveDesign.DISP_WIDTH_DP * scale
    val DISP_H get() = LiveDesign.DISP_HEIGHT_DP * scale
    val TOP_DECK_H get() = LiveDesign.TOP_DECK_HEIGHT_DP * scale
    val TOP_DECK_SIDE get() = 10f * scale
    val TOP_DECK_GAP get() = 12f * scale
    val BOTTOM_INSET get() = 14f * scale
    val BOTTOM_GAP get() = 12f * scale
    val RAIL_W get() = LiveDesign.RAIL_WIDTH_DP * scale
    val RAIL_SIDE_GUTTER get() = 8f * scale
    val CHROME_TOP get() = 14f * scale
    val CHROME_LEADING get() = 16f * scale
    val CHROME_BOTTOM get() = 12f * scale
    val CHROME_TRAILING get() = 18f * scale
    const val FEED_ASPECT = 16f / 9f
    const val CUTOUT_MIN = 50f
    const val CLASSIC_NOTCH_SHIFT = 10f
    val BATTERY_PILL_W get() = 48f * scale
    val BATTERY_PILL_H get() = 40f * scale
    val BATTERY_PILL_LEADING get() = 8f * scale
    val BATTERY_PILL_GAP get() = 6f * scale
    val BATTERY_INLINE_GAP get() = 12f * scale
    val BATTERY_INLINE_W get() = 52f * scale
    val ZOOM_INSET get() = 10f * scale
    val ZOOM get() = LiveDesign.ZOOM_CHIP_DP * scale
    val STICK get() = LiveDesign.GIMBAL_STICK_DP * scale
    val KNOB get() = LiveDesign.GIMBAL_KNOB_DP * scale
    val STICK_INSET get() = 16f * scale
    val STICK_GAP get() = 8f * scale
    val FOCUS_RESET get() = LiveDesign.FOCUS_RESET_DP * scale
    val FOCUS_RESET_GAP get() = 24f * scale
    val POPUP_GAP get() = 10f * scale
    val TOP_PICKER_GAP get() = 8f * scale
    val TOP_PICKER_WIDTH get() = LiveDesign.TOP_PICKER_WIDTH_DP * scale
    val CAPTURE_PICKER_MAX_WIDTH get() = LiveDesign.CAPTURE_PICKER_WIDTH_DP * scale
    val CONTROL_H get() = LiveDesign.CONTROL_HEIGHT_DP * scale
    val INFO_PILL_HUG get() = 800f * scale
    val CAPTURE_HUG get() = 512f * scale
    val CAPTURE_CELL_GAP get() = 16f * scale
    /** OpenZCine `PickerPanel` hug (16+16 pad, 34 close header, 14 gap, 176 drum). */
    const val DRUM_PICKER_HEIGHT = 256f
    /** Extra hug when a mode-tab row sits under the drum. */
    const val PICKER_MODE_BAR_HEIGHT = 51f
}

/** Assist takes leftover after the capture pill hugs the trailing edge. */
internal data class BottomBarSplit(val assistWidth: Float, val captureWidth: Float)

internal fun bottomBarSplit(barsWidth: Float, gap: Float, captureHug: Float): BottomBarSplit {
    val inner = max(0f, barsWidth - gap)
    val captureShare = inner - inner / 3f
    val capture = min(captureShare, captureHug).coerceAtLeast(0f)
    val assist = max(0f, barsWidth - gap - capture)
    return BottomBarSplit(assist, capture)
}

/**
 * The iPhone Dynamic Island's landscape leading safe-area inset, in points/dp —
 * the canonical iOS geometry throughout the layout tests (`LiveMonitorLayout`
 * 874×402 with leading 59). `feedFrame` turns it into a left chrome lane: the
 * feed starts at x = 59 while the fixed-margin lock button (chrome insets
 * ignore the safe area; lock spans x 16–56) sits beside it. Compact 16:9
 * viewports may slide a couple of dp left of 59 so the trailing rail still
 * fits in the letterbox.
 */
internal const val IOS_ISLAND_LANE_DP = 59f

/**
 * Shortest side (sw dp / landscape height) of the iPhone Pro Max / 6.8" class
 * the live HUD is authored against. Compact phones (S25 360 dp) scale chrome
 * down to [CHROME_SCALE_MIN] so record / rail / type match that board.
 */
internal const val CHROME_SCALE_REFERENCE_DP = 424f

internal const val CHROME_SCALE_MIN = 0.935f

/** 1 on Pro Max / 6.8"+; [CHROME_SCALE_MIN] on S25-class 360 dp; lerp in between. */
internal fun monitorChromeScale(smallestWidthDp: Float): Float {
    if (smallestWidthDp <= 0f) return 1f
    return (smallestWidthDp / CHROME_SCALE_REFERENCE_DP).coerceIn(CHROME_SCALE_MIN, 1f)
}

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
internal fun monitorLeadingInsetDp(
    cutoutDp: Float,
    transientBarDp: Float,
    chromeScale: Float = 1f,
): Float {
    // Island floor is geometry, not chrome scale — compact phones still get
    // the iPhone lane. `chromeScale` is unused here (callers pass it).
    return maxOf(cutoutDp, IOS_ISLAND_LANE_DP) + maxOf(0f, transientBarDp - cutoutDp)
}

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

    fun contains(px: Float, py: Float): Boolean = px >= minX && px <= maxX && py >= minY && py <= maxY
}

/** Canvas origin in window pixels — capture / top-picker anchors are relative to this. */
val LocalLiveCanvasOrigin = compositionLocalOf { Offset.Zero }

fun Modifier.reportChromeFrame(onFrame: (ChromeRect) -> Unit): Modifier =
    composed {
        val density = LocalDensity.current
        val origin = LocalLiveCanvasOrigin.current
        onGloballyPositioned { coords ->
            val pos = coords.positionInRoot()
            val d = density.density
            onFrame(
                ChromeRect(
                    (pos.x - origin.x) / d,
                    (pos.y - origin.y) / d,
                    coords.size.width / d,
                    coords.size.height / d,
                ),
            )
        }
    }

/**
 * OpenZCine live-view popup geometry (`PanelHost.topPickerBody` / `bottomPickerBody`):
 * a glass card 8dp below a top chip or 10dp above a bottom bar, clamped into the
 * safe viewport — never a full-bleed or centred sheet.
 */
object LivePopupPlacement {
    data class Box(val x: Float, val y: Float, val width: Float, val maxHeight: Float)

    const val EDGE_MARGIN = 8f
    const val ASSIST_MARGIN = 12f
    const val CUTOUT_CLEARANCE = 4f
    const val ASSIST_TOP_INSET = 4f

    fun horizontalBand(
        preferredWidth: Float,
        viewportWidth: Float,
        safeLeading: Float,
        safeTrailing: Float,
        margin: Float,
    ): Triple<Float, Float, Float> {
        val minX = max(margin, safeLeading + CUTOUT_CLEARANCE)
        val maxX = viewportWidth - max(margin, safeTrailing + CUTOUT_CLEARANCE)
        val width = max(0f, min(preferredWidth, maxX - minX))
        return Triple(minX, maxX, width)
    }

    fun leadingX(desired: Float, width: Float, minX: Float, maxX: Float): Float =
        min(max(desired, minX), max(minX, maxX - width))

    /** OpenZCine `topPickerBody`: 340-wide card, centred on the cell, 8dp under `cell.maxY`. */
    fun topPicker(
        cell: ChromeRect,
        panelHeight: Float,
        viewportWidth: Float,
        viewportHeight: Float,
        safeLeading: Float,
        safeTrailing: Float,
        safeTop: Float,
        safeBottom: Float,
        floorY: Float? = null,
        preferredWidth: Float = LiveChromeMetrics.TOP_PICKER_WIDTH,
        gap: Float = LiveChromeMetrics.TOP_PICKER_GAP,
    ): Box {
        val (minX, maxX, width) =
            horizontalBand(
                preferredWidth = preferredWidth,
                viewportWidth = viewportWidth,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                margin = EDGE_MARGIN,
            )
        val hasCell = cell.width > 1f && cell.height > 1f
        val x =
            leadingX(
                desired = if (hasCell) cell.midX - width / 2f else minX,
                width = width,
                minX = minX,
                maxX = maxX,
            )
        val minY = max(EDGE_MARGIN, safeTop + LiveChromeMetrics.CHROME_TOP + EDGE_MARGIN)
        val floor = floorY ?: (viewportHeight - max(EDGE_MARGIN, safeBottom))
        val desiredTop = if (hasCell) cell.maxY + gap else minY
        // Pin under the chip. A too-tall first measure must shrink into
        // maxHeight — not slide up over STBY / the originating chip.
        val y = max(minY, desiredTop)
        return Box(x = x, y = y, width = width, maxHeight = max(0f, floor - y))
    }

    /**
     * OpenZCine `bottomPickerBody`: 420 cap, 10dp above the capture bar, centred on
     * the originating tile (or the bar when the tile frame is missing).
     */
    fun capturePicker(
        tile: ChromeRect,
        bar: ChromeRect,
        panelHeight: Float,
        viewportWidth: Float,
        viewportHeight: Float,
        safeLeading: Float,
        safeTrailing: Float,
        safeTop: Float,
        safeBottom: Float,
        ceilingY: Float = 0f,
        preferredWidth: Float = LiveChromeMetrics.CAPTURE_PICKER_MAX_WIDTH,
        gap: Float = LiveChromeMetrics.POPUP_GAP,
    ): Box {
        val hasBar = bar.width > 1f
        val widthPref = if (hasBar) min(bar.width, preferredWidth) else preferredWidth
        val (minX, maxX, width) =
            horizontalBand(
                preferredWidth = widthPref,
                viewportWidth = viewportWidth,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                margin = EDGE_MARGIN,
            )
        val midX =
            when {
                tile.width > 1f -> tile.midX
                hasBar -> bar.midX
                else -> viewportWidth / 2f
            }
        val x = leadingX(desired = midX - width / 2f, width = width, minX = minX, maxX = maxX)
        val minY = max(EDGE_MARGIN, max(safeTop + ASSIST_TOP_INSET, ceilingY))
        val boxBottom =
            (if (hasBar) bar.minY else viewportHeight - max(EDGE_MARGIN, safeBottom)) - gap
        val maxHeight = max(0f, boxBottom - minY)
        val height = min(max(0f, panelHeight), maxHeight)
        val y = max(minY, boxBottom - height)
        return Box(x = x, y = y, width = width, maxHeight = maxHeight)
    }

    /**
     * OpenZCine `AssistOptionsPopupAnchor`: card above the toolbar, trailing-aligned
     * to the pressed chip, island clearance. Never a bottom-start sheet over the rail.
     */
    fun assistOptions(
        icon: ChromeRect,
        toolbar: ChromeRect,
        preferredWidth: Float,
        panelHeight: Float,
        viewportWidth: Float,
        viewportHeight: Float,
        safeLeading: Float,
        safeTrailing: Float,
        safeTop: Float,
        safeBottom: Float,
        ceilingY: Float = 0f,
        gap: Float = LiveChromeMetrics.POPUP_GAP,
    ): Box {
        val minX =
            maxOf(
                LiveChromeMetrics.CHROME_LEADING,
                safeLeading + CUTOUT_CLEARANCE,
                ASSIST_MARGIN,
            )
        val maxX =
            viewportWidth -
                maxOf(LiveChromeMetrics.CHROME_TRAILING, safeTrailing + CUTOUT_CLEARANCE, ASSIST_MARGIN)
        val width = max(0f, min(preferredWidth, maxX - minX))
        val hasIcon = icon.width > 1f && icon.height > 1f
        val hasToolbar = toolbar.width > 1f && toolbar.height > 1f
        val desiredX =
            when {
                hasIcon -> icon.maxX - width
                hasToolbar -> toolbar.maxX - width
                else -> minX
            }
        val x = leadingX(desired = desiredX, width = width, minX = minX, maxX = maxX)
        val barTop =
            when {
                hasToolbar -> toolbar.minY
                hasIcon -> icon.minY
                else -> viewportHeight - max(EDGE_MARGIN, safeBottom)
            }
        val minY = maxOf(ASSIST_MARGIN, safeTop + ASSIST_TOP_INSET, ceilingY)
        val boxBottom = barTop - gap
        val maxHeight = max(0f, boxBottom - minY)
        val height = min(max(0f, panelHeight), maxHeight)
        val y = max(minY, boxBottom - height)
        return Box(x = x, y = y, width = width, maxHeight = maxHeight)
    }
}

/** OpenZCine `topPickerBody` convenience used by tests and the landscape host. */
object LiveTopPickerPlacement {
    fun leadingX(
        cellMidX: Float,
        width: Float,
        viewportWidth: Float,
        safeLeading: Float = 0f,
        safeTrailing: Float = 0f,
    ): Float =
        LivePopupPlacement.topPicker(
            cell = ChromeRect(cellMidX - 1f, 0f, 2f, 2f),
            panelHeight = 80f,
            viewportWidth = viewportWidth,
            viewportHeight = 400f,
            safeLeading = safeLeading,
            safeTrailing = safeTrailing,
            safeTop = 0f,
            safeBottom = 0f,
            preferredWidth = width,
        ).x

    fun topY(
        cellMaxY: Float,
        panelHeight: Float,
        viewportHeight: Float,
        safeTop: Float = 0f,
        safeBottom: Float = 0f,
        floorY: Float? = null,
    ): Float =
        LivePopupPlacement.topPicker(
            cell = ChromeRect(0f, cellMaxY - 2f, 2f, 2f),
            panelHeight = panelHeight,
            viewportWidth = 400f,
            viewportHeight = viewportHeight,
            safeLeading = 0f,
            safeTrailing = 0f,
            safeTop = safeTop,
            safeBottom = safeBottom,
            floorY = floorY,
        ).y
}

/** Hold a numeric FPS string until it moves by [step] so hundredths do not tick the chip. */
object LiveChromeReadout {
    fun holdFPS(incoming: String, displayed: String, step: Double = 0.4): String {
        val next = incoming.toDoubleOrNull()
        val current = displayed.toDoubleOrNull()
        if (next == null || current == null) return incoming
        return if (abs(next - current) >= step) incoming else displayed
    }
}

/**
 * Pocket mapping onto OpenZCine's FPS chip labels. SoftAP live view is ~25 fps —
 * that is the delivery target for bars, not `CameraStatus.fps` (record format).
 */
object LiveViewLink {
    const val TARGET_FPS = 25.0

    fun cameraLinkPhase(
        connection: ConnectionPhase,
        recovering: Boolean,
        measuredFPS: Double,
    ): CameraLinkPhase {
        if (connection == ConnectionPhase.FAILED) return CameraLinkPhase.DISCONNECTED
        if (measuredFPS > 0) {
            return if (recovering) CameraLinkPhase.RECOVERING else CameraLinkPhase.STREAMING
        }
        return when (connection) {
            ConnectionPhase.IDLE -> CameraLinkPhase.DISCONNECTED
            ConnectionPhase.LIVE -> CameraLinkPhase.CONNECTED_IDLE
            else -> CameraLinkPhase.CONNECTING
        }
    }

    fun fpsChipLabel(
        connection: ConnectionPhase,
        recovering: Boolean,
        formattedFPS: String,
        measuredFPS: Double,
    ): String {
        if (connection == ConnectionPhase.FAILED) return "FAIL"
        if (recovering) return "RECOV"
        if (measuredFPS > 0) return formattedFPS
        return if (connection == ConnectionPhase.IDLE) "—" else "LINK"
    }
}

enum class CameraLinkPhase {
    DISCONNECTED,
    CONNECTING,
    CONNECTED_IDLE,
    STREAMING,
    RECOVERING,
    DEMO,
}

data class CameraLinkHealthInputs(
    val phase: CameraLinkPhase = CameraLinkPhase.DISCONNECTED,
    val ptpRoundTripMilliseconds: Double? = null,
    val liveViewFPS: Double? = null,
    val targetLiveViewFPS: Double = 30.0,
    val secondsSinceLastGoodFrame: Double? = null,
    val consecutiveBadFrames: Int = 0,
    val recentCommandFailures: Int = 0,
    val isRecoveringStream: Boolean = false,
)

data class CameraLinkHealthSnapshot(val linkHealthScore: Int, val detailCaption: String)

object CameraLinkHealthScorer {
    fun latencyScore(milliseconds: Double): Double =
        when {
            milliseconds < 30 -> 100.0
            milliseconds < 60 -> 92.0
            milliseconds < 100 -> 82.0
            milliseconds < 150 -> 68.0
            milliseconds < 250 -> 48.0
            milliseconds < 500 -> 28.0
            else -> 10.0
        }

    fun frameDeliveryScore(actualFPS: Double, targetFPS: Double): Double {
        if (actualFPS <= 0 || targetFPS <= 0) return 0.0
        return min(1.0, actualFPS / targetFPS) * 100.0
    }

    fun frameFreshnessPenalty(secondsSinceLastGoodFrame: Double?): Double {
        val s = secondsSinceLastGoodFrame ?: return 0.0
        return when {
            s < 0.5 -> 0.0
            s < 1.5 -> 8.0
            s < 3.0 -> 20.0
            s < 5.0 -> 35.0
            else -> 55.0
        }
    }

    fun badFramePenalty(consecutiveBadFrames: Int): Double =
        when {
            consecutiveBadFrames <= 0 -> 0.0
            consecutiveBadFrames <= 2 -> 6.0
            consecutiveBadFrames <= 5 -> 18.0
            consecutiveBadFrames <= 8 -> 32.0
            else -> 50.0
        }

    fun commandFailurePenalty(recentFailures: Int): Double =
        when {
            recentFailures <= 0 -> 0.0
            recentFailures == 1 -> 15.0
            recentFailures == 2 -> 30.0
            else -> 50.0
        }

    fun score(inputs: CameraLinkHealthInputs): CameraLinkHealthSnapshot {
        when (inputs.phase) {
            CameraLinkPhase.DISCONNECTED ->
                return CameraLinkHealthSnapshot(0, "Not connected")
            CameraLinkPhase.DEMO ->
                return CameraLinkHealthSnapshot(85, "Demo session")
            CameraLinkPhase.CONNECTING ->
                return CameraLinkHealthSnapshot(20, "Connecting…")
            else -> Unit
        }
        val latency = inputs.ptpRoundTripMilliseconds?.let(::latencyScore) ?: 0.0
        val fps = inputs.liveViewFPS
        val streaming =
            inputs.phase == CameraLinkPhase.STREAMING || inputs.phase == CameraLinkPhase.RECOVERING
        val frameScore =
            if (fps != null && streaming) {
                frameDeliveryScore(fps, inputs.targetLiveViewFPS)
            } else {
                0.0
            }
        val linkHealthRaw =
            if (streaming) {
                val lc = if (latency > 0) latency else 70.0
                frameScore * 0.55 + lc * 0.25 + 20.0 -
                    frameFreshnessPenalty(inputs.secondsSinceLastGoodFrame) -
                    badFramePenalty(inputs.consecutiveBadFrames) -
                    commandFailurePenalty(inputs.recentCommandFailures) -
                    if (inputs.isRecoveringStream) 25.0 else 0.0
            } else {
                val lc = if (latency > 0) latency else 60.0
                lc * 0.75 + 25.0 -
                    commandFailurePenalty(inputs.recentCommandFailures) -
                    if (inputs.isRecoveringStream) 25.0 else 0.0
            }
        return CameraLinkHealthSnapshot(
            linkHealthScore = linkHealthRaw.roundToInt().coerceIn(0, 100),
            detailCaption = "Command channel warm",
        )
    }
}

/** Rolling live-view delivery rate. Displayed rate throttles to ~1 Hz. */
class FrameRateSampler(
    windowSize: Int = 30,
    displayRefreshInterval: Double = 1.0,
) {
    private val windowSize = max(1, windowSize)
    private val displayInterval = max(0.0, displayRefreshInterval)
    private val intervals = ArrayList<Double>()
    private var lastTimestamp: Double? = null
    private var lastDisplayTimestamp: Double? = null
    var displayFPS: Double = 0.0
        private set

    fun recordFrame(at: Double) {
        val previous = lastTimestamp
        lastTimestamp = at
        if (previous == null || at <= previous) return
        intervals.add(at - previous)
        if (intervals.size > windowSize) intervals.removeAt(0)
        val last = lastDisplayTimestamp
        if (last != null && at - last < displayInterval) return
        displayFPS = currentFPS
        lastDisplayTimestamp = at
    }

    /** Instantaneous Hz from a present counter over a wall-clock window. */
    fun recordFrameRate(fps: Double) {
        displayFPS = fps.coerceAtLeast(0.0)
    }

    val intervalCount: Int get() = intervals.size

    val currentFPS: Double
        get() {
            if (intervals.isEmpty()) return 0.0
            val average = intervals.sum() / intervals.size
            return 1.0 / average
        }

    val formatted: String get() = String.format("%.2f", displayFPS)
}

/** 0–4 bars from the 0–100 link-health score, with hysteresis. */
class LinkSignalBars(hysteresisMargin: Int = 6) {
    var bars: Int = 0
        private set
    private val margin = max(0, hysteresisMargin)

    fun update(score: Int): Int {
        val raw = rawBars(score)
        when {
            raw == bars -> Unit
            bars == 0 || raw == 0 -> bars = raw
            raw > bars -> if (score >= floorScore(raw) + margin) bars = raw
            else -> if (score < floorScore(bars) - margin) bars = raw
        }
        return bars
    }

    companion object {
        private fun floorScore(of: Int): Int = 25 * (of - 1) + 1

        private fun rawBars(score: Int): Int {
            if (score <= 0) return 0
            return min(4, max(1, kotlin.math.ceil(score / 25.0).toInt()))
        }
    }
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

    val gimbalCluster: GimbalCluster
        get() {
            val inset = LiveChromeMetrics.STICK_INSET
            val gap = LiveChromeMetrics.STICK_GAP
            var barTop = Float.POSITIVE_INFINITY
            if (showsBottomBars) {
                if (assist.height > 1f) barTop = min(barTop, assist.minY)
                if (capture.height > 1f) barTop = min(barTop, capture.minY)
            }
            val floorY =
                if (barTop < Float.POSITIVE_INFINITY) min(feed.maxY - inset, barTop - gap)
                else feed.maxY - inset
            val avoid = if (record.width > 1f) record else null
            return GimbalCluster.inTrailingBottom(
                well = feed,
                floorY = floorY,
                canvasMaxY = viewportHeight - max(0f, safeBottom),
                avoid = avoid,
                stickSize = LiveChromeMetrics.STICK,
                zoomSize = LiveChromeMetrics.ZOOM,
                gap = gap,
                inset = inset,
            )
        }

    val zoomButton: ChromeRect
        get() = gimbalCluster.zoom

    val gimbalStick: ChromeRect
        get() = gimbalCluster.stick

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
            chromeScale: Float = 1f,
            pictureAspect: Float? = null,
        ): LiveMonitorLayout {
            LiveChromeMetrics.scale = chromeScale
            val vw = max(0f, viewportWidth)
            val vh = max(0f, viewportHeight)
            val constrained = isWidthConstrained(vw, vh)
            val chrome = chromeRect(vw, vh)
            val feed = feedFrame(vw, vh, safeLeading, safeTrailing)
            val picture =
                pictureFrame(
                    aspect = pictureAspect ?: LiveChromeMetrics.FEED_ASPECT,
                    well = feed,
                    viewportWidth = vw,
                    viewportHeight = vh,
                    safeLeading = safeLeading,
                    safeTrailing = safeTrailing,
                )
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

        /**
         * Center the displayed raster in the cinema well. A 9:16 Pocket flip
         * pillarboxes here so the rail — keyed off the 16:9 well — never moves.
         */
        fun pictureFrame(
            aspect: Float,
            well: ChromeRect,
            viewportWidth: Float,
            viewportHeight: Float,
            safeLeading: Float,
            safeTrailing: Float,
        ): ChromeRect {
            val ratio = if (aspect > 0.2f) aspect else LiveChromeMetrics.FEED_ASPECT
            if (well.width < 1f || well.height < 1f) return well
            if (abs(ratio - LiveChromeMetrics.FEED_ASPECT) < 0.02f) return well
            val vw = max(0f, viewportWidth)
            val vh = max(0f, viewportHeight)
            if (vh > vw || vh <= 0f) return well
            var width = vh * ratio
            var height = vh
            if (width > vw + 0.5f) {
                width = vw
                height = vw / ratio
            }
            val lead = if (safeLeading >= LiveChromeMetrics.CUTOUT_MIN) safeLeading else 0f
            val trail = if (safeTrailing >= LiveChromeMetrics.CUTOUT_MIN) safeTrailing else 0f
            val minX = lead
            val maxX = max(minX, vw - trail - width)
            val x = min(max((vw - width) / 2f, minX), maxX)
            val y = (vh - height) / 2f
            return ChromeRect(x, y, width, height)
        }

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
            val xWanted =
                if (isClassicNotch(safeLeading, safeTrailing)) {
                    val available = max(0f, remaining - max(0f, safeLeading) - max(0f, safeTrailing))
                    val shift = min(LiveChromeMetrics.CLASSIC_NOTCH_SHIFT, available)
                    min(remaining, safeLeading + shift)
                } else {
                    min(remaining, leadingInset)
                }
            // S25 leftover 140. Reserve the rail plus a few dp so record
            // clears the picture without parking the well in the lock lane.
            // Auditor 874×402 still pins x at 59.
            val trailLane = LiveChromeMetrics.RAIL_W + 8f
            val x = min(xWanted, max(0f, remaining - trailLane))
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
                // Prefer clipping the screen edge over covering the picture.
                // Hug-to-chrome.maxX jumped ~20 dp onto the feed when the lane
                // was only a couple of dp short of RAIL_W.
                ChromeRect(laneX, chrome.minY, railWidth, chrome.height)
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
            val y = vh - LiveChromeMetrics.BOTTOM_INSET - LiveChromeMetrics.CONTROL_H
            val split = bottomBarSplit(barsWidth, gap, LiveChromeMetrics.CAPTURE_HUG)
            val capture = ChromeRect(chrome.minX + barsWidth - split.captureWidth, y, split.captureWidth, LiveChromeMetrics.CONTROL_H)
            val assist = ChromeRect(chrome.minX, y, split.assistWidth, LiveChromeMetrics.CONTROL_H)
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
            .size(LiveChromeMetrics.LOCK.dp)
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
        OpcIcon(
            icon = OpcIcon.LOCK,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(16.dp),
        )
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
            .width(LiveChromeMetrics.DISP_W.dp)
            .height(LiveChromeMetrics.DISP_H.dp)
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
            .size(LiveChromeMetrics.AUX.dp)
            .monitorGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { role = Role.Button },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size((LiveChromeMetrics.AUX * 0.36f).dp),
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
    photo: Boolean = false,
    onClick: () -> Unit,
) {
    var confirmOpen by remember { mutableStateOf(false) }
    if (confirmOpen) {
        Dialog(
            onDismissRequest = { confirmOpen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .chromeClickable(onClick = { confirmOpen = false }),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                        .pickerPanelGlass(ChromeShape)
                        .padding(horizontal = 18.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (recording) "Stop recording?" else "Start recording?",
                        color = LiveDesign.text,
                        style = LiveType.ui(16f, FontWeight.SemiBold),
                    )
                    Text(
                        if (recording) "Stop" else "Start",
                        color = if (recording) LiveDesign.rec else LiveDesign.accent,
                        style = LiveType.ui(16f, FontWeight.SemiBold),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .chromeClickable(onClick = {
                                    confirmOpen = false
                                    onClick()
                                })
                                .padding(vertical = 14.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Text(
                        "Cancel",
                        color = LiveDesign.muted,
                        style = LiveType.ui(15f, FontWeight.Medium),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .chromeClickable(onClick = { confirmOpen = false })
                                .padding(vertical = 12.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
        }
    }
    Box(
        modifier
            .size(LiveChromeMetrics.RECORD.dp)
            .then(if (recording && !enabled) Modifier.graphicsLayer { alpha = 0.72f } else Modifier)
            .shadow(2.dp, CircleShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.40f))
            .chromeClickable(enabled = enabled, onClick = { if (confirm) confirmOpen = true else onClick() })
            .semantics {
                contentDescription =
                    when {
                        photo -> "Take photo"
                        recording -> "Stop recording"
                        else -> "Start recording"
                    }
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

/** iOS `LiveBatteryRow` outline: 26×15 body, nub drawn outside the trailing edge. */
internal const val BATTERY_CELL_W_DP = 26f
internal const val BATTERY_CELL_H_DP = 15f

@Composable
private fun BatteryOutlineRow(percent: Int, charging: Boolean, camera: Boolean) {
    val tint =
        when {
            percent < 0 -> LiveDesign.faint
            percent <= 20 -> LiveDesign.rec
            percent <= 40 -> LiveDesign.amber
            else -> LiveDesign.good
        }
    val readout = if (percent < 0) "—" else "$percent"
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(10.dp), contentAlignment = Alignment.Center) {
            if (camera) CameraGlyph(LiveDesign.muted, Modifier.size(12.dp, 10.dp))
            else PhoneGlyph(LiveDesign.muted, Modifier.size(7.dp, 11.dp))
        }
        Box(Modifier.size(BATTERY_CELL_W_DP.dp, BATTERY_CELL_H_DP.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(horizontal = 2.dp, vertical = 1.dp)
                    .clip(RoundedCornerShape(2.5.dp)),
                contentAlignment = Alignment.Center,
            ) {
                ScaleToFit(minScale = 0.65f, modifier = Modifier.fillMaxSize()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(1.dp),
                    ) {
                        if (charging) BoltGlyph(tint, Modifier.size(5.dp, 7.dp))
                        Text(
                            readout,
                            color = tint,
                            style =
                                LiveType.ui(10f, FontWeight.Medium).copy(
                                    color = tint,
                                    fontFeatureSettings = "tnum",
                                    lineHeight = 10.sp,
                                    lineHeightStyle =
                                        LineHeightStyle(
                                            alignment = LineHeightStyle.Alignment.Center,
                                            trim = LineHeightStyle.Trim.Both,
                                        ),
                                    platformStyle = PlatformTextStyle(includeFontPadding = false),
                                ),
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Clip,
                        )
                    }
                }
            }
            Canvas(Modifier.fillMaxSize()) {
                drawRoundRect(
                    tint.copy(alpha = 0.85f),
                    cornerRadius = CornerRadius(3.5.dp.toPx()),
                    style = Stroke(1.2.dp.toPx()),
                )
            }
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .offset(x = 3.dp)
                    .size(1.6.dp, 6.dp)
                    .background(tint.copy(alpha = 0.85f), RoundedCornerShape(1.dp)),
            )
        }
    }
}

@Composable
private fun BoltGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val path =
            Path().apply {
                moveTo(w * 0.62f, 0f)
                lineTo(w * 0.08f, h * 0.55f)
                lineTo(w * 0.46f, h * 0.55f)
                lineTo(w * 0.38f, h)
                lineTo(w * 0.92f, h * 0.42f)
                lineTo(w * 0.54f, h * 0.42f)
                close()
            }
        drawPath(path, tint)
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
    val incoming = timecode?.takeIf { it.isNotBlank() }
    val clock =
        incoming?.let { value ->
            val parts = value.split(':')
            if (parts.size >= 4) parts.take(3).joinToString(":") else value
        } ?: if (portrait) "00:00:00" else "--:--:--"
    val raw = clock
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
                .padding(horizontal = 11.dp, vertical = 7.dp)
                .semantics {
                    contentDescription = "Live view $fps frames per second, $bars of 4 signal bars"
                },
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
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    accessibilityLabel: String? = null,
    icon: @Composable (Color) -> Unit,
) {
    val surface =
        if (active) {
            Modifier.background(LiveDesign.accentDim, CircleShape).border(1.dp, LiveDesign.accentDim, CircleShape)
        } else {
            Modifier.chipGlass(CircleShape)
        }
    val spoken =
        accessibilityLabel?.let { label ->
            "$label ${value.replace(" · ", "·")}"
        }
    Row(
        modifier =
            modifier
                .then(surface)
                .wrapContentWidth(unbounded = true)
                .then(
                    if (onClick != null) {
                        Modifier.chromeClickable(enabled = enabled, onClick = onClick, onLongClick = onLongClick)
                    } else {
                        Modifier
                    },
                )
                .then(
                    if (spoken != null) {
                        Modifier.semantics(mergeDescendants = true) { contentDescription = spoken }
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
    modifier: Modifier = Modifier,
    showFacePriorityBadge: Boolean = false,
    valueIcon: (@Composable (Color) -> Unit)? = null,
    onClick: () -> Unit,
) {
    val labelColor = if (active) LiveDesign.accent.copy(alpha = 0.85f) else LiveDesign.muted
    val valueColor = if (active) LiveDesign.accent else LiveDesign.text
    Column(
        modifier =
            modifier
                .clip(ChromeShape)
                .background(if (active) LiveDesign.accentDim else Color.Transparent)
                .then(
                    if (active) Modifier.border(1.dp, LiveDesign.accentDim, ChromeShape) else Modifier,
                )
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 4.dp, vertical = 5.dp)
                .then(
                    if (showFacePriorityBadge) {
                        Modifier.semantics {
                            contentDescription = "$label $value, ${CaptureLists.FACE_PRIORITY_TITLE}"
                        }
                    } else {
                        Modifier
                    },
                ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = labelColor, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
            if (showFacePriorityBadge) FacePrioritySmile(labelColor)
        }
        Box(contentAlignment = Alignment.Center) {
            Text(
                widest,
                color = Color.Transparent,
                style = LiveType.ui(17f, FontWeight.Medium),
                maxLines = 1,
            )
            if (valueIcon != null) {
                valueIcon(valueColor)
            } else {
                Text(value, color = valueColor, style = LiveType.ui(17f, FontWeight.Medium), maxLines = 1)
            }
        }
    }
}

/** iOS `face.smiling.fill` stand-in until Lucide. */
@Composable
private fun FacePrioritySmile(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(11.dp)) {
        val stroke = 1.2.dp.toPx()
        val r = size.minDimension / 2f
        val c = Offset(size.width / 2f, size.height / 2f)
        drawCircle(tint, r - stroke / 2f, c, style = Stroke(stroke))
        val eyeY = c.y - r * 0.22f
        val eyeOff = r * 0.28f
        drawCircle(tint, stroke * 0.65f, Offset(c.x - eyeOff, eyeY))
        drawCircle(tint, stroke * 0.65f, Offset(c.x + eyeOff, eyeY))
        drawArc(
            color = tint,
            startAngle = 20f,
            sweepAngle = 140f,
            useCenter = false,
            topLeft = Offset(c.x - r * 0.45f, c.y - r * 0.1f),
            size = Size(r * 0.9f, r * 0.85f),
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}

@Composable
fun AssistToolChip(label: String, on: Boolean, enabled: Boolean, stub: Boolean, onClick: () -> Unit) {
    Column(
        modifier =
            Modifier.clip(ChromeShape)
                .background(if (on) LiveDesign.accentDim else Color.Transparent, ChromeShape)
                .border(1.dp, if (on) LiveDesign.accent else Color.Transparent, ChromeShape)
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
    val knobRatio = LiveDesign.GIMBAL_KNOB_DP / LiveDesign.GIMBAL_STICK_DP
    var knobOffset by remember { mutableStateOf(Offset.Zero) }
    val scope = rememberCoroutineScope()
    var recenterJob by remember { mutableStateOf<Job?>(null) }
    Box(
        modifier
            .fillMaxSize()
            .semantics { contentDescription = "Gimbal stick" }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                val stickPx = min(this.size.width, this.size.height).toFloat()
                val travel = (stickPx - stickPx * knobRatio) / 2f
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
            val stickPx = size.minDimension
            val knobPx = stickPx * knobRatio
            val stroke = 2.dp.toPx()
            drawCircle(
                color = Color.White.copy(alpha = 0.30f),
                radius = stickPx / 2f - stroke / 2f,
                style = Stroke(width = stroke),
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.30f),
                radius = knobPx / 2f,
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
        OpcIcon(
            icon = OpcIcon.CROSSHAIR,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(18.dp),
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
