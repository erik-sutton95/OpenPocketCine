package com.opencapture.monitorui

import kotlin.math.atan2

enum class MonitorZoomAttachment { Trailing, Bottom }

/** Mirrors portable MonitorZoomGeometry: an inset scale in one edge-filled material. */
data class MonitorZoomGeometry(
    val radius: Float,
    val edgeExtension: Float,
    val attachment: MonitorZoomAttachment = MonitorZoomAttachment.Trailing,
) {
    val width: Float get() = if (attachment == MonitorZoomAttachment.Trailing) radius + edgeExtension else radius * 2f
    val height: Float get() = if (attachment == MonitorZoomAttachment.Trailing) radius * 2f else radius + edgeExtension

    fun contains(x: Float, y: Float): Boolean {
        if (radius <= 0f || !x.isFinite() || !y.isFinite() ||
            x < 0f || x > width || y < 0f || y > height) return false
        val inExtension = if (attachment == MonitorZoomAttachment.Trailing) x >= radius else y >= radius
        if (inExtension) return true
        return (x - radius) * (x - radius) + (y - radius) * (y - radius) <= radius * radius
    }

    /** Only the original half-disc arms zoom; its singular flat edge is excluded. */
    fun canStartZoom(x: Float, y: Float): Boolean {
        if (!contains(x, y)) return false
        return if (attachment == MonitorZoomAttachment.Trailing) x < radius else y < radius
    }

    fun angle(x: Float, y: Float): Double = if (attachment == MonitorZoomAttachment.Trailing)
        atan2((radius - x).toDouble(), (y - radius).toDouble())
    else atan2((radius - y).toDouble(), (radius - x).toDouble())

    companion object {
        fun layout(
            width: Float, height: Float, trailingInset: Float = 0f, bottomInset: Float = 0f,
            attachment: MonitorZoomAttachment = MonitorZoomAttachment.Trailing,
        ): MonitorZoomGeometry {
            val w = width.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
            val h = height.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
            return if (attachment == MonitorZoomAttachment.Trailing) {
                val extension = (trailingInset.takeIf { it.isFinite() } ?: 0f).coerceIn(0f, w)
                val reference = minOf(if (minOf(w, h) >= 600f) 330f else 260f,
                    maxOf(120f, (h - 24f) / 2f))
                MonitorZoomGeometry(minOf(reference * 1.10f, h / 2f, w - extension), extension)
            } else {
                val extension = (bottomInset.takeIf { it.isFinite() } ?: 0f).coerceIn(0f, h)
                val reference = minOf(if (minOf(w, h) >= 600f) 330f else 260f,
                    maxOf(120f, (w - 24f) / 2f))
                MonitorZoomGeometry(
                    minOf(reference * 1.10f, w / 2f, h - extension), extension,
                    MonitorZoomAttachment.Bottom,
                )
            }
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

    private fun radialAngle(x: Float, y: Float): Double? {
        if (!isArmed || !x.isFinite() || !y.isFinite()) return null
        val onScale = if (geometry.attachment == MonitorZoomAttachment.Trailing) x < geometry.radius
        else y < geometry.radius
        return if (onScale) geometry.angle(x, y) else null
    }
}
