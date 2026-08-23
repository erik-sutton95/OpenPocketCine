package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.reportChromeFrame
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.monitorGlass

/**
 * OpenZCine landscape assist strip: glass pill, tools in groups of three,
 * AUDIO in its own trailing section, cyan edge chevrons + fades.
 */
@Composable
fun LiveAssistBar(
    enabled: Boolean,
    on: Set<LiveAssistTool>,
    modifier: Modifier = Modifier,
    onToggle: (LiveAssistTool) -> Unit,
) {
    LiveAssistBarRow(
        locked = !enabled,
        isOn = { it in on },
        onClick = onToggle,
        onLongPress = {},
        modifier = modifier,
    )
}

@Composable
fun LiveAssistBar(
    state: LiveAssistState,
    locked: Boolean,
    onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier,
) {
    val frames = remember { mutableStateMapOf<LiveAssistTool, ChromeRect>() }
    LiveAssistBarRow(
        locked = locked,
        isOn = { state.isOn(it) },
        onClick = { state.toggle(it) },
        onLongPress = { tool ->
            if (tool.hasConfiguration) {
                frames[tool]?.let { state.longPressAnchor = it }
                state.configureTool = tool
                onLongPress(tool)
            }
        },
        onToolFrame = { tool, rect -> frames[tool] = rect },
        modifier = modifier,
    )
}

/**
 * iOS playback assist strip: [playbackToolbarCases] in groups of three, including
 * AUDIO in the scroll. Parent supplies the glass; chips only.
 */
@Composable
fun PlaybackAssistBar(
    state: LiveAssistState,
    onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = rememberScrollState()
    Row(
        modifier.horizontalScroll(scroll),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LiveAssistTool.playbackToolbarCases.forEachIndexed { index, tool ->
            if (index > 0 && index % 3 == 0) AssistDivider()
            AssistToolCell(
                tool = tool,
                isOn = state.isPlaybackVisible(tool),
                enabled = true,
                onLongClick =
                    if (tool.hasConfiguration) {
                        {
                            state.configureTool = tool
                            onLongPress(tool)
                        }
                    } else {
                        null
                    },
                onClick = { state.togglePlayback(tool) },
            )
        }
    }
}

@Composable
private fun LiveAssistBarRow(
    locked: Boolean,
    isOn: (LiveAssistTool) -> Boolean,
    onClick: (LiveAssistTool) -> Unit,
    onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier,
    onToolFrame: (LiveAssistTool, ChromeRect) -> Unit = { _, _ -> },
) {
    val scroll = rememberScrollState()
    val leadingFade = scroll.canScrollBackward
    val trailingFade = scroll.canScrollForward
    Box(
        modifier
            .height(LiveDesign.CONTROL_HEIGHT_DP.dp)
            .fillMaxWidth()
            .monitorGlass(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .padding(start = 7.dp, end = 14.dp)
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    val fade = size.width * 0.09f
                    if (leadingFade) {
                        drawRect(
                            Brush.horizontalGradient(
                                0f to Color.Transparent,
                                1f to Color.Black,
                                endX = fade,
                            ),
                            size = Size(fade, size.height),
                            blendMode = BlendMode.DstIn,
                        )
                    }
                    if (trailingFade) {
                        drawRect(
                            Brush.horizontalGradient(
                                0f to Color.Black,
                                1f to Color.Transparent,
                                startX = size.width - fade,
                                endX = size.width,
                            ),
                            topLeft = Offset(size.width - fade, 0f),
                            size = Size(fade, size.height),
                            blendMode = BlendMode.DstIn,
                        )
                    }
                }
                .horizontalScroll(scroll, enabled = !locked),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LiveAssistTool.toolbarCases.forEachIndexed { index, tool ->
                if (index > 0 && index % 3 == 0) AssistDivider()
                AssistToolCell(
                    tool = tool,
                    isOn = isOn(tool),
                    enabled = !locked,
                    onLongClick =
                        if (tool.hasConfiguration) {
                            { onLongPress(tool) }
                        } else {
                            null
                        },
                    onClick = { onClick(tool) },
                    modifier = Modifier.reportChromeFrame { onToolFrame(tool, it) },
                )
            }
            AssistDivider()
            AssistToolCell(
                tool = LiveAssistTool.AUDIO,
                isOn = isOn(LiveAssistTool.AUDIO),
                enabled = !locked,
                onLongClick = null,
                onClick = { onClick(LiveAssistTool.AUDIO) },
            )
        }
        AssistScrollChevron(
            leading = true,
            visible = leadingFade,
            modifier = Modifier.align(Alignment.CenterStart),
        )
        AssistScrollChevron(
            leading = false,
            visible = trailingFade,
            modifier = Modifier.align(Alignment.CenterEnd),
        )
    }
}

@Composable
private fun AssistDivider() {
    Box(
        Modifier
            .padding(horizontal = 3.dp)
            .size(width = 1.dp, height = 28.dp)
            .background(LiveDesign.hairlineStrong),
    )
}
