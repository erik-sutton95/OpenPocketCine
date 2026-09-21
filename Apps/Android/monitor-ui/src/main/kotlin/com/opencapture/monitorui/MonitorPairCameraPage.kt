package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class MonitorPairingStep(val title: String, val subtitle: String)

enum class MonitorPairingInstructionIcon { CAMERA, PHONE }

@Immutable
data class MonitorPairingInstruction(
    val title: String,
    val icon: MonitorPairingInstructionIcon,
    val lines: List<String>,
)

enum class MonitorPairingCheckState { COMPLETE, ACTIVE, WAITING }

@Immutable
data class MonitorPairingCheck(
    val title: String,
    val subtitle: String,
    val state: MonitorPairingCheckState,
    val stateLabel: String,
)

@Immutable
data class MonitorPairingSummary(val title: String, val value: String)

@Immutable
data class MonitorPairingDevice(
    val id: String,
    val name: String,
    val subtitle: String,
    val selected: Boolean = false,
    val busy: Boolean = false,
    val signalBars: Int? = null,
)

/**
 * Presentation-only pairing values. The shell adapter reports completed stages;
 * only its callbacks can connect, retry, or cancel a real camera session.
 */
@Immutable
data class MonitorPairingPresentation(
    val steps: List<MonitorPairingStep>,
    val currentStep: Int,
    val title: String,
    val body: String,
    val target: String,
    val hint: String,
    val progress: String? = null,
    val error: String? = null,
    val devices: List<MonitorPairingDevice> = emptyList(),
    val instructions: List<MonitorPairingInstruction> = emptyList(),
    val checks: List<MonitorPairingCheck> = emptyList(),
    val summary: List<MonitorPairingSummary> = emptyList(),
    val emptyTitle: String? = null,
    val primaryAction: String? = null,
    val primaryActionEnabled: Boolean = false,
    val backAction: String? = null,
)

/** Native rail-and-pane pairing. Matches iOS `PairCameraPage`. */
@Composable
fun MonitorPairCameraPage(
    presentation: MonitorPairingPresentation,
    onSelect: (String) -> Unit,
    onPrimary: () -> Unit,
    onBack: () -> Unit,
    onDiagnostics: () -> Unit,
    onReportProblem: () -> Unit,
    modifier: Modifier = Modifier,
    onWatchFeed: (() -> Unit)? = null,
    extra: @Composable ColumnScope.() -> Unit = {},
) {
    BoxWithConstraints(modifier.fillMaxSize().background(MonitorPalette.background)) {
        val portrait = maxHeight > maxWidth
        val tablet = minOf(maxWidth, maxHeight) >= 600.dp
        val railWidth = if (tablet) 268.dp else 210.dp
        if (portrait) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PairingRail(presentation, true, onDiagnostics, onReportProblem, onWatchFeed)
                PairingPane(
                    presentation, true, tablet, onSelect, onPrimary, onBack, extra,
                    Modifier.weight(1f),
                )
            }
        } else {
            Row(
                Modifier.fillMaxSize(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                PairingRail(
                    presentation, false, onDiagnostics, onReportProblem, onWatchFeed,
                    Modifier.width(railWidth).fillMaxHeight(),
                )
                PairingPane(
                    presentation, false, tablet, onSelect, onPrimary, onBack, extra,
                    Modifier.weight(1f).fillMaxHeight(),
                )
            }
        }
    }
}

