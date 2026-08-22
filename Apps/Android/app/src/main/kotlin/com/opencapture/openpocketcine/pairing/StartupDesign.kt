package com.opencapture.openpocketcine.pairing

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LiveTypeDesign
import com.opencapture.openpocketcine.core.ConnectionPhase

private fun startupType(size: Float, weight: FontWeight = FontWeight.Normal) =
    LiveType.ui(size, weight, LiveTypeDesign.Rounded)

/** Pairing chrome — DJI Sky Blue `#00A3E0` on Black, no Nikon gold. */
object StartupColors {
    val surface: Color = Color(28 / 255f, 28 / 255f, 28 / 255f)
    val tile: Color = Color(36 / 255f, 36 / 255f, 36 / 255f)
    val control: Color = Color(94 / 255f, 98 / 255f, 98 / 255f)
    val ink: Color = Color.White
    val muted: Color = Color(160 / 255f, 165 / 255f, 165 / 255f)
    val dim: Color = Color(94 / 255f, 98 / 255f, 98 / 255f)
    val border: Color = Color.White
    val card: Color = surface.copy(alpha = 0.58f)
    val accent: Color = Color(0f, 163 / 255f, 230 / 255f)
    val ready: Color = Color(0.247f, 0.710f, 0.416f)
    val destructive: Color = Color(0.930f, 0.267f, 0.267f)
    val darkText: Color = Color(20 / 255f, 20 / 255f, 20 / 255f)
    val backdropBase: Color = Color(20 / 255f, 20 / 255f, 20 / 255f)
    /**
     * Operator Setup wash. iOS uses Sky Blue at 10% / 760 pt; Android is 20%
     * quieter and tighter on top of the OLED dim (6% / 608 pt).
     */
    val backdropGlow: Color = Color(0f, 163 / 255f, 230 / 255f, 0.06f)
}

fun Modifier.startupBackdrop(): Modifier = drawBehind {
    drawRect(StartupColors.backdropBase)
    // iOS `RadialGradient` endRadius 760 on ~956×440 pt landscape. Android
    // uses 80% of that (608) so the wash does not bloom as far, still
    // fraction-of-the-window so a shorter-dp device does not fill the screen.
    // Fade to DJI black at 0, not cyan at 0, so chroma collapses the way
    // SwiftUI interpolates.
    val radius =
        minOf(
            608.dp.toPx(),
            size.maxDimension * (608f / 956f),
            size.minDimension * (608f / 440f),
        )
    val inner = (8.dp.toPx() / radius).coerceIn(0f, 0.2f)
    drawRect(
        Brush.radialGradient(
            colorStops =
                arrayOf(
                    0f to StartupColors.backdropGlow,
                    inner to StartupColors.backdropGlow,
                    1f to StartupColors.backdropBase.copy(alpha = 0f),
                ),
            center = Offset(size.width * 0.5f, size.height * 0.24f),
            radius = radius,
        )
    )
}

/**
 * Fades out the bottom edge of a scrollable viewport while more content lies
 * below the fold — the "there's more" affordance. Apply before the
 * `verticalScroll` modifier that shares [scrollState].
 */
@Composable
fun Modifier.fadeOverflowBottom(scrollState: ScrollState, height: Dp = 28.dp): Modifier {
    val fade by
        animateFloatAsState(
            targetValue = if (scrollState.canScrollForward) 1f else 0f,
            label = "overflow-edge-fade",
        )
    return graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            if (fade > 0f) {
                val bandHeight = height.toPx()
                drawRect(
                    brush =
                        Brush.verticalGradient(
                            colors = listOf(Color.Black, Color.Black.copy(alpha = 1f - fade)),
                            startY = size.height - bandHeight,
                            endY = size.height,
                        ),
                    topLeft = Offset(0f, size.height - bandHeight),
                    size = Size(size.width, bandHeight),
                    blendMode = BlendMode.DstIn,
                )
            }
        }
}

fun Modifier.startupCard(): Modifier =
    clip(RoundedCornerShape(20.dp))
        .background(StartupColors.card)
        .border(1.dp, StartupColors.border.copy(alpha = 0.08f), RoundedCornerShape(20.dp))

