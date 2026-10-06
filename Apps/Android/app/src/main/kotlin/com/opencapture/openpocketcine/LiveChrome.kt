package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorBatteryOutlineRow
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.chromeClickable
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.RecordConfirmationRequest
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import java.util.Locale
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.monitorui.LivePopupPlacement
import com.opencapture.monitorui.LiveChromeMetrics
import com.opencapture.monitorui.LiveMonitorLayout
import com.opencapture.monitorui.MonitorRect

val ChromeShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
fun Modifier.monitorGlass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

@Composable
fun Modifier.chromePressable(enabled: Boolean = true): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed && enabled) 0.6f else 1f, tween(120), label = "chrome-press-a")
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, tween(120), label = "chrome-press-s")
    return this
        .graphicsLayer {
            this.alpha = alpha
            scaleX = scale
            scaleY = scale
        }
        .then(Modifier)
}

fun Modifier.liveModuleFrame(rect: MonitorRect): Modifier =
    offset(rect.x.dp, rect.y.dp).size(rect.width.dp, rect.height.dp)

/** Occupies [rect] and seats wrapping chrome (InfoPill, capture strip) like iOS `alignment`. */
fun Modifier.liveModuleFrame(rect: MonitorRect, alignment: Alignment): Modifier {
    val vertical =
        when (alignment) {
            Alignment.TopStart, Alignment.TopCenter, Alignment.TopEnd -> Alignment.Top
            Alignment.BottomStart, Alignment.BottomCenter, Alignment.BottomEnd -> Alignment.Bottom
            else -> Alignment.CenterVertically
        }
    return liveModuleFrame(rect).wrapContentHeight(align = vertical, unbounded = true)
}

/**
 * Measures unbounded then scales down to [maxWidth] — iOS `minimumScaleFactor` for the
 * info-pill so chips compress instead of wrapping when the deck is tight.
 */
@Composable
fun FitScale(maxWidth: Dp, content: @Composable () -> Unit) {
    Layout(content) { measurables, _ ->
        val measurable = measurables.firstOrNull() ?: return@Layout layout(0, 0) {}
        val placeable = measurable.measure(Constraints())
        val maxPx = maxWidth.roundToPx()
        val scale = if (placeable.width > maxPx) maxPx / placeable.width.toFloat() else 1f
        val width = (placeable.width * scale).toInt()
        val height = (placeable.height * scale).toInt()
        layout(width, height) {
            placeable.placeWithLayer(0, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0f)
            }
        }
    }
}

