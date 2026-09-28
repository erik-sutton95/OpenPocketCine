package com.opencapture.openpocketcine

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.session.FocusOverlay
import com.opencapture.openpocketcine.session.LiveTrackingChrome
import com.opencapture.openpocketcine.session.TrackingBox
import com.opencapture.openpocketcine.session.TrackingHud
import kotlin.math.max
import kotlin.math.min

@Composable
fun LiveFocusTrackingLayer(
    hud: TrackingHud,
    focus: Pair<Float, Float>?,
    mirrored: Boolean,
    showTapFocusBox: Boolean,
    modifier: Modifier = Modifier,
    aeLocked: Boolean = false,
    flippedVertically: Boolean = false,
) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize()) {
        val aeTag =
            if (aeLocked) {
                measurer.measure(
                    "AE-L",
                    TextStyle(
                        color = LiveDesign.aeLock,
                        fontSize = 9.sp,
                        fontFamily = OpcFonts.sora,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = 0.5.sp,
                        shadow = Shadow(Color.Black.copy(alpha = 0.8f), Offset(0f, 0.5.dp.toPx()), 1.5.dp.toPx()),
                    ),
                )
            } else {
                null
            }
        fun feedRect(box: TrackingBox): Rect {
            val drawn = box.flipped(mirrored, flippedVertically)
            return Rect(
                (drawn.x * size.width).toFloat(),
                (drawn.y * size.height).toFloat(),
                ((drawn.x + drawn.width) * size.width).toFloat(),
                ((drawn.y + drawn.height) * size.height).toFloat(),
            )
        }
        hud.dimmedFaces.forEach { box ->
            drawBracket(feedRect(box), LiveDesign.text.copy(alpha = 0.20f), 1.6.dp.toPx())
        }
        when (val overlay = hud.overlay) {
            is FocusOverlay.Search -> {
                drawBracket(feedRect(overlay.box), LiveDesign.text.copy(alpha = 0.88f), 1.5.dp.toPx())
                if (showTapFocusBox && focus != null) drawFocusBox(focus, mirrored, flippedVertically, aeTag)
            }
            is FocusOverlay.Subject ->
                drawBracket(feedRect(overlay.box), LiveDesign.good, 2.dp.toPx())
            is FocusOverlay.Face ->
                drawBracket(feedRect(overlay.box), LiveDesign.text.copy(alpha = 0.92f), 1.6.dp.toPx())
            FocusOverlay.Focus ->
                if (showTapFocusBox && focus != null) drawFocusBox(focus, mirrored, flippedVertically, aeTag)
        }
    }
}

@Composable
fun LiveTrackingCancelButton(
    box: TrackingBox,
    feedWidth: Float,
    feedHeight: Float,
    mirrored: Boolean,
    flippedVertically: Boolean = false,
    onClick: () -> Unit,
) {
    val rect = LiveTrackingChrome.cancelRect(box, feedWidth, feedHeight, mirrored, flippedVertically)
    Box(
        Modifier
            .offset(rect.x.dp, rect.y.dp)
            .size(rect.width.dp, rect.height.dp)
            .clip(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = "Stop subject tracking" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(LiveTrackingChrome.CANCEL_SIZE.dp)
                .clip(CircleShape)
                .background(LiveDesign.good),
            contentAlignment = Alignment.Center,
        ) {
            OpcIcon(OpcIcon.X, null, Modifier.size(11.dp), LiveDesign.background)
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawFocusBox(
    focus: Pair<Float, Float>,
    mirrored: Boolean,
    flippedVertically: Boolean,
    aeTag: TextLayoutResult?,
) {
    val nx = if (mirrored) 1f - focus.first else focus.first
    val ny = if (flippedVertically) 1f - focus.second else focus.second
    val side = min(size.width, size.height) * 0.14f
    val cx = nx * size.width
    val cy = ny * size.height
    if (aeTag != null) {
        // iOS `FocusBoxView`: right of the box, or left near the right edge.
        val gap = 3.dp.toPx()
        val w = aeTag.size.width.toFloat()
        val right = cx + side / 2f + gap
        val x = if (right + w > size.width) cx - side / 2f - gap - w else right
        drawText(aeTag, topLeft = Offset(x, cy - side / 2f + 6.dp.toPx() - aeTag.size.height / 2f))
    }
    drawRoundRect(
        if (aeTag != null) LiveDesign.aeLock else LiveDesign.accent,
        topLeft = Offset(cx - side / 2f, cy - side / 2f),
        size = androidx.compose.ui.geometry.Size(side, side),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(max(6f, side * 0.12f)),
        style = Stroke(1.5.dp.toPx()),
    )
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawBracket(
    rect: Rect,
    color: Color,
    stroke: Float,
) {
    if (rect.width < 2f || rect.height < 2f) return
    val path = bracketPath(rect.width, rect.height)
    path.translate(Offset(rect.left, rect.top))
    drawPath(
        path,
        color,
        style = Stroke(stroke, cap = StrokeCap.Round, join = StrokeJoin.Round),
    )
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.bracketPath(
    w: Float,
    h: Float,
): Path {
    val ax = LiveTrackingChrome.bracketArm(w)
    val ay = LiveTrackingChrome.bracketArm(h)
    val r = min(max(6f, min(w, h) * 0.12f), min(ax - 1f, ay - 1f)).coerceAtLeast(0f)
    val path = Path()
    path.moveTo(0f, ay)
    path.lineTo(0f, r)
    if (r >= 3f) path.quadraticTo(0f, 0f, r, 0f) else {
        path.lineTo(0f, 0f)
        path.lineTo(r, 0f)
    }
    path.lineTo(ax, 0f)
    path.moveTo(w - ax, 0f)
    path.lineTo(w - r, 0f)
    if (r >= 3f) path.quadraticTo(w, 0f, w, r) else {
        path.lineTo(w, 0f)
        path.lineTo(w, r)
    }
    path.lineTo(w, ay)
    path.moveTo(w, h - ay)
    path.lineTo(w, h - r)
    if (r >= 3f) path.quadraticTo(w, h, w - r, h) else {
        path.lineTo(w, h)
        path.lineTo(w - r, h)
    }
    path.lineTo(w - ax, h)
    path.moveTo(ax, h)
    path.lineTo(r, h)
    if (r >= 3f) path.quadraticTo(0f, h, 0f, h - r) else {
        path.lineTo(0f, h)
        path.lineTo(0f, h - r)
    }
    path.lineTo(0f, h - ay)
    return path
}
