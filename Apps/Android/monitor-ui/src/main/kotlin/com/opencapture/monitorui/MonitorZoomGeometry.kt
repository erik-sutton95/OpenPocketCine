package com.opencapture.monitorui

import kotlin.math.atan2

/** Mirrors portable MonitorZoomGeometry: an inset scale in one edge-filled material. */
data class MonitorZoomGeometry(val radius: Float, val edgeExtension: Float) {
    val width: Float get() = radius + edgeExtension
    val height: Float get() = radius * 2f

    fun contains(x: Float, y: Float): Boolean {
        if (radius <= 0f || !x.isFinite() || !y.isFinite() ||
            x < 0f || x > width || y < 0f || y > height) return false
        if (x >= radius) return true
        return (x - radius) * (x - radius) + (y - radius) * (y - radius) <= radius * radius
    }

    /** Only the original half-disc arms zoom; its singular flat edge is excluded. */
    fun canStartZoom(x: Float, y: Float): Boolean = x < radius && contains(x, y)

    fun angle(x: Float, y: Float): Double =
        atan2((radius - x).toDouble(), (y - radius).toDouble())

    companion object {
        fun layout(width: Float, height: Float, trailingInset: Float = 0f): MonitorZoomGeometry {
            val w = width.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
            val h = height.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
            val extension = (trailingInset.takeIf { it.isFinite() } ?: 0f).coerceIn(0f, w)
            val reference = minOf(if (minOf(w, h) >= 600f) 330f else 260f,
                maxOf(120f, (h - 24f) / 2f))
            return MonitorZoomGeometry(minOf(reference * 1.10f, h / 2f, w - extension), extension)
        }
    }
}

/** Mirrors the Swift pointer policy: extension input pauses, reentry rebases without a jump. */
class MonitorZoomRadialGesture(private val geometry: MonitorZoomGeometry, startX: Float, startY: Float) {
    val isArmed = geometry.canStartZoom(startX, startY)
    private var lastAngle: Double? = if (isArmed) geometry.angle(startX, startY) else null
    private var accumulatedAngle = 0.0

    /** Skip native touch-slop movement without changing accumulated output. */
    fun rebase(x: Float, y: Float) { lastAngle = radialAngle(x, y) }

    fun angleDelta(x: Float, y: Float): Double? {
        if (!isArmed) return null
        val next = radialAngle(x, y)
        if (next == null) { lastAngle = null; return null }
        val previous = lastAngle
        lastAngle = next
        if (previous == null) return null
        accumulatedAngle += next - previous
        return accumulatedAngle
    }

    private fun radialAngle(x: Float, y: Float): Double? =
        if (isArmed && x.isFinite() && y.isFinite() && x < geometry.radius) geometry.angle(x, y) else null
}
