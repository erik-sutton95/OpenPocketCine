package com.opencapture.monitorui

import android.graphics.Paint
import android.os.Build
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.LayoutModifier
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Shared monitor engine tokens. Brand shells supply identity separately. */
object MonitorPalette {
    val background = Color(0xFF111213)
    val backgroundDeep = Color(0xFF08090A)
    val surface = Color(0xFF1A1B1C)
    /** iOS `MonitorTheme.raised` `0x222425`. */
    val tile = Color(0xFF222425)
    /** Mockup panel RGB (20,22,24). Alphas follow compact / expanded / share plates. */
    val panel = Color(20, 22, 24)
    val compactGlass = MonitorMaterial.Compact.tint
    val expandedGlass = MonitorMaterial.Expanded.tint
    /** Delivery plates. Information uses MonitorMaterial.Info; capture uses expanded. */
    val overlayPanel = MonitorMaterial.Delivery.tint
    val zoomGlass = MonitorMaterial.Zoom.tint
    val recHousing = MonitorMaterial.Record.tint
    val accent = Color(0xFF00A3E0)
    val text = Color.White
    val secondary = Color(0xFFCFD4D4)
    val muted = Color(0xFF8D9293)
    val faint = Color(0xFF5E6262)
    val border = Color.White.copy(alpha = .08f)
    val recording = Color(0xFFD13034)
    /** Digital-crop warning on the zoom chip and disc (same as the dial ticks). */
    val digitalCrop = Color(0xFFF0B23C)
}

/** Single-layer stand-in for callers that only have a TextStyle. Radii are points. */
fun TextStyle.monitorReadoutGlow(density: Density): TextStyle = copy(
    shadow = Shadow(
        Color.Black.copy(alpha = .92f),
        Offset(0f, with(density) { 1.dp.toPx() }),
        blurRadius = with(density) { 3.dp.toPx() },
    ),
)

@Composable
fun TextStyle.monitorReadoutGlow(): TextStyle = monitorReadoutGlow(LocalDensity.current)

/**
 * iOS `monitorReadoutShadow` without per-draw Paint/BlurMaskFilter or 4× children.
 * API 31+: record children once and composite three cached GPU shadows plus
 * sharp foreground, matching the iOS shadow radii and opacity. Radius uses the
 * same HWUI CSS-sigma map as [MonitorBackdropRenderer]. API 30−: one cached
 * `Paint.setShadowLayer` (native text-shadow) and a single saveLayer.
 */
fun Modifier.monitorReadoutShadow(): Modifier = this
    .then(ReadoutBloomLayout)
    .drawWithCache {
        val blurPx = 3.dp.toPx()
        val dy = 1.dp.toPx()
        val extra = 10.dp.toPx()
        if (Build.VERSION.SDK_INT >= 31) {
            val sharp = obtainGraphicsLayer()
            val black = ColorFilter.colorMatrix(ColorMatrix().apply { setToScale(0f, 0f, 0f, 1f) })
            fun shadow(radiusDp: Float, opacity: Float, yDp: Float) = obtainGraphicsLayer().apply {
                clip = false
                colorFilter = black
                val radius = ((radiusDp.dp.toPx() - .5f) / .57735f).coerceAtLeast(0f)
                renderEffect = BlurEffect(radius, radius, TileMode.Decal)
                alpha = opacity
                translationY = yDp.dp.toPx()
            }
            val halos = arrayOf(shadow(1.5f, 1f, 0f), shadow(3f, .92f, 0f), shadow(1f, .85f, 1f))
            onDrawWithContent {
                sharp.record { this@onDrawWithContent.drawContent() }
                for ((index, halo) in halos.withIndex()) {
                    // SwiftUI chains shadow modifiers: each shadow includes the
                    // preceding bloom, not just the original glyph alpha.
                    halo.record {
                        for (previous in 0 until index) drawLayer(halos[previous])
                        drawLayer(sharp)
                    }
                    drawLayer(halo)
                }
                drawLayer(sharp)
            }
        } else {
            val shadow = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                setShadowLayer(blurPx, 0f, dy, android.graphics.Color.argb(235, 0, 0, 0))
            }
            onDrawWithContent {
                val native = drawContext.canvas.nativeCanvas
                native.saveLayer(-extra, -extra, size.width + extra, size.height + extra, shadow)
                drawContent()
                native.restore()
            }
        }
    }
    .padding(10.dp)

private object ReadoutBloomLayout : LayoutModifier {
    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): MeasureResult {
        val extra = 10.dp.roundToPx()
        val child = measurable.measure(
            Constraints(
                minWidth = constraints.minWidth + extra * 2,
                minHeight = constraints.minHeight + extra * 2,
                maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra * 2 else Constraints.Infinity,
                maxHeight = if (constraints.hasBoundedHeight) constraints.maxHeight + extra * 2 else Constraints.Infinity,
            ),
        )
        return layout(
            (child.width - extra * 2).coerceAtLeast(0),
            (child.height - extra * 2).coerceAtLeast(0),
        ) { child.place(-extra, -extra) }
    }
}

object MonitorTypography {
    val fontFamily = FontFamily(
        Font(R.font.sora_regular, FontWeight.Normal),
        Font(R.font.sora_medium, FontWeight.Medium),
        Font(R.font.sora_semibold, FontWeight.SemiBold),
        Font(R.font.sora_bold, FontWeight.Bold),
    )

    fun text(size: Float, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontFamily = fontFamily, fontWeight = weight, fontSize = size.sp, color = MonitorPalette.text)

    fun readout(size: Float, weight: FontWeight = FontWeight.Medium): TextStyle =
        text(size, weight).copy(fontFeatureSettings = "tnum")
}

/** Additive capabilities are supplied by an adapter, never inferred from a brand here. */
@Immutable
data class MonitorCapabilities(
    val gimbal: Boolean = false,
    val zoom: Boolean = false,
    val focus: Boolean = false,
    val iris: Boolean = false,
    val audio: Boolean = false,
    val headTracking: Boolean = false,
    val clipDelete: Boolean = false,
    val clipStar: Boolean = false,
    val requiresInternetHop: Boolean = false,
    val timecode: Boolean = false,
) {
    val availableControls: Set<MonitorControlRole>
        get() = buildSet {
            if (gimbal) add(MonitorControlRole.GIMBAL)
            if (zoom) add(MonitorControlRole.ZOOM)
            if (focus) add(MonitorControlRole.FOCUS)
            if (iris) add(MonitorControlRole.IRIS)
            if (audio) add(MonitorControlRole.AUDIO)
            if (headTracking && gimbal) add(MonitorControlRole.HEAD_TRACKING)
        }
}

enum class MonitorControlRole { GIMBAL, ZOOM, FOCUS, IRIS, AUDIO, HEAD_TRACKING }
