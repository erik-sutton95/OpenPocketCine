package com.opencapture.openpocketcine.media

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.max

val MediaCapsuleShape: RoundedCornerShape = RoundedCornerShape(percent = 50)

val MediaCornerShape: RoundedCornerShape = ChromeShape

@Composable
fun Modifier.mediaGlass(shape: Shape = MediaCornerShape): Modifier = panelGlass(shape)

@Composable
fun MediaCloseButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 37.dp,
    enabled: Boolean = true,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .panelGlass(CircleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(size * 0.30f)) {
            val stroke = 1.8.dp.toPx()
            drawLine(LiveDesign.text, Offset(0f, 0f), Offset(this.size.width, this.size.height), stroke, StrokeCap.Round)
            drawLine(LiveDesign.text, Offset(this.size.width, 0f), Offset(0f, this.size.height), stroke, StrokeCap.Round)
        }
    }
}

@Composable
fun MediaBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .panelGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = "Back" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(size * 0.47f),
        )
    }
}

@Composable
fun MediaCircleIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
    iconSize: Dp = size * 0.47f,
    tint: androidx.compose.ui.graphics.Color = LiveDesign.text,
    enabled: Boolean = true,
    highlighted: Boolean = false,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .then(if (highlighted) Modifier.background(LiveDesign.accentDim, CircleShape) else Modifier)
            .panelGlass(CircleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (!enabled) LiveDesign.faint else if (highlighted) LiveDesign.accent else tint,
            modifier = Modifier.size(iconSize),
        )
    }
}

@Composable
fun MediaActionPill(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    active: Boolean = false,
    enabled: Boolean = true,
    badge: Int? = null,
    contentDescription: String? = null,
) {
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.5f)
            .clip(MediaCapsuleShape)
            .then(if (active) Modifier.background(LiveDesign.accentDim, MediaCapsuleShape) else Modifier)
            .border(1.dp, LiveDesign.hairline, MediaCapsuleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription ?: title }
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (active) LiveDesign.accent else LiveDesign.muted,
                modifier = Modifier.size(12.dp),
            )
        }
        Text(
            title,
            color = if (active) LiveDesign.accent else LiveDesign.muted,
            fontSize = 9.5.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
        )
        if (badge != null) {
            Text(
                "$badge",
                color = LiveDesign.background,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                modifier =
                    Modifier
                        .clip(MediaCapsuleShape)
                        .background(LiveDesign.accent)
                        .padding(horizontal = 5.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
fun MediaFilterChip(
    title: String,
    active: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Text(
        title,
        color = if (active) LiveDesign.accent else LiveDesign.muted,
        fontSize = 10.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Monospace,
        maxLines = 1,
        modifier =
            modifier
                .fillMaxWidth()
                .clip(MediaCapsuleShape)
                .background(if (active) LiveDesign.accentDim else LiveDesign.glassBright, MediaCapsuleShape)
                .border(
                    1.dp,
                    if (active) LiveDesign.accent.copy(alpha = 0.45f) else LiveDesign.hairline,
                    MediaCapsuleShape,
                )
                .chromeClickable(onClick = onClick)
                .padding(horizontal = 8.dp, vertical = 8.dp),
    )
}

@Composable
fun MediaGlassTrack(
    fraction: Float,
    modifier: Modifier = Modifier,
    trackWidth: Dp? = null,
    trackHeight: Dp = 4.dp,
) {
    val shape = MediaCapsuleShape
    Box(
        modifier
            .then(if (trackWidth != null) Modifier.width(trackWidth) else Modifier.fillMaxWidth())
            .height(trackHeight)
            .clip(shape)
            .background(LiveDesign.hairline.copy(alpha = 0.55f), shape),
    ) {
        Box(
            Modifier
                .fillMaxWidth(fraction.coerceIn(0.05f, 1f))
                .fillMaxHeight()
                .clip(shape)
                .background(LiveDesign.accent, shape),
        )
    }
}

@Composable
fun MediaConfirmPopup(
    title: String,
    confirmTitle: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    destructive: Boolean = true,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.45f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onDismiss,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .width(320.dp)
                .clip(MediaCornerShape)
                .background(LiveDesign.surface, MediaCornerShape)
                .border(1.dp, LiveDesign.hairline, MediaCornerShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {},
                )
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(title, color = LiveDesign.text, style = LiveType.ui(15f, FontWeight.SemiBold))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    Modifier
                        .weight(1f)
                        .clip(MediaCornerShape)
                        .border(1.dp, LiveDesign.hairline, MediaCornerShape)
                        .chromeClickable(onClick = onDismiss)
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Cancel", color = LiveDesign.muted, style = LiveType.ui(14f, FontWeight.SemiBold))
                }
                Box(
                    Modifier
                        .weight(1f)
                        .clip(MediaCornerShape)
                        .background(
                            if (destructive) LiveDesign.rec.copy(alpha = 0.22f) else LiveDesign.accentDim,
                            MediaCornerShape,
                        )
                        .border(
                            1.dp,
                            if (destructive) LiveDesign.rec.copy(alpha = 0.55f) else LiveDesign.accent.copy(alpha = 0.55f),
                            MediaCornerShape,
                        )
                        .chromeClickable(onClick = onConfirm)
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        confirmTitle,
                        color = if (destructive) LiveDesign.rec else LiveDesign.text,
                        style = LiveType.ui(14f, FontWeight.SemiBold),
                    )
                }
            }
        }
    }
}

