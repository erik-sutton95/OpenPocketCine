package com.opencapture.monitorui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** One connection setup on a saved camera. Tapping connects over it (iOS `CameraSetupChip`). */
@Immutable
data class MonitorSetupChip(val id: String, val title: String, val active: Boolean, val canForget: Boolean = false)

/** iOS `CameraConnectStep`. A backend owns progress; the card only shows it. */
@Immutable
data class MonitorConnectStep(val title: String, val detail: String, val state: State) {
    enum class State { DONE, ACTIVE, WAITING }
}

/** A failed connect stays on its card with the ways out (iOS `CameraConnectFailure`). */
@Immutable
data class MonitorConnectFailure(
    val title: String,
    val message: String,
    val actions: List<Action>,
    val link: Action? = null,
) {
    @Immutable
    data class Action(val id: String, val title: String, val primary: Boolean = false)
}

object MonitorConnectProgress {
    /** One caption at a time: the active step and its detail. */
    fun caption(steps: List<MonitorConnectStep>): String {
        val step = steps.firstOrNull { it.state == MonitorConnectStep.State.ACTIVE }
            ?: steps.lastOrNull { it.state == MonitorConnectStep.State.DONE } ?: return "Connecting"
        return if (step.detail.isEmpty()) step.title else "${step.title} · ${step.detail}"
    }

    fun fraction(steps: List<MonitorConnectStep>): Float {
        val done = steps.count { it.state == MonitorConnectStep.State.DONE }
        val active = if (steps.any { it.state == MonitorConnectStep.State.ACTIVE }) 0.5f else 0f
        return ((done + active) / steps.size.coerceAtLeast(1)).coerceIn(0.06f, 1f)
    }
}

/** OpenZCine-style setup tabs: one per way in, plus Add setup. Scrolls sideways on a portrait phone. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun MonitorSetupChips(
    cameraName: String,
    setups: List<MonitorSetupChip>,
    canAddSetup: Boolean,
    enabled: Boolean,
    onSetup: (MonitorSetupChip) -> Unit,
    onAddSetup: (() -> Unit)?,
    onForgetSetup: ((MonitorSetupChip) -> Unit)?,
) {
    val scroll = rememberScrollState()
    Row(
        Modifier.fillMaxWidth().monitorScrollFade(scroll, vertical = false).horizontalScroll(scroll),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        setups.forEach { setup ->
            var menu by remember { mutableStateOf(false) }
            val shape = RoundedCornerShape(9.dp)
            // 34 dp chip, 44 dp tap target.
            Box(
                Modifier.heightIn(min = 44.dp)
                    .combinedClickable(
                        enabled = enabled, role = Role.Button, onClick = { onSetup(setup) },
                        onLongClick = if (setup.canForget && onForgetSetup != null) ({ menu = true }) else null,
                    )
                    .semantics { contentDescription = "Connect $cameraName over ${setup.title}" }
                    .testTag("cameras.setup.${setup.id}"),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    setup.title,
                    color = if (setup.active) Color.White else MonitorPalette.muted,
                    style = MonitorTypography.text(11f, FontWeight.SemiBold),
                    maxLines = 1,
                    modifier = Modifier.heightIn(min = 34.dp).clip(shape)
                        .background(if (setup.active) MonitorPalette.accent.copy(alpha = 0.16f) else Color.White.copy(alpha = 0.05f))
                        .border(1.dp, if (setup.active) MonitorPalette.accent.copy(alpha = 0.45f) else Color.White.copy(alpha = 0.06f), shape)
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                )
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text("Forget ${setup.title} setup", color = MonitorPalette.recording) },
                        onClick = { menu = false; onForgetSetup?.invoke(setup) },
                    )
                }
            }
        }
        if (canAddSetup && onAddSetup != null) {
            val dash = MonitorPalette.secondary.copy(alpha = 0.22f)
            Row(
                Modifier.heightIn(min = 44.dp)
                    .clickable(enabled = enabled, role = Role.Button, onClick = onAddSetup)
                    .semantics { contentDescription = "Add a setup for $cameraName" }
                    .testTag("cameras.addSetup"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.heightIn(min = 34.dp)
                        .drawBehind {
                            drawRoundRect(
                                dash, cornerRadius = CornerRadius(9.dp.toPx()),
                                style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                            )
                        }
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    MonitorIcon(MonitorIcon.PLUS, null, Modifier.size(11.dp), tint = MonitorPalette.muted)
                    Text("Add setup", color = MonitorPalette.muted, style = MonitorTypography.text(11f, FontWeight.SemiBold))
                }
            }
        }
    }
}

/** Connection progress as one bar that fills per step with a sweep running through it. */
@Composable
internal fun MonitorConnectProgressBar(steps: List<MonitorConnectStep>) {
    val fraction by animateFloatAsState(MonitorConnectProgress.fraction(steps), tween(450), label = "connectFill")
    val sweep by rememberInfiniteTransition(label = "connectSweep")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart), label = "sweep")
    BoxWithConstraints(
        Modifier.fillMaxWidth().padding(vertical = 2.dp).height(4.dp).clip(CircleShape)
            .background(Color.White.copy(alpha = 0.08f))
            .semantics { contentDescription = MonitorConnectProgress.caption(steps) },
    ) {
        val fill = maxWidth * fraction
        Box(Modifier.width(fill).fillMaxHeight().clip(CircleShape).background(MonitorPalette.accent)) {
            Box(
                Modifier.width(70.dp).fillMaxHeight().offset(x = (fill + 70.dp) * sweep - 70.dp)
                    .background(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.55f), Color.Transparent))),
            )
        }
    }
}

@Composable
internal fun MonitorConnectFailureBanner(
    failure: MonitorConnectFailure,
    enabled: Boolean,
    onAction: ((String) -> Unit)?,
) {
    val warning = MonitorLinkHealth.watch
    val shape = RoundedCornerShape(11.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(warning.copy(alpha = 0.08f))
            .border(1.dp, warning.copy(alpha = 0.3f), shape)
            .padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = if (failure.link == null) 12.dp else 0.dp)
            .testTag("cameras.failure"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        MonitorIcon(MonitorIcon.TRIANGLE_ALERT, null, Modifier.size(20.dp), tint = warning)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(failure.title, color = MonitorPalette.text, style = MonitorTypography.text(13.5f, FontWeight.SemiBold))
            Text(failure.message, color = MonitorPalette.secondary, style = MonitorTypography.text(11.5f))
            failure.link?.let { link ->
                Box(
                    Modifier.heightIn(min = 44.dp)
                        .clickable(enabled = enabled && onAction != null, role = Role.Button) { onAction?.invoke(link.id) },
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(link.title, color = MonitorPalette.accent, style = MonitorTypography.text(12f, FontWeight.SemiBold))
                }
            }
        }
    }
}