/** Inner tile/row surface (iOS 14pt-radius tile). */
fun Modifier.startupTile(borderColor: Color = StartupColors.border.copy(alpha = 0.10f)): Modifier =
    clip(RoundedCornerShape(14.dp))
        .background(StartupColors.tile.copy(alpha = 0.45f))
        .border(1.dp, borderColor, RoundedCornerShape(14.dp))

fun Modifier.startupInstructionCard(): Modifier =
    clip(RoundedCornerShape(16.dp))
        .background(StartupColors.card)
        .border(1.dp, StartupColors.border.copy(alpha = 0.10f), RoundedCornerShape(16.dp))

fun ConnectionPhase.isBusy(): Boolean =
    when (this) {
        ConnectionPhase.IDLE,
        ConnectionPhase.SCANNING,
        ConnectionPhase.FAILED,
        ConnectionPhase.LIVE,
        -> false
        else -> true
    }

object StartupConnectionCopy {
    fun statusTitle(
        phase: ConnectionPhase,
        isDiscovering: Boolean,
        isReconnecting: Boolean = false,
    ): String =
        when {
            isReconnecting &&
                (phase == ConnectionPhase.SCANNING || phase == ConnectionPhase.IDLE) ->
                "Connecting"
            else ->
                when (phase) {
                    ConnectionPhase.IDLE -> if (isDiscovering) "Looking" else "Ready"
                    ConnectionPhase.SCANNING -> "Looking"
                    ConnectionPhase.CONNECTING_GATT -> "Connecting"
                    ConnectionPhase.PAIRING,
                    ConnectionPhase.AWAITING_APPROVAL,
                    -> "Pairing"
                    ConnectionPhase.READING_WIFI_CREDS -> "Reading"
                    ConnectionPhase.JOINING_WIFI -> "Joining"
                    ConnectionPhase.OPENING_DATALINK -> "Connecting"
                    ConnectionPhase.LIVE -> "Connected"
                    ConnectionPhase.FAILED -> "Ready"
                }
        }

    fun phaseLabel(phase: ConnectionPhase, failure: String?): String =
        when (phase) {
            ConnectionPhase.IDLE -> "Idle"
            ConnectionPhase.SCANNING -> "Scanning for camera…"
            ConnectionPhase.CONNECTING_GATT -> "Connecting (Bluetooth)…"
            ConnectionPhase.PAIRING -> "Pairing…"
            ConnectionPhase.AWAITING_APPROVAL -> "Approve on the camera screen"
            ConnectionPhase.READING_WIFI_CREDS -> "Reading Wi-Fi credentials…"
            ConnectionPhase.JOINING_WIFI -> "Joining camera Wi-Fi…"
            ConnectionPhase.OPENING_DATALINK -> "Opening datalink…"
            ConnectionPhase.LIVE -> "Connected"
            ConnectionPhase.FAILED -> "Failed: ${failure.orEmpty()}"
        }

    fun wizardStep(phase: ConnectionPhase): Int =
        when (phase) {
            ConnectionPhase.IDLE,
            ConnectionPhase.SCANNING,
            ConnectionPhase.FAILED,
            -> 1
            ConnectionPhase.CONNECTING_GATT,
            ConnectionPhase.PAIRING,
            ConnectionPhase.AWAITING_APPROVAL,
            -> 2
            ConnectionPhase.READING_WIFI_CREDS,
            ConnectionPhase.JOINING_WIFI,
            -> 3
            ConnectionPhase.OPENING_DATALINK,
            ConnectionPhase.LIVE,
            -> 4
        }

    const val WIZARD_STEP_COUNT = 4

    fun friendly(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return trimmed
        val lower = trimmed.lowercase()
        if (lower.contains("timed out") || lower.contains("timeout")) {
            return "The camera didn't respond in time. Check Bluetooth and try again."
        }
        if (lower.contains("disconnected")) {
            return "The camera ended the connection. Try again."
        }
        return trimmed
    }
}

