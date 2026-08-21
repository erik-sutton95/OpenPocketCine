package com.opencapture.openpocketcine.pairing

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

/**
 * Canvas stand-ins for the SF Symbols the iOS startup screens use
 * (`antenna.radiowaves.left.and.right`, `iphone.radiowaves.left.and.right`,
 * `cable.connector`, `camera.fill`, `wifi`, `lock.shield`, `camera.aperture`,
 * `iphone`, `chevron.left`) — the same approach as the monitor's
 * toolbar glyphs, since the app bundles no icon font.
 */
enum class StartupGlyphKind {
    ANTENNA,
    PHONE_WAVES,
    CABLE,
    CAMERA,
    WIFI,
    SHIELD,
    APERTURE,
    PHONE,
    CHEVRON_LEFT,
}

@Composable
fun StartupGlyph(
    kind: StartupGlyphKind,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier) {
        val stroke = Stroke(width = size.minDimension * 0.085f, cap = StrokeCap.Round)
        when (kind) {
            StartupGlyphKind.ANTENNA -> drawAntenna(tint, stroke)
            StartupGlyphKind.PHONE_WAVES -> drawPhoneWaves(tint, stroke)
            StartupGlyphKind.CABLE -> drawCable(tint, stroke)
            StartupGlyphKind.CAMERA -> drawCamera(tint)
            StartupGlyphKind.WIFI -> drawWifi(tint, stroke)
            StartupGlyphKind.SHIELD -> drawShield(tint, stroke)
            StartupGlyphKind.APERTURE -> drawAperture(tint, stroke)
            StartupGlyphKind.PHONE -> drawPhone(tint, stroke)
            StartupGlyphKind.CHEVRON_LEFT -> drawChevronLeft(tint, stroke)
        }
    }
}

private fun DrawScope.drawAntenna(tint: Color, stroke: Stroke) {
    val c = center
    drawCircle(tint, radius = size.minDimension * 0.09f, center = c)
    for (side in listOf(-1f, 1f)) {
        for (ring in 1..2) {
            val r = size.minDimension * (0.20f + 0.14f * ring)
            drawArc(
                color = tint,
                startAngle = if (side < 0f) 135f else -45f,
                sweepAngle = 90f,
                useCenter = false,
                topLeft = Offset(c.x - r, c.y - r),
                size = Size(r * 2, r * 2),
                style = stroke,
            )
        }
    }
}

private fun DrawScope.drawPhoneWaves(tint: Color, stroke: Stroke) {
    val w = size.width
    val h = size.height
    drawRoundRect(
        color = tint,
        topLeft = Offset(w * 0.36f, h * 0.18f),
        size = Size(w * 0.28f, h * 0.64f),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.06f),
        style = stroke,
    )
    for (side in listOf(-1f, 1f)) {
        val cx = if (side < 0f) w * 0.36f else w * 0.64f
        for (ring in 1..2) {
            val r = w * (0.10f + 0.10f * ring)
            drawArc(
                color = tint,
                startAngle = if (side < 0f) 135f else -45f,
                sweepAngle = 90f,
                useCenter = false,
                topLeft = Offset(cx - r, size.height / 2 - r),
                size = Size(r * 2, r * 2),
                style = stroke,
            )
        }
    }
}

private fun DrawScope.drawCable(tint: Color, stroke: Stroke) {
    val w = size.width
    val h = size.height
    // Plug housing with two pins and a tail lead — `cable.connector`.
    drawRoundRect(
        color = tint,
        topLeft = Offset(w * 0.30f, h * 0.16f),
        size = Size(w * 0.40f, h * 0.42f),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.08f),
        style = stroke,
    )
    drawLine(tint, Offset(w * 0.42f, h * 0.16f), Offset(w * 0.42f, h * 0.05f), stroke.width)
    drawLine(tint, Offset(w * 0.58f, h * 0.16f), Offset(w * 0.58f, h * 0.05f), stroke.width)
    drawLine(tint, Offset(w * 0.5f, h * 0.58f), Offset(w * 0.5f, h * 0.92f), stroke.width)
}