/** Landscape top deck (OpenZCine `InfoPill` / iOS `GlassDeck`): glass hugs the nested chips. */
@Composable
fun InfoPill(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier = modifier.wrapContentWidth().monitorGlass().padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/**
 * Landscape capture strip shell (OpenZCine `MonitorCaptureStrip` / iOS `captureBarFrame`).
 * Glass hugs the readouts at 58dp; the host slot trailing-aligns this pill.
 */
@Composable
fun CaptureStripShell(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier =
            modifier
                .height(LiveChromeMetrics.CONTROL_HEIGHT_DP.dp)
                .fillMaxWidth()
                .monitorGlass()
                .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/**
 * Landscape bottom row: capture hugs its chips on the trailing edge; the
 * view-assist bar fills the leftover so the 12 dp gutter is the only gap.
 */
@Composable
fun LiveBottomChromeBand(
    band: MonitorRect,
    showAssist: Boolean,
    showCapture: Boolean,
    modifier: Modifier = Modifier,
    assist: @Composable () -> Unit,
    capture: @Composable () -> Unit,
) {
    Layout(
        modifier = modifier.liveModuleFrame(band),
        content = {
            Box(Modifier.layoutId("capture")) { if (showCapture) capture() }
            Box(Modifier.layoutId("assist")) { if (showAssist) assist() }
        },
    ) { measurables, constraints ->
        val gap = LiveChromeMetrics.BOTTOM_GAP.dp.roundToPx()
        val hug = LiveChromeMetrics.CAPTURE_HUG.dp.roundToPx()
        val captureMeasurable = measurables.first { it.layoutId == "capture" }
        val assistMeasurable = measurables.first { it.layoutId == "assist" }
        val minAssist =
            if (showAssist) max(0, (constraints.maxWidth - gap) / 3) else 0
        val maxCapture =
            if (showCapture) {
                min(hug, constraints.maxWidth - minAssist - if (showAssist) gap else 0).coerceAtLeast(0)
            } else {
                0
            }
        val capturePlaceable =
            captureMeasurable.measure(
                Constraints(maxWidth = maxCapture, maxHeight = constraints.maxHeight),
            )
        val captureW = if (showCapture) capturePlaceable.width else 0
        val assistW =
            if (!showAssist) {
                0
            } else if (captureW == 0) {
                constraints.maxWidth
            } else {
                (constraints.maxWidth - captureW - gap).coerceAtLeast(minAssist)
            }
        val assistPlaceable =
            assistMeasurable.measure(
                Constraints.fixed(assistW.coerceAtLeast(0), constraints.maxHeight),
            )
        layout(constraints.maxWidth, constraints.maxHeight) {
            if (showAssist) assistPlaceable.place(0, 0)
            if (showCapture) capturePlaceable.place(constraints.maxWidth - capturePlaceable.width, 0)
        }
    }
}



internal object LiveSessionBridge {
    fun call(target: Any, name: String, vararg args: Any?): Boolean {
        val method =
            target.javaClass.methods.firstOrNull { it.name == name && it.parameterCount == args.size }
                ?: return false
        val coerced =
            method.parameterTypes
                .mapIndexed { i, type ->
                    val arg = args[i] ?: return@mapIndexed null
                    when (type) {
                        java.lang.Float.TYPE,
                        java.lang.Float::class.java,
                        -> (arg as Number).toFloat()
                        java.lang.Double.TYPE,
                        java.lang.Double::class.java,
                        -> (arg as Number).toDouble()
                        Integer.TYPE,
                        java.lang.Integer::class.java,
                        -> (arg as Number).toInt()
                        java.lang.Boolean.TYPE,
                        java.lang.Boolean::class.java,
                        -> arg as Boolean
                        else -> arg
                    }
                }
                .toTypedArray()
        return runCatching {
                method.invoke(target, *coerced)
                true
            }
            .getOrDefault(false)
    }
}

/** Replaces [LockButton] while Live View borrows a Multiview tile. iOS `multiviewExit`. */
@Composable
fun MultiviewReturnButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .size(LiveChromeMetrics.LOCK.dp)
            .chromeClickable(onClick = onClick)
            .semantics {
                contentDescription = "Return to Multiview"
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        MonitorIcon(
            icon = MonitorIcon.LAYOUT_GRID,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
fun DispButton(
    clean: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    Column(
        modifier
            .width(LiveChromeMetrics.DISP_W.dp)
            .height(LiveChromeMetrics.DISP_H.dp)
            .monitorGlass()
            .chromeClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics {
                contentDescription = if (clean) "DISP 2 clean" else "DISP 1 live"
                role = Role.Button
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
    ) {
        Text(
            "DISP",
            color = LiveDesign.muted,
            style = LiveType.ui(com.opencapture.monitorui.MonitorLayoutPolicy.DISP_SIZE, FontWeight.Bold)
                .copy(letterSpacing = com.opencapture.monitorui.MonitorLayoutPolicy.DISP_TRACKING.sp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(
                Modifier.size(width = 14.dp, height = 3.dp)
                    .clip(CircleShape)
                    .background(if (!clean) LiveDesign.info else LiveDesign.hairlineStrong),
            )
            Box(
                Modifier.size(width = 14.dp, height = 3.dp)
                    .clip(CircleShape)
                    .background(if (clean) LiveDesign.info else LiveDesign.hairlineStrong),
            )
        }
    }
}

@Composable
fun AuxCircleButton(modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit, glyph: @Composable (Color) -> Unit) {
    val tablet = minOf(LocalConfiguration.current.screenWidthDp, LocalConfiguration.current.screenHeightDp) >= 600
    val side = com.opencapture.monitorui.MonitorLayoutPolicy.systemButtonSize(tablet)
    com.opencapture.monitorui.MonitorAuxCircleButton(
        modifier
            .size(side.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .monitorGlass(RoundedCornerShape(14.dp))
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { role = Role.Button },
        glyph = glyph,
    )
}

/** Common video control; native still capture and shooting-mode editing are explicit slots. */
@Composable
internal fun LiveCaptureButton(model: AppModel, enabled: Boolean, diameter: Float,
    modifier: Modifier = Modifier, openMode: () -> Unit) {
    val status by model.session.status.collectAsState()
    val photo = CaptureShutterPolicy.isStillCapture(status.shootingMode)
    com.opencapture.opencine.appkit.MonitorCaptureButton(model.control, diameter,
        enabled = enabled && (!photo || model.session.phase == com.opencapture.opencine.vocabulary.ConnectionPhase.LIVE),
        modifier = modifier, photo = photo, confirm = model.recordConfirmationEnabled,
        takePhoto = model::pressShutter, openMode = openMode)
}

@Composable
internal fun RecordButton(
    recording: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    confirm: Boolean = false,
    photo: Boolean = false,
    diameter: Float = LiveChromeMetrics.RECORD,
    request: RecordConfirmationRequest = CaptureShutterPolicy.request(
        shootingMode = CameraCommands.SHOOT_VIDEO,
        recording = recording,
        locked = !enabled,
        busy = !enabled,
        phase = com.opencapture.opencine.vocabulary.ConnectionPhase.LIVE,
    ),
    onClick: () -> Unit,
) {
    var confirmOpen by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<RecordConfirmationRequest?>(null) }
    LaunchedEffect(request) {
        if (CaptureShutterPolicy.shouldDismiss(pending, request)) {
            confirmOpen = false
            pending = null
        }
    }
    if (confirmOpen) {
        Dialog(
            onDismissRequest = { confirmOpen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .chromeClickable(onClick = { confirmOpen = false }),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                        .pickerPanelGlass(ChromeShape)
                        .padding(horizontal = 18.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (recording) "Stop recording?" else "Start recording?",
                        color = LiveDesign.text,
                        style = LiveType.ui(16f, FontWeight.SemiBold),
                    )
                    Text(
                        if (recording) "Stop" else "Start",
                        color = if (recording) LiveDesign.rec else LiveDesign.accent,
                        style = LiveType.ui(16f, FontWeight.SemiBold),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .chromeClickable(onClick = {
                                    val snap = pending
                                    confirmOpen = false
                                    pending = null
                                    if (CaptureShutterPolicy.canCommit(snap, request)) onClick()
                                })
                                // Both rows are plain Text, so without a role
                                // they read as label, not as something to press
                                // — at the one moment that costs a take.
                                .semantics { role = Role.Button }
                                .padding(vertical = 14.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Text(
                        "Cancel",
                        color = LiveDesign.muted,
                        style = LiveType.ui(15f, FontWeight.Medium),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .chromeClickable(onClick = { confirmOpen = false })
                                .semantics { role = Role.Button }
                                .padding(vertical = 12.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
        }
    }
    Box(
        modifier
            .size(diameter.dp)
            .then(if (recording && !enabled) Modifier.graphicsLayer { alpha = 0.72f } else Modifier)
            .chromeClickable(enabled = enabled, onClick = {
                if (confirm && request.canConfirm) {
                    pending = request
                    confirmOpen = true
                } else if (!confirm) {
                    onClick()
                }
            })
            .semantics {
                contentDescription =
                    when {
                        photo -> "Take photo"
                        recording -> "Stop recording"
                        else -> "Start recording"
                    }
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        com.opencapture.monitorui.MonitorRecordLamp(
            recording = recording, photo = photo, modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
fun BatteryPair(
    phonePercent: Int,
    phoneCharging: Boolean,
    cameraPercent: Int,
    cameraCharging: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        MonitorBatteryOutlineRow(percent = phonePercent, charging = phoneCharging, camera = false)
        MonitorBatteryOutlineRow(percent = cameraPercent, charging = cameraCharging, camera = true)
    }
}

@Composable
fun CameraBatteryReadout(percent: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.clearAndSetSemantics {
            contentDescription =
                if (percent in 0..100) "Camera battery $percent percent"
                else "Camera battery level unknown"
        },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CameraGlyph(LiveDesign.text, Modifier.size(12.dp, 10.dp))
        Text(
            if (percent in 0..100) "$percent%" else "—",
            color = LiveDesign.text,
            style = LiveType.ui(12f, FontWeight.SemiBold),
        )
    }
}

@Composable
fun TimecodeReadout(timecode: String?, modifier: Modifier = Modifier, portrait: Boolean = false) {
    val config = LocalConfiguration.current
    val tablet = min(config.screenWidthDp, config.screenHeightDp) >= 600
    val incoming = timecode?.takeIf { it.isNotBlank() }
    val clock = com.opencapture.opencine.vocabulary.timecodeClock(incoming)
        ?: if (portrait) "00:00:00" else "--:--:--"
    val raw = clock
    val colon = raw.lastIndexOf(':')
    val head = if (colon >= 0) raw.substring(0, colon + 1) else raw
    val tail = if (colon >= 0) raw.substring(colon + 1) else ""
    // Nothing on screen says these digits are a timecode, and the placeholder
    // is punctuation that speech drops entirely.
    val spoken = if (incoming == null) "Timecode not available" else "Timecode $raw"
    if (portrait) {
        Text(
            raw,
            color = LiveDesign.text,
            style = LiveType.mono(15f, FontWeight.Normal),
            maxLines = 1,
            softWrap = false,
            modifier = modifier.semantics { contentDescription = spoken },
        )
        return
    }
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(color = LiveDesign.text)) { append(head) }
            withStyle(SpanStyle(color = LiveDesign.accent)) { append(tail) }
        },
        style = LiveType.mono(if (tablet) 25f else 23f, FontWeight.Medium)
            ,
        maxLines = 1,
        softWrap = false,
        modifier =
            modifier
                .wrapContentWidth(align = Alignment.Start, unbounded = true)
                .semantics { contentDescription = spoken },
    )
}

/** "02:14" reads as digits; speech wants the units named. */
private fun spokenElapsed(seconds: Int): String {
    val minutes = seconds / 60
    val rest = seconds % 60
    val m = if (minutes == 1) "1 minute" else "$minutes minutes"
    val s = if (rest == 1) "1 second" else "$rest seconds"
    return when {
        minutes == 0 -> s
        rest == 0 -> m
        else -> "$m $s"
    }
}

/** Elapsed time comes from camera telemetry; this view never starts a timer. */
@Composable
fun RecChip(recording: Boolean, elapsedSeconds: Int = 0) {
    val config = LocalConfiguration.current
    val size = if (min(config.screenWidthDp, config.screenHeightDp) >= 600) 11.5f else 10.5f
    val pulse = com.opencapture.monitorui.monitorPulsePhase(1600, enabled = recording)
    val elapsed = elapsedSeconds.coerceAtLeast(0)
    val duration = "%02d:%02d".format(java.util.Locale.ROOT, elapsed / 60, elapsed % 60)
    Row(Modifier.graphicsLayer { alpha = 1f - .75f * pulse }
        .background(if (recording) LiveDesign.rec.copy(alpha = .9f) else Color(0xFF060708).copy(alpha = .72f), RoundedCornerShape(percent = 50))
        .padding(horizontal = 9.dp, vertical = 4.dp)
        // "REC" and "02:14" are two nodes and read as fragments. Whether the
        // chip also *announces* a start or stop is a live-region question the
        // coverage rules in ARCHITECTURE.md have to settle first; this only
        // makes the chip legible to someone who reaches it.
        .clearAndSetSemantics {
            val spoken = spokenElapsed(elapsed)
            contentDescription =
                when {
                    recording -> "Recording, $spoken"
                    elapsed > 0 -> "Standby, $spoken"
                    else -> "Standby"
                }
        }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        if (recording) Box(Modifier.size(6.dp).background(Color.White, CircleShape))
        Text(if (recording) "REC" else "STBY", color = LiveDesign.text,
            style = LiveType.ui(size, FontWeight.Medium).copy(letterSpacing = .6.sp), maxLines = 1)
        Text(duration, color = Color.White.copy(alpha = .75f),
            style = LiveType.mono(size, FontWeight.Medium), maxLines = 1)
    }
}

@Composable
fun FpsChip(fps: String, bars: Int) {
    val tint =
        when {
            bars >= 3 -> LiveDesign.good
            bars == 2 -> LiveDesign.accent
            bars == 1 -> LiveDesign.rec
            else -> LiveDesign.faint
        }
    Row(
        modifier =
            Modifier
                .wrapContentWidth(unbounded = true)
                .chipGlass(CircleShape)
                .padding(horizontal = 11.dp, vertical = 7.dp)
                // A plain `semantics` here reads the sentence, then "FPS", then
                // the number again. Only clearing collapses the row to one
                // stop; `mergeDescendants` does not (measured on device in
                // `LiveChromeSemanticsTest`).
                .clearAndSetSemantics {
                    contentDescription = "Live view $fps frames per second, $bars of 4 signal bars"
                },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalBarsGlyph(bars = bars, tint = tint)
        Text(
            "FPS",
            color = LiveDesign.faint,
            style = LiveType.mono(8f, FontWeight.Bold),
            maxLines = 1,
            softWrap = false,
        )
        Text(
            fps,
            color = LiveDesign.text,
            style = LiveType.mono(12f, FontWeight.Medium),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
fun ReadoutPill(
    value: String,
    active: Boolean = false,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    accessibilityLabel: String? = null,
    icon: @Composable (Color) -> Unit,
) {
    val surface =
        if (active) {
            Modifier.background(LiveDesign.accentDim, CircleShape).border(1.dp, LiveDesign.accentDim, CircleShape)
        } else {
            Modifier.chipGlass(CircleShape)
        }
    val spoken =
        accessibilityLabel?.let { label ->
            "$label ${value.replace(" · ", "·")}"
        }
    Row(
        modifier =
            modifier
                .then(surface)
                .wrapContentWidth(unbounded = true)
                .then(
                    if (onClick != null) {
                        Modifier.chromeClickable(enabled = enabled, onClick = onClick, onLongClick = onLongClick)
                    } else {
                        Modifier
                    },
                )
                .then(
                    if (spoken != null) {
                        Modifier.clearAndSetSemantics { contentDescription = spoken }
                    } else {
                        Modifier
                    },
                )
                .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon(if (active) LiveDesign.accent else LiveDesign.muted)
        Text(
            value.replace(" · ", "·"),
            color = if (active) LiveDesign.accent else LiveDesign.text,
            style = LiveType.mono(15f, FontWeight.Medium),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
fun CaptureSettingCell(
    label: String,
    value: String,
    widest: String,
    active: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    showFacePriorityBadge: Boolean = false,
    valueIcon: (@Composable (Color) -> Unit)? = null,
    onClick: () -> Unit,
) {
    val labelColor = if (active) LiveDesign.accent.copy(alpha = 0.85f) else LiveDesign.muted
    val valueColor = if (active) LiveDesign.accent else LiveDesign.text
    Column(
        modifier =
            modifier
                .clip(ChromeShape)
                .background(if (active) LiveDesign.accentDim else Color.Transparent)
                .then(
                    if (active) Modifier.border(1.dp, LiveDesign.accentDim, ChromeShape) else Modifier,
                )
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 4.dp, vertical = 5.dp)
                .then(
                    if (showFacePriorityBadge) {
                        Modifier.semantics {
                            contentDescription = "$label $value, ${CaptureLists.FACE_PRIORITY_TITLE}"
                        }
                    } else {
                        Modifier
                    },
                ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = labelColor, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
            if (showFacePriorityBadge) FacePrioritySmile(labelColor)
        }
        Box(contentAlignment = Alignment.Center) {
            Text(
                widest,
                color = Color.Transparent,
                style = LiveType.ui(17f, FontWeight.Medium),
                maxLines = 1,
            )
            if (valueIcon != null) {
                valueIcon(valueColor)
            } else {
                Text(value, color = valueColor, style = LiveType.ui(17f, FontWeight.Medium), maxLines = 1)
            }
        }
    }
}

/** iOS `face.smiling.fill` stand-in until Lucide. */
@Composable
private fun FacePrioritySmile(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(11.dp)) {
        val stroke = 1.2.dp.toPx()
        val r = size.minDimension / 2f
        val c = Offset(size.width / 2f, size.height / 2f)
        drawCircle(tint, r - stroke / 2f, c, style = Stroke(stroke))
        val eyeY = c.y - r * 0.22f
        val eyeOff = r * 0.28f
        drawCircle(tint, stroke * 0.65f, Offset(c.x - eyeOff, eyeY))
        drawCircle(tint, stroke * 0.65f, Offset(c.x + eyeOff, eyeY))
        drawArc(
            color = tint,
            startAngle = 20f,
            sweepAngle = 140f,
            useCenter = false,
            topLeft = Offset(c.x - r * 0.45f, c.y - r * 0.1f),
            size = Size(r * 0.9f, r * 0.85f),
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}

@Composable
fun AssistToolChip(label: String, on: Boolean, enabled: Boolean, stub: Boolean, onClick: () -> Unit) {
    Column(
        modifier =
            Modifier.clip(ChromeShape)
                .background(if (on) LiveDesign.accentDim else Color.Transparent, ChromeShape)
                .border(1.dp, if (on) LiveDesign.accent else Color.Transparent, ChromeShape)
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 8.dp, vertical = 5.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(
            label,
            color = if (on) LiveDesign.accent else LiveDesign.muted,
            style = LiveType.mono(9f, FontWeight.Medium),
            maxLines = 1,
        )
        if (stub && on) {
            Text("local", color = LiveDesign.faint, style = LiveType.mono(7f), maxLines = 1)
        }
    }
}

@Composable
fun CameraGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        drawRoundRect(tint, style = Stroke(1.3.dp.toPx()), cornerRadius = CornerRadius(1.8.dp.toPx()))
        drawCircle(tint, radius = size.minDimension * 0.22f, style = Stroke(1.2.dp.toPx()))
    }
}

@Composable
fun VideoGlyph(tint: Color, modifier: Modifier = Modifier) {
    MonitorIcon(MonitorIcon.VIDEO, null, modifier.size(14.dp), tint)
}

@Composable
fun SignalBarsGlyph(bars: Int, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(12.dp, 10.dp)) {
        val gap = 1.6.dp.toPx()
        val w = (size.width - gap * 3) / 4f
        for (i in 0 until 4) {
            val h = size.height * (0.35f + i * 0.22f)
            val color = if (i < bars) tint else tint.copy(alpha = 0.22f)
            drawRoundRect(
                color,
                topLeft = Offset(i * (w + gap), size.height - h),
                size = Size(w, h),
                cornerRadius = CornerRadius(0.8.dp.toPx()),
            )
        }
    }
}