@Composable
fun StartupHeader(
    title: String,
    statusTitle: String,
    isBusy: Boolean,
    onPrivacy: (() -> Unit)? = null,
    onTerms: (() -> Unit)? = null,
) {
    val busyTitles =
        setOf(
            "Looking", "Pairing", "Reconnecting", "Starting", "Reading", "Discovering",
            "Preparing", "Joining", "Connecting",
        )
    val statusColor =
        if (isBusy || statusTitle in busyTitles) StartupColors.accent else StartupColors.ready
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f)) {
            Text(
                "OPENPOCKETCINE",
                color = StartupColors.muted,
                style = startupType(10f, FontWeight.SemiBold).copy(letterSpacing = 1.3.sp),
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(
                    title,
                    color = StartupColors.ink,
                    style = startupType(17f, FontWeight.Bold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (onPrivacy != null) {
                    StartupLegalLink("Privacy", onPrivacy)
                }
                if (onTerms != null) {
                    StartupLegalLink("Terms", onTerms)
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier =
                Modifier.clip(CircleShape)
                    .background(StartupColors.surface.copy(alpha = 0.50f))
                    .border(1.dp, statusColor.copy(alpha = 0.40f), CircleShape)
                    .padding(horizontal = 14.dp, vertical = 7.dp),
        ) {
            Box(Modifier.size(7.dp).background(statusColor, CircleShape))
            Text(statusTitle, color = statusColor, style = startupType(12f, FontWeight.Medium), maxLines = 1)
        }
    }
}

@Composable
private fun StartupLegalLink(label: String, onClick: () -> Unit) {
    Text(
        label,
        color = StartupColors.dim,
        style = startupType(11f, FontWeight.Medium),
        maxLines = 1,
        modifier =
            Modifier.semantics { contentDescription = "$label policy" }
                .clickable(role = Role.Button, onClick = onClick)
                .padding(horizontal = 3.dp, vertical = 5.dp),
    )
}

@Composable
fun StartupWizardProgress(currentStep: Int, totalSteps: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row {
            Text("Setup", color = StartupColors.muted, style = startupType(10f, FontWeight.SemiBold))
            Spacer(Modifier.weight(1f))
            Text(
                "Step $currentStep of $totalSteps",
                color = StartupColors.dim,
                style = startupType(10f, FontWeight.Medium),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (step in 1..totalSteps) {
                Box(
                    Modifier.weight(1f)
                        .height(3.dp)
                        .clip(CircleShape)
                        .background(
                            if (step <= currentStep) StartupColors.accent
                            else StartupColors.control.copy(alpha = 0.55f)
                        )
                )
            }
        }
    }
}

@Composable
fun StartupIndeterminateBar(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "startup-indeterminate")
    val progress by
        transition.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(850), RepeatMode.Reverse),
            label = "startup-indeterminate-offset",
        )
    BoxWithConstraints(
        modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(StartupColors.control.copy(alpha = 0.45f))
    ) {
        val segment: Dp = maxOf(44.dp, maxWidth * 0.32f)
        Box(
            Modifier.width(segment)
                .height(3.dp)
                .offset(x = (maxWidth - segment) * progress)
                .clip(CircleShape)
                .background(StartupColors.accent)
        )
    }
}

/** iOS `StartupIconSquare` — glyph on a 16pt-radius tile. */
@Composable
fun StartupGlyphTile(
    kind: StartupGlyphKind,
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    cornerRadius: Dp = 16.dp,
    tint: Color = StartupColors.accent,
) {
    val glyphSize = maxOf(16.dp, size * 0.38f)
    Box(
        modifier
            .size(size)
            .clip(RoundedCornerShape(cornerRadius))
            .background(StartupColors.tile)
            .border(1.dp, tint.copy(alpha = 0.46f), RoundedCornerShape(cornerRadius)),
        contentAlignment = Alignment.Center,
    ) {
        StartupGlyph(kind, tint = tint, modifier = Modifier.size(glyphSize))
    }
}

/** Centered icon + copy card while discovery waits (iOS `StartupEmptyDiscoveryCard`). */
@Composable
fun StartupEmptyDiscoveryCard(
    title: String,
    hint: String,
    compact: Boolean = false,
    glyph: StartupGlyphKind = StartupGlyphKind.ANTENNA,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(
            Modifier.fillMaxWidth()
                .startupInstructionCard()
                .padding(horizontal = if (compact) 12.dp else 18.dp, vertical = if (compact) 12.dp else 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 10.dp),
        ) {
            StartupGlyph(glyph, tint = StartupColors.accent, modifier = Modifier.size(if (compact) 18.dp else 24.dp))
            Text(
                title,
                color = StartupColors.ink,
                style = startupType(if (compact) 13f else 15f, FontWeight.SemiBold),
            )
            Text(
                hint,
                color = StartupColors.muted,
                style = startupType(if (compact) 10f else 12f).copy(lineHeight = if (compact) 14.sp else 16.sp),
            )
        }
        StartupIndeterminateBar()
    }
}

