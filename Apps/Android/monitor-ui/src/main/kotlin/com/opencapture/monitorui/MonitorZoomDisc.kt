package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.waterfall
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin
import kotlinx.coroutines.delay

private data class ZoomGestureGeometry(
    val width: Int,
    val height: Int,
    val density: Float,
    val fontScale: Float,
    val layoutDirection: LayoutDirection,
    val safeInsets: IntRect,
    val trailingInset: Float,
    val maximum: Double,
)

/** Native insets are available before Compose's lazy inset holder first dispatch. */
@Suppress("DEPRECATION")
private fun physicalZoomInsets(view: android.view.View, observed: IntRect): IntRect {
    val insets = view.rootWindowInsets ?: return observed
    val bars = if (android.os.Build.VERSION.SDK_INT >= 30) {
        insets.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.systemBars() or
            android.view.WindowInsets.Type.displayCutout())
    } else android.graphics.Insets.of(insets.stableInsetLeft, insets.stableInsetTop,
        insets.stableInsetRight, insets.stableInsetBottom)
    val cutout = insets.displayCutout
    val waterfall = if (android.os.Build.VERSION.SDK_INT >= 30) cutout?.waterfallInsets else null
    return IntRect(maxOf(bars.left, cutout?.safeInsetLeft ?: 0, waterfall?.left ?: 0),
        maxOf(bars.top, cutout?.safeInsetTop ?: 0, waterfall?.top ?: 0),
        maxOf(bars.right, cutout?.safeInsetRight ?: 0, waterfall?.right ?: 0),
        maxOf(bars.bottom, cutout?.safeInsetBottom ?: 0, waterfall?.bottom ?: 0))
}

