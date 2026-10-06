package com.opencapture.openpocketcine.media

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.openpocketcine.liveChromeGlass
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.max
import com.opencapture.opencine.cameracontrols.MediaCornerShape
import com.opencapture.opencine.cameracontrols.MediaCapsuleShape

@Composable
fun Modifier.mediaGlass(shape: Shape = MediaCornerShape): Modifier {
    val glass = LocalMonitorGlass.current
    return if (glass == null) panelGlass(shape) else liveChromeGlass(shape)
}

/** Playback transport plate — frost fill, no Kyant. */
fun Modifier.playbackFrost(shape: Shape = MediaCornerShape): Modifier =
    background(LiveDesign.playbackPanel, shape).border(1.dp, LiveDesign.hairlineStrong, shape)

fun Modifier.mediaSheetPlate(shape: Shape = MediaCornerShape): Modifier =
    background(LiveDesign.sheetPlate, shape).border(1.dp, LiveDesign.hairlineStrong, shape)


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
            .mediaGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = "Back" },
        contentAlignment = Alignment.Center,
    ) {
        MonitorIcon(
            icon = MonitorIcon.CHEVRON_LEFT,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(size * 0.47f),
        )
    }
}

@Composable
fun MediaFavoriteButton(
    favorite: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .mediaGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics {
                contentDescription = if (favorite) "Remove from favorites" else "Add to favorites"
            },
        contentAlignment = Alignment.Center,
    ) {
        MonitorIcon(
            icon = MonitorIcon.STAR,
            contentDescription = null,
            tint = if (favorite) Color(0xFFE9C35A) else LiveDesign.text,
            modifier = Modifier.size(size * 0.50f),
            filled = favorite,
        )
    }
}


@Composable
fun MediaActionPill(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: MonitorIcon? = null,
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
            MonitorIcon(
                icon = icon,
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
            fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
        )
        if (badge != null) {
            Text(
                "$badge",
                color = LiveDesign.background,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
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
        fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
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
    val trackHeight = with(density) { 4.dp.toPx() }
    val thumbSize = with(density) { 13.dp.toPx() }
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
            .semantics {
                contentDescription = "Playback position"
                progressBarRangeInfo = ProgressBarRangeInfo(display.coerceIn(0f, duration), 0f..duration)
                setProgress { requested ->
                    val target = requested.coerceIn(0f, duration)
                    onScrubbingChanged(true)
                    onProgressChange(target)
                    onSeek(target)
                    onScrubbingChanged(false)
                    dragProgress.floatValue = -1f
                    true
                }
            }
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
        drawCircle(color = Color.White, radius = thumbSize / 2f, center = Offset(thumbX, cy))
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
    const val barPaddingH = 10f
    const val transportRowSpacing = 5f
    const val narrowestScreenWidth = 375f
    const val chromeHorizontalPadding = 16f
    const val topScrimDp = 120f
    const val bottomScrimDp = 200f
    const val SAMPLE_MS = 80L
    const val SAMPLE_MAX_SIDE = 480f
    const val actionChipSize = 44f
    const val actionChipIcon = 18f
    const val actionChipCorner = 14f
    val hideChromeIcon = MonitorIcon.MAXIMIZE
    val showChromeIcon = MonitorIcon.MINIMIZE

    fun usesDarkenedBars(tier: GlassTier): Boolean = tier == GlassTier.FLAT

    /** iOS `MediaPlayerView.PlaybackChrome.transportRowWidth`. */
    fun transportRowWidth(
        transportCount: Int = 3,
        actionCount: Int = 5,
        minimumSpacer: Float = 6f,
    ): Float {
        val buttons = 38f * transportCount + 32f * actionCount
        val gaps = transportRowSpacing * (transportCount + actionCount - 1)
        return buttons + gaps + barPaddingH * 2 + minimumSpacer
    }
}

@Composable
fun PlaybackActionChip(
    icon: MonitorIcon,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    title: String? = null,
    active: Boolean = false,
    destructive: Boolean = false,
    filled: Boolean = false,
    enabled: Boolean = true,
    tint: Color = if (!enabled) LiveDesign.faint else if (destructive) LiveDesign.rec else if (active) LiveDesign.accent else LiveDesign.text.copy(alpha = 0.86f),
) {
    val shape = RoundedCornerShape(PlaybackChromeMetrics.actionChipCorner.dp)
    Row(
        modifier
            .height(PlaybackChromeMetrics.actionChipSize.dp)
            .then(if (title == null) Modifier.width(PlaybackChromeMetrics.actionChipSize.dp) else Modifier)
            .clip(shape)
            .then(
                when {
                    destructive -> Modifier.background(LiveDesign.rec.copy(alpha = 0.12f), shape)
                    active -> Modifier.background(LiveDesign.accent.copy(alpha = 0.22f), shape)
                    else -> Modifier
                },
            )
            .mediaGlass(shape)
            .then(
                when {
                    destructive -> Modifier.border(1.dp, LiveDesign.rec.copy(alpha = 0.4f), shape)
                    active -> Modifier.border(1.dp, LiveDesign.accent.copy(alpha = 0.5f), shape)
                    else -> Modifier
                },
            )
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription }
            .padding(horizontal = if (title == null) 13.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        MonitorIcon(
            icon = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(PlaybackChromeMetrics.actionChipIcon.dp),
            filled = filled,
        )
        if (title != null) {
            Text(
                title,
                color = tint,
                style = LiveType.ui(12f, FontWeight.SemiBold),
            )
        }
    }
}

@Composable
fun MediaTransportIconButton(
    icon: MonitorIcon,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    highlighted: Boolean = false,
    primary: Boolean = false,
    action: Boolean = false,
) {
    val width = if (primary) 52.dp else if (action) 37.dp else 34.dp
    val height = width
    val iconSize =
        when {
            primary -> PlaybackChromeMetrics.primaryTransportIconSize
            action -> PlaybackChromeMetrics.actionIconSize
            else -> PlaybackChromeMetrics.transportIconSize
        }
    val shape = if (action) RoundedCornerShape(10.dp) else CircleShape
    Box(
        modifier
            .size(width = width, height = height)
            .clip(shape)
            .then(if (primary) Modifier.background(Color.White, shape) else Modifier.monitorMaterial(
                if (highlighted) MonitorMaterial.Compact.copy(tint = LiveDesign.accentDim) else MonitorMaterial.Compact, shape))
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        MonitorIcon(
            icon = icon,
            contentDescription = null,
            tint =
                when {
                    !enabled -> LiveDesign.faint
                    primary -> LiveDesign.background
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
            .mediaGlass(PlaybackChromeMetrics.corner)
            .chromeClickable(onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = LiveDesign.text,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
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
        fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
        fontWeight = FontWeight.Bold,
        modifier =
            modifier
                .background(LiveDesign.feedWell.copy(alpha = 0.58f), RoundedCornerShape(4.dp))
                .padding(horizontal = 6.dp, vertical = 3.dp),
    )
}
