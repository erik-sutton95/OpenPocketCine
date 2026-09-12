package com.opencapture.monitorui

import kotlin.math.max
import kotlin.math.min

/** Logical platform points; no display density, camera, or OS state is retained. */
data class MonitorRect(val x: Float, val y: Float, val width: Float, val height: Float) {
    val maxX: Float get() = x + width
    val maxY: Float get() = y + height
    val midX: Float get() = x + width / 2f
}

data class MonitorPortraitLayout(
    val status: MonitorRect,
    val picture: MonitorRect,
    val values: MonitorRect,
    val system: MonitorRect,
    val controlsFloor: Float,
)

/** UI 2.0 layout decisions shared by brand apps; native shells retain the feed. */
object MonitorLayoutPolicy {
    fun portrait(
        width: Float, height: Float, safeTop: Float, safeBottom: Float,
        fill: Boolean, valuesVisible: Boolean, sourceAspect: Float,
    ): MonitorPortraitLayout {
        val vw = max(0f, width)
        val vh = max(0f, height)
        val tablet = min(vw, vh) >= 600f
        val ratio = sourceAspect.takeIf { it.isFinite() && it > 0f } ?: 16f / 9f
        val top = max(0f, safeTop - 8f)
        val status = MonitorRect(0f, top, vw, if (tablet) 52f else 44f)
        val systemH = if (tablet) 116f else 100f
        val systemY = max(0f, vh - max(0f, safeBottom - 14f) - systemH)
        val system = MonitorRect(0f, systemY, vw, systemH)
        val valuesH = if (!valuesVisible) 0f else if (tablet) 43f else 74f
        val valuesY = max(0f, systemY - 8f - valuesH)
        val floor = max(0f, valuesY - if (valuesVisible) 8f else 0f)
        val frameRatio = if (fill) min(ratio, 9f / 16f) else ratio
        val ceiling = if (tablet && safeTop < 20f) 8f else status.maxY
        val wide = tablet && vw / frameRatio > max(0f, floor - ceiling)
        val h = if (wide) max(0f, floor - ceiling) else vw / frameRatio
        val w = if (wide) h * frameRatio else vw
        val tall = !wide && h > floor - status.maxY
        val lowBound = if (safeTop > 20f) safeTop + 10f else top
        val y = when {
            h > vh -> (vh - h) / 2f
            tall -> min(max(lowBound, systemY - h), max(0f, vh - h))
            else -> max(ceiling, floor - h)
        }
        return MonitorPortraitLayout(status, MonitorRect((vw - w) / 2f, y, w, h),
            MonitorRect(14f, valuesY, max(0f, vw - 28f), valuesH), system, floor)
    }

    fun valueColumns(width: Float, portrait: Boolean, count: Int): Int =
        if (portrait && width < 600f) 3 else count.coerceAtLeast(1)
}