@Composable
fun StartupStatusPill(text: String, color: Color) {
    Text(
        text,
        color = color,
        style = startupType(11f, FontWeight.SemiBold),
        maxLines = 1,
        modifier =
            Modifier.border(1.dp, color.copy(alpha = 0.50f), CircleShape)
                .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

/** Spinner + optional glyph tile + phase copy — inline connection-progress chrome. */
@Composable
fun StartupConnectionProgress(
    label: String,
    detail: String? = null,
    glyph: StartupGlyphKind? = null,
    tight: Boolean = false,
) {
    Column(verticalArrangement = Arrangement.spacedBy(if (glyph != null) 14.dp else 10.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (glyph != null) 14.dp else 10.dp),
        ) {
            CircularProgressIndicator(
                color = StartupColors.accent,
                modifier = Modifier.size(if (glyph != null) 22.dp else 18.dp),
                strokeWidth = 2.dp,
            )
            if (glyph != null) {
                StartupGlyphTile(glyph, size = if (tight) 36.dp else 48.dp)
            }
            if (glyph == null) {
                Text(label, color = StartupColors.ink, style = startupType(13f, FontWeight.SemiBold))
            }
        }
        if (glyph != null) {
            Text(label, color = StartupColors.ink, style = startupType(15f, FontWeight.SemiBold))
            if (detail != null) {
                Text(detail, color = StartupColors.muted, style = startupType(13f))
            }
        }
    }
}

@Composable
fun StartupQuietButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Box(
        modifier
            .height(40.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(StartupColors.control.copy(alpha = if (enabled) 0.66f else 0.45f))
            .border(1.dp, StartupColors.border.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = StartupColors.ink, style = startupType(13f, FontWeight.SemiBold), maxLines = 1)
    }
}

@Composable
fun StartupFilledButton(
    text: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    large: Boolean = false,
) {
    val height = if (large) 48.dp else 40.dp
    val type = startupType(if (large) 16f else 14f, FontWeight.SemiBold)
    Box(
        modifier
            .height(height)
            .clip(RoundedCornerShape(16.dp))
            .background(if (enabled) StartupColors.accent else StartupColors.control.copy(alpha = 0.6f))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.55f)
            .padding(horizontal = 22.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            color = if (enabled) StartupColors.darkText else StartupColors.muted,
            style = type,
            maxLines = 1,
        )
    }
}

