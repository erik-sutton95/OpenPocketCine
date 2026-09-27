package com.opencapture.monitorui

import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Alpha-masks scrolling content at an edge only while more content lies that way.
 * Nothing is painted, so the page background shows through. Works with ScrollState,
 * LazyListState and LazyGridState. Place it before `verticalScroll`/`horizontalScroll`
 * (or on the lazy list's own modifier) so the mask stays put while content moves.
 */
fun Modifier.monitorScrollFade(
    state: ScrollableState,
    vertical: Boolean = true,
    depth: Dp = 24.dp,
): Modifier =
    graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithCache {
            val length = if (vertical) size.height else size.width
            val d = minOf(depth.toPx(), length / 2f)
            val start = if (vertical) {
                Brush.verticalGradient(listOf(Color.Transparent, Color.Black), endY = d)
            } else {
                Brush.horizontalGradient(listOf(Color.Transparent, Color.Black), endX = d)
            }
            val end = if (vertical) {
                Brush.verticalGradient(listOf(Color.Black, Color.Transparent), startY = length - d, endY = length)
            } else {
                Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = length - d, endX = length)
            }
            val band = if (vertical) Size(size.width, d) else Size(d, size.height)
            val endOrigin = if (vertical) Offset(0f, length - d) else Offset(length - d, 0f)
            onDrawWithContent {
                drawContent()
                // Read scroll state in draw, not composition, so scrolling never recomposes.
                if (state.canScrollBackward) drawRect(start, size = band, blendMode = BlendMode.DstIn)
                if (state.canScrollForward) {
                    drawRect(end, topLeft = endOrigin, size = band, blendMode = BlendMode.DstIn)
                }
            }
        }