@Composable
private fun PairingRail(
    presentation: MonitorPairingPresentation,
    portrait: Boolean,
    onDiagnostics: () -> Unit,
    onReportProblem: () -> Unit,
    onWatchFeed: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    val current = presentation.currentStep.coerceIn(0, (presentation.steps.size - 1).coerceAtLeast(0))
    Column(
        modifier
            .fillMaxWidth()
            .then(if (portrait) Modifier else Modifier.fillMaxHeight())
            .clip(shape)
            .background(MonitorPalette.surface)
            .border(1.dp, Color.White.copy(alpha = 0.05f), shape)
            .padding(11.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    "STEP ${current + 1} OF ${presentation.steps.size}",
                    color = MonitorPalette.accent,
                    style = MonitorTypography.text(8f, FontWeight.Bold).copy(letterSpacing = 1.4.sp),
                    maxLines = 1,
                )
                Text(
                    "Pair a camera",
                    color = MonitorPalette.text,
                    style = MonitorTypography.text(13f, FontWeight.SemiBold),
                    maxLines = 1,
                )
            }
            PairingOverflowMenu(onDiagnostics, onWatchFeed)
        }
        if (portrait) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                presentation.steps.forEachIndexed { index, step ->
                    PairingStepRow(step, index, current, true, Modifier.weight(1f))
                }
            }
        } else {
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                presentation.steps.forEachIndexed { index, step ->
                    PairingStepRow(step, index, current, false, Modifier.fillMaxWidth())
                }
            }
        }
        Column(
            Modifier.fillMaxWidth()
                .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(10.dp))
                .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(10.dp))
                .padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                "TARGET",
                color = MonitorPalette.faint,
                style = MonitorTypography.text(8f, FontWeight.Bold).copy(letterSpacing = 1.3.sp),
                maxLines = 1,
            )
            Text(
                presentation.target,
                color = MonitorPalette.secondary,
                style = MonitorTypography.text(10f, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box(
            Modifier.fillMaxWidth().heightIn(min = 44.dp)
                .clickable(role = Role.Button, onClick = onReportProblem)
                .testTag("pair.reportProblem"),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Report a problem",
                color = MonitorPalette.accent,
                style = MonitorTypography.text(12f, FontWeight.SemiBold),
            )
        }
    }
}

@Composable
private fun PairingOverflowMenu(onDiagnostics: () -> Unit, onWatchFeed: (() -> Unit)?) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.size(width = 32.dp, height = 44.dp)
                .clickable(role = Role.Button, onClick = { open = true })
                .semantics { contentDescription = "Pairing help and diagnostics" },
            contentAlignment = Alignment.Center,
        ) {
            MonitorIcon(MonitorIcon.ELLIPSIS, null, Modifier.size(15.dp), MonitorPalette.text)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = {
                    Text("Share Diagnostics", style = MonitorTypography.text(13f, FontWeight.SemiBold))
                },
                onClick = {
                    open = false
                    onDiagnostics()
                },
            )
            if (onWatchFeed != null) {
                DropdownMenuItem(
                    text = {
                        Text("Watch a feed", style = MonitorTypography.text(13f, FontWeight.SemiBold))
                    },
                    onClick = {
                        open = false
                        onWatchFeed()
                    },
                )
            }
        }
    }
}