@Composable
fun StartupOutlineButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingChevron: Boolean = false,
) {
    Row(
        modifier
            .height(40.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(StartupColors.control.copy(alpha = if (enabled) 0.82f else 0.55f))
            .border(1.dp, StartupColors.border.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.55f)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (leadingChevron) {
            StartupGlyph(StartupGlyphKind.CHEVRON_LEFT, tint = StartupColors.ink, modifier = Modifier.size(13.dp))
            Spacer(Modifier.width(5.dp))
        }
        Text(text, color = StartupColors.ink, style = startupType(14f, FontWeight.SemiBold), maxLines = 1)
    }
}

/** Wizard-exit affordance matching iOS `StartupYourCamerasButton`. */
@Composable
fun StartupYourCamerasButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Row(
        modifier
            .height(40.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(StartupColors.control.copy(alpha = if (enabled) 0.82f else 0.55f))
            .border(1.dp, StartupColors.border.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.55f)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        StartupGlyph(StartupGlyphKind.CHEVRON_LEFT, tint = StartupColors.ink, modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(7.dp))
        StartupGlyph(StartupGlyphKind.CAMERA, tint = StartupColors.ink, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(7.dp))
        Text("Your cameras", color = StartupColors.ink, style = startupType(14f, FontWeight.SemiBold), maxLines = 1)
    }
}

/** Visual Connect / Reconnect chrome — the row is the hit target, not this pill. */
@Composable
fun StartupConnectChrome(
    text: String,
    filled: Boolean,
    enabled: Boolean = true,
) {
    Text(
        text,
        color = if (filled) StartupColors.darkText else StartupColors.ink,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        maxLines = 1,
        modifier =
            Modifier.clip(RoundedCornerShape(16.dp))
                .background(
                    if (filled) StartupColors.accent else StartupColors.control.copy(alpha = 0.82f)
                )
                .then(
                    if (filled) Modifier
                    else Modifier.border(1.dp, StartupColors.border.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                )
                .alpha(if (enabled) 1f else 0.4f)
                .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
fun StartupInfoBanner(text: String, tight: Boolean = false) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(StartupColors.surface.copy(alpha = 0.72f))
            .border(1.dp, StartupColors.accent.copy(alpha = 0.28f), RoundedCornerShape(16.dp))
            .padding(horizontal = if (tight) 10.dp else 12.dp, vertical = if (tight) 8.dp else 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(if (tight) 8.dp else 10.dp),
    ) {
        Box(
            Modifier.size(if (tight) 14.dp else 16.dp)
                .clip(CircleShape)
                .background(StartupColors.accent.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Text("i", color = StartupColors.accent, fontSize = if (tight) 9.sp else 10.sp, fontWeight = FontWeight.Bold)
        }
        Text(
            text,
            color = StartupColors.muted,
            fontSize = if (tight) 10.sp else 12.sp,
            lineHeight = if (tight) 14.sp else 16.sp,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun StartupDeviceInstructionCard(
    title: String,
    steps: List<String>,
    tight: Boolean = false,
    glyph: StartupGlyphKind? = null,
) {
    Column(
        Modifier.fillMaxWidth()
            .startupInstructionCard()
            .padding(horizontal = if (tight) 10.dp else 14.dp, vertical = if (tight) 10.dp else 12.dp),
        verticalArrangement = Arrangement.spacedBy(if (tight) 6.dp else 8.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (glyph != null) {
                StartupGlyph(
                    glyph,
                    tint = StartupColors.accent,
                    modifier = Modifier.size(if (tight) 13.dp else 15.dp),
                )
            }
            Text(title, color = StartupColors.ink, fontSize = if (tight) 11.sp else 12.sp, fontWeight = FontWeight.Bold)
        }
        steps.forEachIndexed { index, step ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "${index + 1}",
                    color = StartupColors.muted,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.width(14.dp),
                )
                Text(
                    step,
                    color = StartupColors.ink,
                    fontSize = if (tight) 11.sp else 13.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
        }
    }
}

@Composable
fun StartupPrepareCards(steps: List<String>, tight: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(if (tight) 6.dp else 10.dp)) {
        steps.forEachIndexed { index, step ->
            Row(
                Modifier.fillMaxWidth()
                    .startupInstructionCard()
                    .padding(horizontal = if (tight) 12.dp else 16.dp, vertical = if (tight) 9.dp else 15.dp),
                horizontalArrangement = Arrangement.spacedBy(if (tight) 10.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(if (tight) 24.dp else 30.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(StartupColors.accent.copy(alpha = 0.12f))
                        .border(1.dp, StartupColors.accent.copy(alpha = 0.45f), RoundedCornerShape(8.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "${index + 1}",
                        color = StartupColors.accent,
                        fontSize = if (tight) 12.sp else 13.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Text(
                    step,
                    color = StartupColors.ink,
                    fontSize = if (tight) 12.sp else 14.sp,
                    fontWeight = FontWeight.Medium,
                    lineHeight = if (tight) 16.sp else 18.sp,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
fun StartupPermissionRow(
    glyph: StartupGlyphKind,
    title: String,
    detail: String,
    granted: Boolean,
    onRequest: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .clickable(enabled = !granted, onClick = onRequest)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(30.dp).background(StartupColors.accent.copy(alpha = 0.14f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            StartupGlyph(glyph, tint = StartupColors.accent, modifier = Modifier.size(15.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = StartupColors.ink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(2.dp))
            Text(detail, color = StartupColors.muted, fontSize = 11.sp, lineHeight = 15.sp)
        }
        Text(
            if (granted) "Allowed" else "Allow",
            color = if (granted) StartupColors.ready else StartupColors.darkText,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            modifier =
                Modifier.clip(CircleShape)
                    .background(if (granted) StartupColors.ready.copy(alpha = 0.16f) else StartupColors.accent)
                    .border(
                        1.dp,
                        if (granted) StartupColors.ready.copy(alpha = 0.5f) else Color.Transparent,
                        CircleShape,
                    )
                    .padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}
