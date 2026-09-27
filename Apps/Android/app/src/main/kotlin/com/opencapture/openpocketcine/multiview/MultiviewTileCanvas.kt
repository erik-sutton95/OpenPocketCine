package com.opencapture.openpocketcine.multiview

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MultiviewPresentationLayout
import com.opencapture.openpocketcine.LiveDesign
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Four permanent siblings: scrolling moves/clips hosts without detaching Android output surfaces. */
@Composable
internal fun MultiviewTileCanvas(
    tileKeys: List<String>,
    layout: MultiviewPresentationLayout,
    modifier: Modifier = Modifier,
    content: @Composable (index: Int, compact: Boolean) -> Unit,
) {
    val scroll = rememberScrollState()
    val density = LocalDensity.current.density
    val viewport = layout.secondaryViewport
    Box(modifier.fillMaxSize()) {
        // The native scroll container supplies range, fling and accessibility actions. Its
        // feed siblings share that state so TextureViews never move between native parents.
        viewport?.let { frame ->
            val contentHeight = layout.secondaryIndices.maxOf { layout.tiles[it].maxY } - frame.y
            Box(Modifier.offset(frame.x.dp, frame.y.dp).requiredSize(frame.width.dp, frame.height.dp)
                .verticalScroll(scroll).testTag("multiview.secondaryStrip")) {
                Box(Modifier.requiredSize(frame.width.dp, contentHeight.dp))
            }
        }
        tileKeys.forEachIndexed { index, identity ->
            key(identity) {
                val frame = layout.tiles[index]
                val secondary = index in layout.secondaryIndices
                Box(Modifier
                    .offset {
                        IntOffset((frame.x * density).roundToInt(),
                            (frame.y * density).roundToInt() - if (secondary) scroll.value else 0)
                    }
                    .requiredSize(frame.width.dp, frame.height.dp)
                    .graphicsLayer {
                        clip = true
                        shape = if (secondary && viewport != null) {
                            TileViewportClip((viewport.y - frame.y) * density + scroll.value,
                                (viewport.maxY - frame.y) * density + scroll.value)
                        } else androidx.compose.ui.graphics.RectangleShape
                        compositingStrategy = if (secondary) CompositingStrategy.Offscreen else CompositingStrategy.Auto
                    }
                    .stripFade(frame, viewport.takeIf { secondary }, scroll)
                    .scrollable(scroll, Orientation.Vertical, enabled = secondary, reverseDirection = true)
                    .clip(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))) {
                    content(index, secondary || frame.width < 200f || frame.height < 136f)
                }
            }
        }
    }
}

private data class TileViewportClip(val top: Float, val bottom: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Rectangle(Rect(0f, top.coerceIn(0f, size.height), size.width, bottom.coerceIn(0f, size.height)))
}

/** Read local scroll state only during drawing; no geometry publication or per-frame composition. */
private fun Modifier.stripFade(frame: MonitorRect, viewport: MonitorRect?, scroll: ScrollState): Modifier =
    drawWithContent {
        drawContent()
        if (viewport != null) {
            val top = (viewport.y - frame.y) * density + scroll.value
            val bottom = (viewport.maxY - frame.y) * density + scroll.value
            val fade = min(24.dp.toPx(), viewport.height * density / 3)
            if (scroll.canScrollBackward) {
                val start = max(0f, top)
                val end = min(size.height, top + fade)
                if (end > start) drawRect(
                    Brush.verticalGradient(listOf(Color.Transparent, Color.Black), startY = top, endY = top + fade),
                    topLeft = Offset(0f, start), size = Size(size.width, end - start), blendMode = BlendMode.DstIn,
                )
            }
            if (scroll.canScrollForward) {
                val start = max(0f, bottom - fade)
                val end = min(size.height, bottom)
                if (end > start) drawRect(
                    Brush.verticalGradient(listOf(Color.Black, Color.Transparent), startY = bottom - fade, endY = bottom),
                    topLeft = Offset(0f, start), size = Size(size.width, end - start), blendMode = BlendMode.DstIn,
                )
            }
        }
    }