/** Edge-mounted logarithmic scale. Camera limits, labels and writes belong to the adapter. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MonitorZoomDisc(initial: Double, maximum: Double, label: (Double) -> String,
    onChange: (Double) -> Unit, onDismiss: () -> Unit,
    foreground: @Composable BoxScope.() -> Unit = {},
    opticalStops: List<Double> = listOf(1.0), caption: (Double) -> String = { "ZOOM" },
    trailingInset: Float = 0f) {
    val maxZoom = maximum.takeIf { it.isFinite() }?.coerceAtLeast(1.0) ?: 1.0
    val logMax = ln(maxZoom).coerceAtLeast(.001)
    val initialValue = initial.takeIf { it.isFinite() }?.coerceIn(1.0, maxZoom) ?: 1.0
    var position by remember { mutableFloatStateOf((ln(initialValue) / logMax).toFloat()) }
    var entering by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    val motion by animateFloatAsState(if (entering && !closing) 1f else 0f,
        tween(if (closing) 180 else 260), label = "zoom-disc")
    val send by rememberUpdatedState(onChange)
    val dismiss by rememberUpdatedState(onDismiss)
    LaunchedEffect(Unit) { entering = true }
    LaunchedEffect(closing) { if (closing) { delay(180); dismiss() } }
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val layoutDirection = LocalLayoutDirection.current
    // A focused overlay may reveal transient system bars. Physical geometry
    // ignores that visibility change while still observing cutout/waterfall
    // changes on foldables and differently oriented displays.
    val safeInsets = WindowInsets.systemBarsIgnoringVisibility
        .union(WindowInsets.displayCutout).union(WindowInsets.waterfall)
    val geometry = ZoomGestureGeometry(configuration.screenWidthDp, configuration.screenHeightDp,
        density.density, density.fontScale, layoutDirection,
        physicalZoomInsets(LocalView.current,
            IntRect(safeInsets.getLeft(density, layoutDirection), safeInsets.getTop(density),
                safeInsets.getRight(density, layoutDirection), safeInsets.getBottom(density))),
        trailingInset, maxZoom)
    val openingGeometry = remember { geometry }
    if (geometry != openingGeometry) {
        // A pointer belongs to the geometry where it began. Remove the window
        // before another event can reuse its angular origin after a resize or
        // cutout/range change; the adapter ends its existing camera transaction.
        LaunchedEffect(geometry) { dismiss() }
        return
    }
    val tablet = minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600
    val radius = minOf(if (tablet) 330f else 260f,
        (configuration.screenHeightDp - 24f) / 2).coerceAtLeast(120f)
    val factor = exp(position * logMax).coerceIn(1.0, maxZoom)
    val optical = opticalStops.any { abs(it - factor) < .05 }
    val accent = if (optical) MonitorPalette.accent else Color(0xFFF0B23C)
    val textMeasurer = rememberTextMeasurer()
    fun update(next: Float) {
        if (!next.isFinite() || closing) return
        position = next.coerceIn(0f, 1f)
        send(exp(position * logMax).coerceIn(1.0, maxZoom))
    }
    val provider = remember { object : PopupPositionProvider {
        override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
            layoutDirection: LayoutDirection, popupContentSize: IntSize) = IntOffset(
            0, 0)
    } }
    Popup(popupPositionProvider = provider, onDismissRequest = { closing = true },
        properties = PopupProperties(focusable = true, dismissOnClickOutside = true, clippingEnabled = false)) {
        // The app can keep critical foreground controls above the scale. The
        // popup's focused accessibility window contains those same actions.
        Box(Modifier.size(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp)
            .pointerInput(Unit) { detectTapGestures { closing = true } }) {
            Box(Modifier.align(Alignment.CenterEnd).padding(end = trailingInset.dp).size(radius.dp, (radius * 2).dp)
                .graphicsLayer { translationX = size.width * (1f - motion); alpha = motion }
                .background(Color(0xFF121416).copy(alpha = .72f),
                    RoundedCornerShape(topStart = radius.dp, bottomStart = radius.dp))) {
                Canvas(Modifier.fillMaxSize().semantics {
                    contentDescription = "Zoom ${label(factor)}"
                    progressBarRangeInfo = ProgressBarRangeInfo(position, 0f..1f)
                    setProgress { update(it); true }
                    customActions = listOf(CustomAccessibilityAction("Close zoom") { closing = true; true })
                }.pointerInput(Unit) { detectTapGestures { } }.pointerInput(geometry) {
                    var startAngle = 0.0
                    var startPosition = 0f
                    fun angle(point: Offset) = atan2((size.width - point.x).toDouble(),
                        (point.y - size.height / 2f).toDouble())
                    var dragging = false
                    try {
                        detectDragGestures(
                            onDragStart = { dragging = true; startAngle = angle(it); startPosition = position },
                            onDragEnd = { dragging = false },
                            onDragCancel = {
                                // A tap recognizer may consume an unarmed
                                // pointer, including the hold that opened us.
                                if (dragging) { dragging = false; dismiss() }
                            },
                        ) { change, _ ->
                            change.consume()
                            update(startPosition - ((angle(change.position) - startAngle) / (210 * PI / 180)).toFloat())
                        }
                    } finally {
                        // Disposal and geometry cancellation can interrupt the
                        // detector before onDragCancel. Close exactly this dial
                        // so its adapter releases the active zoom transaction.
                        if (dragging) dismiss()
                    }
                }) {
                    val scale = size.width / 190f
                    val center = Offset(size.width, size.height / 2)
                    fun point(angle: Double, r: Float) = Offset(center.x - r * scale * sin(angle).toFloat(),
                        center.y + r * scale * cos(angle).toFloat())
                    val arcRadius = 186f * scale
                    drawArc(Color.White.copy(alpha = .07f), 90f, 180f, false,
                        Offset(center.x - arcRadius, center.y - arcRadius), Size(arcRadius * 2, arcRadius * 2),
                        style = Stroke(1.5f * scale))
                    val window = .36 * PI
                    fun alpha(angle: Double) = ((window - abs(angle - PI / 2)) / (.3 * window)).toFloat().coerceIn(0f, 1f)
                    fun angle(t: Double) = PI / 2 + (t - position) * (210 * PI / 180)
                    repeat(49) { index ->
                        val a = angle(index / 48.0)
                        if (abs(a - PI / 2) <= window) drawLine(Color.White.copy(alpha = .3f * alpha(a)),
                            point(a, 164f), point(a, 155f), 1.2f * scale, StrokeCap.Round)
                    }
                    listOf(1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0).filter { it <= maxZoom }.forEach { value ->
                        val a = angle(ln(value) / logMax)
                        if (abs(a - PI / 2) <= window) {
                            drawLine(Color.White.copy(alpha = .7f * alpha(a)), point(a, 164f), point(a, 143f),
                                2.2f * scale, StrokeCap.Round)
                            val near = ((abs(a - PI / 2) - .035) / .075).toFloat().coerceIn(0f, 1f)
                            val measured = textMeasurer.measure(label(value), MonitorTypography.readout(12f, FontWeight.SemiBold))
                            drawText(measured, Color.White.copy(alpha = .78f * alpha(a) * near),
                                topLeft = point(a, 124f) - Offset(measured.size.width / 2f, measured.size.height / 2f))
                        }
                    }
                    drawLine(accent, Offset(14f * scale, center.y), Offset(46f * scale, center.y),
                        3f * scale, StrokeCap.Round)
                    drawCircle(accent, 3.5f * scale, Offset(52f * scale, center.y))
                }
                Column(Modifier.align(Alignment.CenterEnd).padding(start = (radius * .42f).dp, end = (radius * .04f).dp),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(label(factor), style = MonitorTypography.readout(radius * .19f, FontWeight.Bold))
                    Text(caption(factor), style = MonitorTypography.text(10f, FontWeight.Medium), color = accent)
                }
            }
            foreground()
        }
    }
}