private fun DrawScope.drawCamera(tint: Color) {
    val w = size.width
    val h = size.height
    val body = Path().apply {
        // camera.fill: body with a raised viewfinder hump, filled, lens knocked out.
        moveTo(w * 0.08f, h * 0.32f)
        lineTo(w * 0.30f, h * 0.32f)
        lineTo(w * 0.38f, h * 0.20f)
        lineTo(w * 0.62f, h * 0.20f)
        lineTo(w * 0.70f, h * 0.32f)
        lineTo(w * 0.92f, h * 0.32f)
        arcTo(Rect(w * 0.84f, h * 0.32f, w * 0.92f, h * 0.40f), -90f, 90f, false)
        lineTo(w * 0.92f, h * 0.74f)
        arcTo(Rect(w * 0.84f, h * 0.66f, w * 0.92f, h * 0.74f), 0f, 90f, false)
        lineTo(w * 0.16f, h * 0.74f)
        arcTo(Rect(w * 0.08f, h * 0.66f, w * 0.16f, h * 0.74f), 90f, 90f, false)
        lineTo(w * 0.08f, h * 0.40f)
        arcTo(Rect(w * 0.08f, h * 0.32f, w * 0.16f, h * 0.40f), 180f, 90f, false)
        close()
    }
    drawPath(body, tint)
    drawCircle(Color.Black.copy(alpha = 0.85f), radius = w * 0.15f, center = Offset(w * 0.5f, h * 0.52f))
    drawCircle(tint, radius = w * 0.08f, center = Offset(w * 0.5f, h * 0.52f))
}

private fun DrawScope.drawWifi(tint: Color, stroke: Stroke) {
    val cx = size.width / 2
    val base = size.height * 0.78f
    drawCircle(tint, radius = size.minDimension * 0.07f, center = Offset(cx, base))
    for (ring in 1..3) {
        val r = size.minDimension * (0.16f + 0.155f * ring)
        drawArc(
            color = tint,
            startAngle = 215f,
            sweepAngle = 110f,
            useCenter = false,
            topLeft = Offset(cx - r, base - r),
            size = Size(r * 2, r * 2),
            style = stroke,
        )
    }
}

private fun DrawScope.drawShield(tint: Color, stroke: Stroke) {
    val w = size.width
    val h = size.height
    val shield = Path().apply {
        moveTo(w * 0.5f, h * 0.10f)
        cubicTo(w * 0.66f, h * 0.20f, w * 0.80f, h * 0.22f, w * 0.84f, h * 0.22f)
        cubicTo(w * 0.84f, h * 0.60f, w * 0.72f, h * 0.80f, w * 0.5f, h * 0.90f)
        cubicTo(w * 0.28f, h * 0.80f, w * 0.16f, h * 0.60f, w * 0.16f, h * 0.22f)
        cubicTo(w * 0.20f, h * 0.22f, w * 0.34f, h * 0.20f, w * 0.5f, h * 0.10f)
        close()
    }
    drawPath(shield, tint, style = stroke)
    // Keyhole dot echoing lock.shield without drawing a full padlock.
    drawCircle(tint, radius = w * 0.07f, center = Offset(w * 0.5f, h * 0.44f))
    drawLine(tint, Offset(w * 0.5f, h * 0.48f), Offset(w * 0.5f, h * 0.62f), stroke.width)
}

private fun DrawScope.drawAperture(tint: Color, stroke: Stroke) {
    val c = center
    val r = size.minDimension * 0.40f
    drawCircle(tint, radius = r, center = c, style = stroke)
    // Six blades from rim toward the opposite rim third — camera.aperture.
    for (i in 0 until 6) {
        val angle = Math.toRadians(60.0 * i)
        val tip = Offset(
            c.x + (r * 0.98f) * kotlin.math.cos(angle).toFloat(),
            c.y + (r * 0.98f) * kotlin.math.sin(angle).toFloat(),
        )
        val innerAngle = Math.toRadians(60.0 * i + 105.0)
        val inner = Offset(
            c.x + (r * 0.45f) * kotlin.math.cos(innerAngle).toFloat(),
            c.y + (r * 0.45f) * kotlin.math.sin(innerAngle).toFloat(),
        )
        drawLine(tint, tip, inner, stroke.width)
    }
}

private fun DrawScope.drawPhone(tint: Color, stroke: Stroke) {
    val w = size.width
    val h = size.height
    drawRoundRect(
        color = tint,
        topLeft = Offset(w * 0.30f, h * 0.10f),
        size = Size(w * 0.40f, h * 0.80f),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.09f),
        style = stroke,
    )
    drawLine(tint, Offset(w * 0.44f, h * 0.82f), Offset(w * 0.56f, h * 0.82f), stroke.width)
}

private fun DrawScope.drawChevronLeft(tint: Color, stroke: Stroke) {
    val w = size.width
    val h = size.height
    val path = Path().apply {
        moveTo(w * 0.62f, h * 0.22f)
        lineTo(w * 0.38f, h * 0.50f)
        lineTo(w * 0.62f, h * 0.78f)
    }
    drawPath(path, tint, style = Stroke(width = size.minDimension * 0.12f, cap = StrokeCap.Round))
}
