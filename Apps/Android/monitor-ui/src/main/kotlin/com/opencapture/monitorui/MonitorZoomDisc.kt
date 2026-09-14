package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
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
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.PI
import kotlin.math.abs
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
    val attachment: MonitorZoomAttachment,
    val bottomClearance: Float,
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
    opticalStops: List<Double> = listOf(1.0), caption: (Double) -> String = { "ZOOM" },
    trailingInset: Float = 0f, attachment: MonitorZoomAttachment = MonitorZoomAttachment.Trailing,
    bottomClearance: Float = 0f, onDetent: () -> Unit = {}) {
    val maxZoom = maximum.takeIf { it.isFinite() }?.coerceAtLeast(1.0) ?: 1.0
    val logMax = ln(maxZoom).coerceAtLeast(.001)
    val initialValue = initial.takeIf { it.isFinite() }?.coerceIn(1.0, maxZoom) ?: 1.0
    var position by remember { mutableFloatStateOf((ln(initialValue) / logMax).toFloat()) }
    var entering by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    val motion by animateFloatAsState(if (entering && !closing) 1f else 0f,
        tween(if (closing) MonitorMotion.ZOOM_OUT_MS else MonitorMotion.ZOOM_IN_MS,
            easing = if (closing) MonitorMotion.ZoomOut else MonitorMotion.Soft), label = "zoom-disc")
    val send by rememberUpdatedState(onChange)
    val dismiss by rememberUpdatedState(onDismiss)
    val detent by rememberUpdatedState(onDetent)
    LaunchedEffect(Unit) { entering = true }
    LaunchedEffect(closing) { if (closing) { delay(MonitorMotion.ZOOM_HOST_MS.toLong()); dismiss() } }
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
        trailingInset, attachment, bottomClearance, maxZoom)
    val openingGeometry = remember { geometry }
    if (geometry != openingGeometry) {
        // A pointer belongs to the geometry where it began. Remove the window
        // before another event can reuse its angular origin after a resize or
        // cutout/range change; the adapter ends its existing camera transaction.
        LaunchedEffect(geometry) { dismiss() }
        return
    }
    val physicalTrailingInset = geometry.safeInsets.right / density.density
    val physicalBottomInset = geometry.safeInsets.bottom / density.density
    val availableHeight = configuration.screenHeightDp.toFloat() -
        if (attachment == MonitorZoomAttachment.Bottom) bottomClearance.coerceAtLeast(0f) else 0f
    val disc = MonitorZoomGeometry.layout(
        configuration.screenWidthDp.toFloat(),
        availableHeight,
        trailingInset = maxOf(trailingInset,
            if (physicalTrailingInset > 0f) physicalTrailingInset + 6f else 0f),
        bottomInset = if (attachment == MonitorZoomAttachment.Bottom) physicalBottomInset else 0f,
        attachment = attachment,
    )
    val radius = disc.radius
    val pixelDisc = MonitorZoomGeometry(
        radius * density.density, disc.edgeExtension * density.density, disc.attachment)
    val factor = exp(position * logMax).coerceIn(1.0, maxZoom)
    val optical = opticalStops.any { abs(it - factor) < .05 }
    val accent = if (optical) MonitorPalette.accent else MonitorPalette.digitalCrop
    val textMeasurer = rememberTextMeasurer()
    fun update(next: Float) {
        if (!next.isFinite() || closing) return
        val unconstrained = MonitorZoomScale.quantized(
            exp(next.toDouble().coerceIn(0.0, 1.0) * logMax).coerceIn(1.0, maxZoom),
            maximum = maxZoom)
        val current = MonitorZoomScale.quantized(
            exp(position.toDouble().coerceIn(0.0, 1.0) * logMax).coerceIn(1.0, maxZoom),
            maximum = maxZoom)
        val factor = MonitorZoomScale.slowSnap(unconstrained, current, maximum = maxZoom)
        if (MonitorDialHaptic.shouldTick(current, factor, MonitorZoomScale.wholeStops)) detent()
        position = MonitorZoomScale.position(factor, 1.0, maxZoom).toFloat()
        send(factor)
    }
    val provider = remember { object : PopupPositionProvider {
        override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
            layoutDirection: LayoutDirection, popupContentSize: IntSize) = IntOffset(
            0, 0)
    } }
    Popup(popupPositionProvider = provider, onDismissRequest = { closing = true },
        properties = PopupProperties(focusable = true, dismissOnClickOutside = true, clippingEnabled = false)) {
        // A focused modal window owns input above every underlying control.
        Box(Modifier.size(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp)
            .pointerInput(Unit) { detectTapGestures { closing = true } }) {
            Box(Modifier.align(
                if (attachment == MonitorZoomAttachment.Bottom) Alignment.BottomCenter
                else Alignment.CenterEnd
            ).padding(bottom = if (attachment == MonitorZoomAttachment.Bottom) bottomClearance.dp else 0.dp)
                .size(disc.width.dp, disc.height.dp)
                .graphicsLayer {
                    val restScale = if (closing) .90f else .88f
                    scaleX = restScale + (1f - restScale) * motion
                    scaleY = scaleX
                    if (attachment == MonitorZoomAttachment.Bottom) {
                        translationY = size.height * .26f * (1f - motion)
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(.5f, 1f)
                    } else {
                        translationX = size.width * .26f * (1f - motion)
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(1f, .5f)
                    }
                    alpha = motion }
                .monitorMaterial(MonitorMaterial.Zoom, MonitorZoomDiscShape(attachment))) {
                Canvas(Modifier.fillMaxSize().semantics {
                    contentDescription = "Zoom ${MonitorZoomScale.dialLabel(factor, maximum = maxZoom)}"
                    progressBarRangeInfo = ProgressBarRangeInfo(position, 0f..1f)
                    setProgress { update(it); true }
                    customActions = listOf(CustomAccessibilityAction("Close zoom") { closing = true; true })
                }.pointerInput(pixelDisc) {
                    detectTapGestures { if (!pixelDisc.contains(it.x, it.y)) closing = true }
                }.pointerInput(geometry, closing) {
                    if (closing) return@pointerInput
                    var radial: MonitorZoomRadialGesture? = null
                    var startPosition = 0f
                    var dragging = false
                    try {
                        detectDragGestures(
                            orientationLock = null,
                            onDragStart = { down, slopTrigger, _ ->
                                // Admission belongs to the original down, not a
                                // later slop event that may have entered the disc.
                                radial = MonitorZoomRadialGesture(pixelDisc, down.position.x, down.position.y)
                                radial?.rebase(slopTrigger.position.x, slopTrigger.position.y)
                                dragging = radial?.isArmed == true
                                startPosition = position
                            },
                            onDragEnd = { _ -> dragging = false; radial = null },
                            onDragCancel = {
                                // A tap recognizer may consume an unarmed
                                // pointer, including the hold that opened us.
                                if (dragging) { dragging = false; dismiss() }
                            },
                        ) { change, _ ->
                            change.consume()
                            if (dragging) radial?.angleDelta(change.position.x, change.position.y)?.let { delta ->
                                update(startPosition - (delta / (210 * PI / 180)).toFloat())
                            }
                        }
                    } finally {
                        // Disposal and geometry cancellation can interrupt the
                        // detector before onDragCancel. Close exactly this dial
                        // so its adapter releases the active zoom transaction.
                        if (dragging) dismiss()
                    }
                }) {
                    val scale = pixelDisc.radius / 190f
                    val center = Offset(pixelDisc.radius, pixelDisc.radius)
                    val bottom = pixelDisc.attachment == MonitorZoomAttachment.Bottom
                    fun point(angle: Double, r: Float) = if (bottom) Offset(
                        center.x - r * scale * cos(angle).toFloat(),
                        center.y - r * scale * sin(angle).toFloat(),
                    ) else Offset(center.x - r * scale * sin(angle).toFloat(),
                        center.y + r * scale * cos(angle).toFloat())
                    val arcRadius = 186f * scale
                    drawArc(Color.White.copy(alpha = .07f), if (bottom) 180f else 90f, 180f, false,
                        Offset(center.x - arcRadius, center.y - arcRadius), Size(arcRadius * 2, arcRadius * 2),
                        style = Stroke(1.5f * scale))
                    val window = .36 * PI
                    fun alpha(angle: Double) = ((window - abs(angle - PI / 2)) / (.3 * window)).toFloat().coerceIn(0f, 1f)
                    fun angle(t: Double) = PI / 2 + (t - position) * MonitorZoomScale.ANGULAR_SPAN
                    fun stroke(t: Double, major: Boolean) {
                        val a = angle(t)
                        val delta = a - PI / 2
                        if (abs(delta) > window) return
                        val tick = MonitorZoomScale.valueAt(t, 1.0, maxZoom)
                        val digital = tick > (opticalStops.maxOrNull() ?: 1.0) + .02
                        val color = if (digital) MonitorPalette.digitalCrop else Color.White
                        drawLine(color.copy(alpha = (if (major) .7f else .3f) * alpha(a)),
                            point(a, 164f), point(a, if (major) 143f else 155f),
                            (if (major) 2.2f else 1.2f) * scale, StrokeCap.Round)
                    }
                    val labeled = MonitorZoomScale.labeledTicks.filter { it in 1.0..maxZoom }
                    val majors = labeled.map { MonitorZoomScale.position(it, 1.0, maxZoom) }
                    for (t in MonitorZoomScale.minorTickPositions()) {
                        if (majors.none { abs(it - t) < 0.012 }) stroke(t, false)
                    }
                    for (tick in labeled) {
                        val t = MonitorZoomScale.position(tick, 1.0, maxZoom)
                        stroke(t, true)
                        val a = angle(t)
                        if (abs(a - PI / 2) > window) continue
                        val near = ((abs(a - PI / 2) - .035) / .075).toFloat().coerceIn(0f, 1f)
                        val measured = textMeasurer.measure(
                            label(tick), MonitorTypography.readout(12f, FontWeight.SemiBold))
                        drawText(measured, Color.White.copy(alpha = .78f * alpha(a) * near),
                            topLeft = point(a, 124f) - Offset(measured.size.width / 2f, measured.size.height / 2f))
                    }
                    if (bottom) {
                        drawLine(accent, Offset(center.x, 14f * scale), Offset(center.x, 46f * scale),
                            3f * scale, StrokeCap.Round)
                        drawCircle(accent, 3.5f * scale, Offset(center.x, 52f * scale))
                    } else {
                        drawLine(accent, Offset(14f * scale, center.y), Offset(46f * scale, center.y),
                            3f * scale, StrokeCap.Round)
                        drawCircle(accent, 3.5f * scale, Offset(52f * scale, center.y))
                    }
                }
                Column(Modifier.align(
                    if (attachment == MonitorZoomAttachment.Bottom) Alignment.TopCenter
                    else Alignment.CenterEnd
                ).padding(
                    start = if (attachment == MonitorZoomAttachment.Bottom) 0.dp else (radius * .42f).dp,
                    top = if (attachment == MonitorZoomAttachment.Bottom) (radius * .42f).dp else 0.dp,
                    end = if (attachment == MonitorZoomAttachment.Bottom) 0.dp
                    else (radius * .04f + disc.edgeExtension).dp,
                ),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(MonitorZoomScale.dialLabel(factor, maximum = maxZoom),
                        style = MonitorTypography.readout(radius * .19f, FontWeight.Bold))
                    Text(caption(factor), style = MonitorTypography.text(10f, FontWeight.Medium), color = accent)
                }
            }
        }
    }
}

/** One closed outline, so the scale and cutout extension share one material pass. */
private class MonitorZoomDiscShape(
    private val attachment: MonitorZoomAttachment,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val controlFactor = .5522847498f
        return Outline.Generic(Path().apply {
            if (attachment == MonitorZoomAttachment.Bottom) {
                val radius = size.width / 2f
                val control = radius * controlFactor
                val flat = radius
                moveTo(0f, size.height)
                lineTo(0f, flat)
                cubicTo(0f, flat - control, radius - control, 0f, radius, 0f)
                cubicTo(radius + control, 0f, size.width, flat - control, size.width, flat)
                lineTo(size.width, size.height)
                close()
            } else {
                val radius = size.height / 2f
                val control = radius * controlFactor
                moveTo(size.width, 0f)
                lineTo(radius, 0f)
                cubicTo(radius - control, 0f, 0f, radius - control, 0f, radius)
                cubicTo(0f, radius + control, radius - control, size.height, radius, size.height)
                lineTo(size.width, size.height)
                close()
            }
        })
    }
}