@Composable
private fun PairingStepRow(
    step: MonitorPairingStep,
    index: Int,
    current: Int,
    portrait: Boolean,
    modifier: Modifier = Modifier,
) {
    val active = index == current
    val complete = index < current
    val status = when {
        complete -> "complete"
        active -> "current"
        else -> "waiting"
    }
    Row(
        modifier
            .heightIn(min = if (portrait) 34.dp else 42.dp)
            .background(
                if (active) MonitorPalette.accent.copy(alpha = 0.14f) else Color.Transparent,
                RoundedCornerShape(9.dp),
            )
            .padding(horizontal = 9.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "Step ${index + 1}: ${step.title}, $status"
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(
            9.dp,
            if (portrait) Alignment.CenterHorizontally else Alignment.Start,
        ),
    ) {
        Box(
            Modifier.size(20.dp).background(
                when {
                    complete -> MonitorPalette.accent
                    active -> MonitorPalette.accent.copy(alpha = 0.24f)
                    else -> Color.White.copy(alpha = 0.06f)
                },
                CircleShape,
            ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (complete) "✓" else "${index + 1}",
                color = when {
                    complete -> MonitorPalette.background
                    active -> MonitorPalette.accent
                    else -> MonitorPalette.faint
                },
                style = MonitorTypography.text(9.5f, FontWeight.Bold),
                maxLines = 1,
            )
        }
        if (!portrait) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    step.title,
                    color = when {
                        active -> MonitorPalette.text
                        complete -> MonitorPalette.secondary
                        else -> MonitorPalette.faint
                    },
                    style = MonitorTypography.text(12f, FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    step.subtitle,
                    color = MonitorPalette.faint,
                    style = MonitorTypography.text(8.5f).copy(letterSpacing = 0.6.sp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun PairingPane(
    presentation: MonitorPairingPresentation,
    portrait: Boolean,
    tablet: Boolean,
    onSelect: (String) -> Unit,
    onPrimary: () -> Unit,
    onBack: () -> Unit,
    extra: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(PairingPaneFill)
            .border(1.dp, Color.White.copy(alpha = 0.04f), shape)
            .padding(
                start = if (tablet) 20.dp else 15.dp,
                top = if (tablet) 18.dp else 14.dp,
                end = if (tablet) 20.dp else 15.dp,
                bottom = if (tablet) 14.dp else 12.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(
                presentation.title,
                color = MonitorPalette.text,
                style = MonitorTypography.text(if (tablet) 25f else 19f, FontWeight.SemiBold)
                    .copy(letterSpacing = (-0.2).sp),
            )
            Text(
                presentation.body,
                color = MonitorPalette.muted,
                style = MonitorTypography.text(12.5f).copy(lineHeight = 16.5.sp),
            )
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            presentation.error?.let { message ->
                Text(
                    message,
                    color = MonitorPalette.secondary,
                    style = MonitorTypography.text(12f),
                    modifier = Modifier.fillMaxWidth()
                        .background(MonitorPalette.recording.copy(alpha = 0.12f), RoundedCornerShape(11.dp))
                        .padding(12.dp),
                )
            }
            extra()
            presentation.devices.forEach { device ->
                PairingDeviceRow(device, onSelect)
            }
            presentation.emptyTitle?.let { title ->
                Text(
                    title,
                    color = MonitorPalette.text,
                    style = MonitorTypography.text(13f, FontWeight.SemiBold),
                    modifier = Modifier.fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(11.dp))
                        .padding(13.dp),
                )
            }
            presentation.instructions.forEach { instruction ->
                PairingInstructionCard(instruction)
            }
            presentation.checks.forEach { check ->
                PairingCheckRow(check)
            }
            if (presentation.summary.isNotEmpty()) {
                val columns = if (portrait || tablet) 2 else 3
                presentation.summary.chunked(columns).forEach { row ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        row.forEach { detail ->
                            PairingSummaryCard(detail, Modifier.weight(1f))
                        }
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
            presentation.progress?.let { PairingProgressLabel(it, Modifier.padding(top = 3.dp)) }
        }
        PairingFooter(presentation, portrait, onPrimary, onBack)
    }
}

@Composable
private fun PairingDeviceRow(device: MonitorPairingDevice, onSelect: (String) -> Unit) {
    val shape = RoundedCornerShape(11.dp)
    Row(
        Modifier.fillMaxWidth()
            .clip(shape)
            .background(if (device.selected) MonitorPalette.accent.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.03f))
            .border(
                if (device.selected) 1.5.dp else 1.dp,
                if (device.selected) MonitorPalette.accent.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.06f),
                shape,
            )
            .clickable(enabled = !device.busy, role = Role.Button, onClick = { onSelect(device.id) })
            .testTag("pair.device.${device.id}")
            .semantics { contentDescription = "Connect ${device.name}" }
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Box(
            Modifier.size(26.dp).background(
                if (device.selected) MonitorPalette.accent.copy(alpha = 0.16f) else Color.White.copy(alpha = 0.05f),
                CircleShape,
            ),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(7.dp).background(
                    if (device.selected) MonitorPalette.accent else MonitorPalette.faint,
                    CircleShape,
                ),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                device.name,
                color = MonitorPalette.text,
                style = MonitorTypography.text(13.5f, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                device.subtitle,
                color = MonitorPalette.muted,
                style = MonitorTypography.text(9.5f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        device.signalBars?.let { PairingSignalBars(it) }
    }
}

@Composable
private fun PairingInstructionCard(instruction: MonitorPairingInstruction) {
    val icon = if (instruction.icon == MonitorPairingInstructionIcon.CAMERA) {
        MonitorIcon.CAMERA
    } else {
        MonitorIcon.SMARTPHONE
    }
    Column(
        Modifier.fillMaxWidth()
            .background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(11.dp))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(11.dp))
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Box(
                Modifier.size(26.dp).background(MonitorPalette.accent.copy(alpha = 0.12f), RoundedCornerShape(8.dp)),
                contentAlignment = Alignment.Center,
            ) {
                MonitorIcon(icon, null, Modifier.size(14.dp), MonitorPalette.accent)
            }
            Text(
                instruction.title.uppercase(),
                color = MonitorPalette.secondary,
                style = MonitorTypography.text(9f, FontWeight.Bold).copy(letterSpacing = 1.4.sp),
                maxLines = 1,
            )
        }
        instruction.lines.forEach { line ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("•", color = MonitorPalette.faint, style = MonitorTypography.text(12.5f))
                Text(
                    line,
                    color = MonitorPalette.secondary,
                    style = MonitorTypography.text(12.5f).copy(lineHeight = 15.5.sp),
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun PairingCheckRow(check: MonitorPairingCheck) {
    Row(
        Modifier.fillMaxWidth()
            .background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(11.dp))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(11.dp))
            .padding(13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Box(
            Modifier.size(22.dp).background(
                when (check.state) {
                    MonitorPairingCheckState.COMPLETE -> MonitorPalette.accent
                    MonitorPairingCheckState.ACTIVE -> MonitorPalette.accent.copy(alpha = 0.16f)
                    MonitorPairingCheckState.WAITING -> MonitorPalette.accent.copy(alpha = 0.04f)
                },
                CircleShape,
            ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                when (check.state) {
                    MonitorPairingCheckState.COMPLETE -> "✓"
                    MonitorPairingCheckState.ACTIVE -> "·"
                    MonitorPairingCheckState.WAITING -> ""
                },
                color = if (check.state == MonitorPairingCheckState.COMPLETE) {
                    MonitorPalette.background
                } else {
                    MonitorPalette.accent
                },
                style = MonitorTypography.text(10f, FontWeight.Bold),
                maxLines = 1,
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                check.title,
                color = MonitorPalette.text,
                style = MonitorTypography.text(13f, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                check.subtitle,
                color = MonitorPalette.muted,
                style = MonitorTypography.text(9.5f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            check.stateLabel,
            color = when (check.state) {
                MonitorPairingCheckState.COMPLETE -> PairingCheckOk
                MonitorPairingCheckState.ACTIVE -> MonitorPalette.accent
                MonitorPairingCheckState.WAITING -> MonitorPalette.faint
            },
            style = MonitorTypography.text(8.5f, FontWeight.Bold).copy(letterSpacing = 1.1.sp),
            maxLines = 1,
        )
    }
}

@Composable
private fun PairingSummaryCard(detail: MonitorPairingSummary, modifier: Modifier = Modifier) {
    Column(
        modifier
            .background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(11.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(
            detail.title.uppercase(),
            color = MonitorPalette.faint,
            style = MonitorTypography.text(8f, FontWeight.Bold).copy(letterSpacing = 1.3.sp),
            maxLines = 1,
        )
        Text(
            detail.value,
            color = MonitorPalette.secondary,
            style = MonitorTypography.text(11f, FontWeight.SemiBold),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PairingProgressLabel(title: String, modifier: Modifier = Modifier) {
    val pulse = monitorPulsePhase(1400)
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = title },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(6.dp).background(
                MonitorPalette.accent.copy(alpha = 1f - 0.75f * pulse),
                CircleShape,
            ),
        )
        Text(
            title,
            color = MonitorPalette.accent,
            style = MonitorTypography.text(10f, FontWeight.SemiBold),
        )
    }
}

@Composable
private fun PairingSignalBars(count: Int) {
    val bars = count.coerceIn(0, 4)
    Row(
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.semantics { contentDescription = "Signal $bars of 4" },
    ) {
        repeat(4) { index ->
            Box(
                Modifier.size(width = 3.dp, height = (5 + index * 3).dp)
                    .background(
                        if (index < bars) MonitorPalette.accent else Color.White.copy(alpha = 0.14f),
                        RoundedCornerShape(1.dp),
                    ),
            )
        }
    }
}

@Composable
private fun PairingFooter(
    presentation: MonitorPairingPresentation,
    portrait: Boolean,
    onPrimary: () -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        if (portrait) {
            Text(
                presentation.hint,
                color = MonitorPalette.faint,
                style = MonitorTypography.text(9.5f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            if (!portrait) {
                Text(
                    presentation.hint,
                    color = MonitorPalette.faint,
                    style = MonitorTypography.text(9.5f),
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
            }
            presentation.backAction?.let { label ->
                PairingActionButton(label, primary = false, enabled = true, onClick = onBack)
            }
            presentation.primaryAction?.let { label ->
                PairingActionButton(label, primary = true, enabled = presentation.primaryActionEnabled, onClick = onPrimary)
            }
        }
    }
}

@Composable
private fun PairingActionButton(label: String, primary: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        Modifier.alpha(if (enabled) 1f else 0.38f)
            .heightIn(min = 42.dp)
            .clip(shape)
            .background(if (primary) MonitorPalette.accent else Color.White.copy(alpha = 0.06f))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .padding(horizontal = 17.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = if (primary) PairingPrimaryInk else MonitorPalette.secondary,
            style = MonitorTypography.text(13f, FontWeight.SemiBold),
            maxLines = 1,
        )
    }
}

private val PairingPaneFill = Color(22, 23, 24)
private val PairingPrimaryInk = Color(8, 25, 31)
private val PairingCheckOk = Color(63, 211, 163)
