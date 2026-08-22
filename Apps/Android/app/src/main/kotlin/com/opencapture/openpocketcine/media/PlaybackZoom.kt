package com.opencapture.openpocketcine.media

import kotlin.math.max
import kotlin.math.min

/**
 * Pinch/pan zoom that stays anchored under the fingers.
 * Port of iOS `AnchoredPinchZoom` in `MediaPlayer.swift`.
 */
data class AnchoredPinchZoom(
    val scale: Float = 1f,
    val offsetX: Float = 0f,
    val offsetY: Float = 0f,
    private val committedScale: Float = 1f,
    private val committedOffsetX: Float = 0f,
    private val committedOffsetY: Float = 0f,
) {
    val isZoomed: Boolean
        get() = scale > 1.001f

    fun pinchChanged(
        magnification: Float,
        startAnchorX: Float,
        startAnchorY: Float,
        width: Float,
        height: Float,
    ): AnchoredPinchZoom {
        val target = min(MAX_SCALE, max(1f, committedScale * magnification))
        if (committedScale <= 0f) return this
        val ratio = target / committedScale
        val centroidX = (startAnchorX - 0.5f) * width
        val centroidY = (startAnchorY - 0.5f) * height
        return copy(
            scale = target,
            offsetX = centroidX - (centroidX - committedOffsetX) * ratio,
            offsetY = centroidY - (centroidY - committedOffsetY) * ratio,
        )
    }

    fun panChanged(translationX: Float, translationY: Float): AnchoredPinchZoom {
        if (!isZoomed) return this
        return copy(
            offsetX = committedOffsetX + translationX,
            offsetY = committedOffsetY + translationY,
        )
    }

    fun endGesture(width: Float, height: Float): AnchoredPinchZoom {
        if (scale < 1.05f) return AnchoredPinchZoom()
        val maxX = width * (scale - 1f) / 2f
        val maxY = height * (scale - 1f) / 2f
        val clampedX = min(maxX, max(-maxX, offsetX))
        val clampedY = min(maxY, max(-maxY, offsetY))
        return copy(
            offsetX = clampedX,
            offsetY = clampedY,
            committedScale = scale,
            committedOffsetX = clampedX,
            committedOffsetY = clampedY,
        )
    }

    fun reset(): AnchoredPinchZoom = AnchoredPinchZoom()

    companion object {
        const val MAX_SCALE = 4f
    }
}