@Composable
fun MediaPlaybackScrubber(
    progressSeconds: Float,
    durationSeconds: Float,
    onScrubbingChanged: (Boolean) -> Unit,
    onProgressChange: (Float) -> Unit,
    onSeek: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val duration = max(0.1f, durationSeconds)
    val widthPx = remember { mutableFloatStateOf(1f) }
    val dragProgress = remember { mutableFloatStateOf(-1f) }
    val density = LocalDensity.current
    val trackHeight = with(density) { 3.dp.toPx() }
    val thumbSize = with(density) { 12.dp.toPx() }
    val hairline = LiveDesign.hairline
    val accent = LiveDesign.accent
    val display = if (dragProgress.floatValue >= 0f) dragProgress.floatValue else progressSeconds
    val fraction = (display / duration).coerceIn(0f, 1f)

    fun progressAt(x: Float): Float {
        val f = (x / max(1f, widthPx.floatValue)).coerceIn(0f, 1f)
        return f * duration
    }

    Canvas(
        modifier
            .fillMaxWidth()
            .height(22.dp)
            .semantics { contentDescription = "Playback position" }
            .pointerInput(duration) {
                detectTapGestures { offset ->
                    val target = progressAt(offset.x)
                    onScrubbingChanged(true)
                    onProgressChange(target)
                    onSeek(target)
                    onScrubbingChanged(false)
                    dragProgress.floatValue = -1f
                }
            }
            .pointerInput(duration) {
                detectHorizontalDragGestures(
                    onDragStart = { offset ->
                        onScrubbingChanged(true)
                        val target = progressAt(offset.x)
                        dragProgress.floatValue = target
                        onProgressChange(target)
                    },
                    onDragEnd = {
                        val target = dragProgress.floatValue.takeIf { it >= 0f } ?: progressSeconds
                        onSeek(target.coerceIn(0f, duration))
                        onScrubbingChanged(false)
                        dragProgress.floatValue = -1f
                    },
                    onDragCancel = {
                        onScrubbingChanged(false)
                        dragProgress.floatValue = -1f
                    },
                    onHorizontalDrag = { change, _ ->
                        change.consume()
                        val target = progressAt(change.position.x)
                        dragProgress.floatValue = target
                        onProgressChange(target)
                    },
                )
            },
    ) {
        widthPx.floatValue = size.width
        val cy = size.height / 2f
        val trackTop = cy - trackHeight / 2f
        drawRoundRect(
            color = hairline,
            topLeft = Offset(0f, trackTop),
            size = Size(size.width, trackHeight),
            cornerRadius = CornerRadius(trackHeight / 2f, trackHeight / 2f),
        )
        drawRoundRect(
            color = accent,
            topLeft = Offset(0f, trackTop),
            size = Size(max(trackHeight, size.width * fraction), trackHeight),
            cornerRadius = CornerRadius(trackHeight / 2f, trackHeight / 2f),
        )
        val thumbX = (size.width * fraction).coerceIn(0f, size.width)
        drawCircle(color = accent, radius = thumbSize / 2f, center = Offset(thumbX, cy))
    }
}

internal object PlaybackChromeMetrics {
    val transportButtonWidth = 38.dp
    val transportButtonHeight = 36.dp
    val actionButtonWidth = 32.dp
    val actionButtonHeight = 36.dp
    val transportIconSize = 18.dp
    val primaryTransportIconSize = 22.dp
    val actionIconSize = 16.dp
    val corner = MediaCornerShape
}

@Composable
fun MediaTransportIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    highlighted: Boolean = false,
    primary: Boolean = false,
    action: Boolean = false,
) {
    val width = if (action) PlaybackChromeMetrics.actionButtonWidth else PlaybackChromeMetrics.transportButtonWidth
    val height = if (action) PlaybackChromeMetrics.actionButtonHeight else PlaybackChromeMetrics.transportButtonHeight
    val iconSize =
        when {
            primary -> PlaybackChromeMetrics.primaryTransportIconSize
            action -> PlaybackChromeMetrics.actionIconSize
            else -> PlaybackChromeMetrics.transportIconSize
        }
    val shape = PlaybackChromeMetrics.corner
    Box(
        modifier
            .size(width = width, height = height)
            .clip(shape)
            .then(if (highlighted) Modifier.background(LiveDesign.accentDim, shape) else Modifier)
            .panelGlass(shape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint =
                when {
                    !enabled -> LiveDesign.faint
                    highlighted -> LiveDesign.accent
                    else -> LiveDesign.text
                },
            modifier = Modifier.size(iconSize),
        )
    }
}

@Composable
fun MediaTransportSkipButton(
    label: String,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(width = PlaybackChromeMetrics.transportButtonWidth, height = PlaybackChromeMetrics.transportButtonHeight)
            .clip(PlaybackChromeMetrics.corner)
            .panelGlass(PlaybackChromeMetrics.corner)
            .chromeClickable(onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = LiveDesign.text,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
        )
    }
}

@Composable
fun MediaBadge(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text,
        color = LiveDesign.text,
        fontSize = 10.sp,
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Bold,
        modifier =
            modifier
                .background(LiveDesign.feedWell.copy(alpha = 0.58f), RoundedCornerShape(4.dp))
                .padding(horizontal = 6.dp, vertical = 3.dp),
    )
}
