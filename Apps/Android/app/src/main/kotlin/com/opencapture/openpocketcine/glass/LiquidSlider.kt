package com.opencapture.openpocketcine.glass

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastCoerceIn
import androidx.compose.ui.util.fastRoundToInt
import androidx.compose.ui.util.lerp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.InnerShadow
import com.kyant.backdrop.shadow.Shadow
import com.kyant.shapes.Capsule
import com.opencapture.openpocketcine.LiveDesign
import kotlinx.coroutines.flow.collectLatest

/**
 * Kyant catalog `LiquidSlider` — liquid-glass capsule thumb over a thin track,
 * with damped drag, press scale, and combined backdrop sampling.
 *
 * Source: https://github.com/Kyant0/AndroidLiquidGlass
 * (`app/.../catalog/components/LiquidSlider.kt`, Apache-2.0).
 *
 * [accentColor] defaults to Pocket cyan so the control matches live chrome.
 */
@Composable
internal fun LiquidSlider(
    value: () -> Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    visibilityThreshold: Float,
    backdrop: Backdrop,
    modifier: Modifier = Modifier,
    onValueChangeFinished: (() -> Unit)? = null,
    accentColor: Color = LiveDesign.accent,
    trackColor: Color = Color(0xFF787880).copy(alpha = 0.36f),
    /**
     * When false (FLAT glass tier / low-end devices), the thumb is a solid
     * white capsule — no Kyant blur/lens path.
     */
    useLiquidGlass: Boolean = true,
) {
    val trackBackdrop = rememberLayerBackdrop()
    val latestValue by rememberUpdatedState(value)
    val latestOnValueChange by rememberUpdatedState(onValueChange)
    val latestOnValueChangeFinished by rememberUpdatedState(onValueChangeFinished)

    BoxWithConstraints(
        modifier.fillMaxWidth(),
        contentAlignment = Alignment.CenterStart,
    ) {
        val trackWidth = constraints.maxWidth

        val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
        val animationScope = rememberCoroutineScope()
        var didDrag by remember { mutableStateOf(false) }
        // While the finger is down, ignore parent refeeds so discrete-step hosts (0…10)
        // cannot snap the pill back to the last committed integer every frame.
        var isDragging by remember { mutableStateOf(false) }
        val trackWidthState = rememberUpdatedState(trackWidth)
        val dampedDragAnimation =
            remember(animationScope, valueRange, visibilityThreshold, isLtr) {
                DampedDragAnimation(
                    animationScope = animationScope,
                    initialValue = latestValue(),
                    valueRange = valueRange,
                    visibilityThreshold = visibilityThreshold,
                    initialScale = 1f,
                    pressedScale = 1.5f,
                    onDragStarted = {
                        isDragging = true
                        didDrag = false
                    },
                    onDragStopped = {
                        if (didDrag) {
                            latestOnValueChange(targetValue)
                        }
                        isDragging = false
                        didDrag = false
                        latestOnValueChangeFinished?.invoke()
                    },
                    onDrag = { _, dragAmount ->
                        if (!didDrag) {
                            didDrag = dragAmount.x != 0f
                        }
                        val width = trackWidthState.value.coerceAtLeast(1)
                        val delta =
                            (valueRange.endInclusive - valueRange.start) *
                                (dragAmount.x / width)
                        val next =
                            if (isLtr) {
                                (targetValue + delta).coerceIn(valueRange)
                            } else {
                                (targetValue - delta).coerceIn(valueRange)
                            }
                        // Follow the finger immediately (catalog only notifies the parent).
                        snapValue(next)
                        latestOnValueChange(next)
                    },
                )
            }
        LaunchedEffect(dampedDragAnimation, isDragging) {
            snapshotFlow { latestValue() }
                .collectLatest { next ->
                    if (!isDragging && dampedDragAnimation.targetValue != next) {
                        dampedDragAnimation.updateValue(next)
                    }
                }
        }

        Box(Modifier.layerBackdrop(trackBackdrop)) {
            Box(
                Modifier
                    .clip(Capsule())
                    .background(trackColor)
                    .pointerInput(animationScope, valueRange, isLtr, trackWidth) {
                        detectTapGestures { position ->
                            val delta =
                                (valueRange.endInclusive - valueRange.start) *
                                    (position.x / trackWidth.coerceAtLeast(1))
                            val targetValue =
                                (
                                    if (isLtr) {
                                        valueRange.start + delta
                                    } else {
                                        valueRange.endInclusive - delta
                                    }
                                ).coerceIn(valueRange)
                            dampedDragAnimation.animateToValue(targetValue)
                            latestOnValueChange(targetValue)
                            latestOnValueChangeFinished?.invoke()
                        }
                    }
                    .height(6.dp)
                    .fillMaxWidth(),
            )

            Box(
                Modifier
                    .clip(Capsule())
                    .background(accentColor)
                    .height(6.dp)
                    .layout { measurable, constraints ->
                        val placeable = measurable.measure(constraints)
                        val width =
                            (constraints.maxWidth * dampedDragAnimation.progress)
                                .fastRoundToInt()
                                .coerceAtLeast(0)
                        layout(width, placeable.height) {
                            placeable.place(0, 0)
                        }
                    },
            )
        }

        val thumbChrome: Modifier =
            if (useLiquidGlass) {
                Modifier.drawBackdrop(
                    backdrop =
                        rememberCombinedBackdrop(
                            backdrop,
                            rememberBackdrop(trackBackdrop) { drawBackdrop ->
                                val progress = dampedDragAnimation.pressProgress
                                val scaleX = lerp(2f / 3f, 1f, progress)
                                val scaleY = lerp(0f, 1f, progress)
                                scale(scaleX, scaleY) {
                                    drawBackdrop()
                                }
                            },
                        ),
                    shape = { Capsule() },
                    effects = {
                        val progress = dampedDragAnimation.pressProgress
                        blur(8f.dp.toPx() * (1f - progress))
                        lens(
                            10f.dp.toPx() * progress,
                            14f.dp.toPx() * progress,
                            chromaticAberration = true,
                        )
                    },
                    highlight = {
                        val progress = dampedDragAnimation.pressProgress
                        Highlight.Ambient.copy(
                            width = Highlight.Ambient.width / 1.5f,
                            blurRadius = Highlight.Ambient.blurRadius / 1.5f,
                            alpha = progress,
                        )
                    },
                    shadow = {
                        Shadow(
                            radius = 4.dp,
                            color = Color.Black.copy(alpha = 0.05f),
                        )
                    },
                    innerShadow = {
                        val progress = dampedDragAnimation.pressProgress
                        InnerShadow(
                            radius = 4.dp * progress,
                            alpha = progress,
                        )
                    },
                    layerBlock = {
                        scaleX = dampedDragAnimation.scaleX
                        scaleY = dampedDragAnimation.scaleY
                        val velocity = dampedDragAnimation.velocity / 10f
                        scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                        scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                    },
                    onDrawSurface = {
                        val progress = dampedDragAnimation.pressProgress
                        drawRect(Color.White.copy(alpha = 1f - progress))
                    },
                )
            } else {
                // FLAT tier: solid white capsule — no RuntimeShader blur/lens cost.
                Modifier.background(Color.White, Capsule())
            }

        Box(
            Modifier
                .graphicsLayer {
                    translationX =
                        (
                            -size.width / 2f +
                                trackWidth * dampedDragAnimation.progress
                        ).fastCoerceIn(
                            -size.width / 4f,
                            trackWidth - size.width * 3f / 4f,
                        ) * if (isLtr) 1f else -1f
                    if (useLiquidGlass) {
                        scaleX = dampedDragAnimation.scaleX
                        scaleY = dampedDragAnimation.scaleY
                    }
                }
                .then(dampedDragAnimation.modifier)
                .then(thumbChrome)
                .size(40.dp, 24.dp),
        )
    }
}
