package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.min

/** Viewport policy for the shared assist/gimbal inspector. Shells do not recompute this. */
object MonitorInspectorPolicy {
    const val PREFERRED_WIDTH = 460f
    const val WIDTH_FRACTION = 0.92f
    const val PORTRAIT_TRAILING_FRACTION = 0.52f
    const val PORTRAIT_TRAILING_MAX = 620f
    const val NAV_WIDTH = 108f
    const val EDGE_INSET_CAP = 44f

    data class Frame(
        val width: Float,
        val height: Float,
        val portrait: Boolean,
        val trailing: Boolean,
    )

    fun width(viewportWidth: Float): Float =
        min(PREFERRED_WIDTH, max(0f, viewportWidth) * WIDTH_FRACTION)

    fun height(viewportHeight: Float, portrait: Boolean, trailing: Boolean): Float {
        val vh = max(0f, viewportHeight)
        return if (portrait && trailing) min(vh * PORTRAIT_TRAILING_FRACTION, PORTRAIT_TRAILING_MAX) else vh
    }

    fun frame(viewportWidth: Float, viewportHeight: Float, trailing: Boolean): Frame {
        val portrait = viewportHeight > viewportWidth
        return Frame(width(viewportWidth), height(viewportHeight, portrait, trailing), portrait, trailing)
    }

    fun edgeInset(portrait: Boolean, trailing: Boolean, safeLeading: Float, safeTrailing: Float): Float {
        if (portrait) return 0f
        val safe = if (trailing) safeTrailing else safeLeading
        return min(EDGE_INSET_CAP, max(0f, safe))
    }
}

/**
 * One leading/trailing inspector shell. Assist and gimbal supply navigation,
 * body and footer; they must not duplicate reveal, size or glass.
 */
@Composable
fun MonitorInspector(
    title: String,
    viewportWidth: Float,
    viewportHeight: Float,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: Boolean = false,
    safeLeading: Float = 0f,
    safeTrailing: Float = 0f,
    safeTop: Float = 0f,
    safeBottom: Float = 0f,
    hasNavigation: Boolean = true,
    close: (@Composable () -> Unit)? = null,
    navigation: @Composable (portrait: Boolean) -> Unit = {},
    footer: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val frame = MonitorInspectorPolicy.frame(viewportWidth, viewportHeight, trailing)
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val reveal by animateFloatAsState(
        if (shown) 1f else 0f,
        tween(MonitorMotion.INSPECTOR_MS, easing = MonitorMotion.EaseOutCubic),
        label = "monitor-inspector",
    )
    val shownWidth = MonitorMotion.INSPECTOR_FROM_PX +
        (frame.width - MonitorMotion.INSPECTOR_FROM_PX) * reveal
    val alignment = when {
        trailing && frame.portrait -> Alignment.CenterEnd
        trailing -> Alignment.TopEnd
        else -> Alignment.TopStart
    }
    val shape = if (trailing) RoundedCornerShape(topStart = 16.dp, bottomStart = 16.dp)
        else RoundedCornerShape(topEnd = 16.dp, bottomEnd = 16.dp)
    val edge = MonitorInspectorPolicy.edgeInset(frame.portrait, trailing, safeLeading, safeTrailing)
    val padTop = if (frame.portrait && trailing) 4f else max(4f, safeTop)
    val padBottom = if (frame.portrait && trailing) 4f else max(4f, safeBottom)
    Box(modifier.fillMaxSize().pointerInput(onDismiss) { detectTapGestures { onDismiss() } }
        .semantics { contentDescription = "Dismiss $title"; role = Role.Button }) {
        Box(
            Modifier.align(alignment).width(frame.width.dp).height(frame.height.dp)
                .clip(GenericShape { size, _ ->
                    val revealedWidth = if (frame.width > 0f) size.width * shownWidth / frame.width else 0f
                    val left = if (trailing) size.width - revealedWidth else 0f
                    addRect(androidx.compose.ui.geometry.Rect(left, 0f, left + revealedWidth, size.height))
                })
                .clip(shape),
        ) {
            Box(
                Modifier.width(frame.width.dp).height(frame.height.dp)
                    .monitorMaterial(MonitorMaterial.Expanded, shape)
                    .pointerInput(Unit) { detectTapGestures { } },
            ) {
                Column(
                    Modifier.fillMaxSize()
                        .padding(
                            start = if (!trailing) edge.dp else 0.dp,
                            end = if (trailing) edge.dp else 0.dp,
                            top = padTop.dp,
                            bottom = padBottom.dp,
                        ),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(start = 14.dp, end = 8.dp, bottom = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            title,
                            modifier = Modifier.weight(1f),
                            style = MonitorTypography.text(9f, FontWeight.SemiBold).copy(
                                letterSpacing = 1.6.sp,
                            ),
                            maxLines = 1,
                        )
                        if (close != null) close() else Box(
                            Modifier.size(44.dp).clickable(onClick = onDismiss).semantics {
                                contentDescription = "Close $title"; role = Role.Button
                            },
                            contentAlignment = Alignment.Center,
                        ) {
                            MonitorIcon(MonitorIcon.X, null, Modifier.size(13.dp), MonitorPalette.muted)
                        }
                    }
                    if (frame.portrait && hasNavigation) {
                        Box(
                            Modifier.fillMaxWidth().height(44.dp)
                                .padding(start = 14.dp, end = 10.dp, bottom = 8.dp),
                        ) { navigation(true) }
                    }
                    Row(Modifier.weight(1f).fillMaxWidth()) {
                        if (!frame.portrait && hasNavigation) {
                            Box(
                                Modifier.width(MonitorInspectorPolicy.NAV_WIDTH.dp).fillMaxHeight()
                                    .padding(start = 8.dp, end = 8.dp),
                            ) { navigation(false) }
                        }
                        Column(Modifier.weight(1f).fillMaxHeight()) {
                            Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp)) { content() }
                            footer()
                        }
                    }
                }
            }
        }
    }
}
