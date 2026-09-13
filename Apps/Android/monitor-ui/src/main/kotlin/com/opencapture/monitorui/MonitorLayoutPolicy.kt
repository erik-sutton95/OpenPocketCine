package com.opencapture.monitorui

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

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

    /** Landscape readouts share the format row's center and stay inside the picture. */
    fun recordingReadoutTrailingInset(statusRight: Float, pictureRight: Float): Float =
        max(8f, statusRight - pictureRight + 12f)
    /** Landscape cutout-phone lock/settings/media drop, as a fraction of HUD height. */
    const val CUTOUT_CORNER_INSET = 0.025f

    fun portraitReadoutTop(tablet: Boolean, safeTop: Float, statusTop: Float, pictureTop: Float): Float {
        if (tablet) return 12f
        val gaugeTop = if (safeTop > 20f) max(4f, statusTop - 16f) else 4f
        return max(max(if (safeTop > 20f) 50f else 8f, gaugeTop + 36f), pictureTop + 8f)
    }

    fun cutoutPhoneCornerInset(viewportHeight: Float, tablet: Boolean, hasDisplayCutout: Boolean): Float =
        if (!tablet && hasDisplayCutout) CUTOUT_CORNER_INSET * max(0f, viewportHeight) else 0f

    fun assistButtonSize(tablet: Boolean): Float = if (tablet) 52f else 44f

    fun assistIconSize(tablet: Boolean): Float = if (tablet) 24f else 20f

    fun assistAvailableWidth(screenWidth: Float, portrait: Boolean, tablet: Boolean, cornerRadius: Float = 42f): Float {
        val inset = if (portrait) 14f else max(14f, (cornerRadius * 0.42f).roundToInt().toFloat())
        val recW = (if (tablet) 84f else 70f) + 16f + 12f
        val clusterW = assistButtonSize(tablet) + 15f + 14f
        val pad = if (portrait) 14f + recW else max(inset + clusterW + 12f, 14f + recW)
        return max(1f, screenWidth - pad - inset)
    }

    fun assistCellWidth(screenWidth: Float, portrait: Boolean, tablet: Boolean, cornerRadius: Float = 42f): Float =
        max(44f, floor((assistAvailableWidth(screenWidth, portrait, tablet, cornerRadius) - 44f) / 7f))

    data class Panel(val x: Float, val y: Float, val width: Float, val maxHeight: Float)

    fun bottomPanel(panelHeight: Float, width: Float, height: Float, safeLeading: Float,
        safeTrailing: Float, safeTop: Float, safeBottom: Float, portraitFloor: Float? = null): Panel {
        val edge = max(14f, max(safeLeading, safeTrailing) + 4f)
        val panelWidth = min(if (min(width, height) >= 600f) 620f else 480f, max(0f, width - edge * 2f))
        val bottom = if (height > width && portraitFloor != null) min(height, portraitFloor - 12f)
            else height - max(0f, safeBottom)
        val top = max(14f, safeTop + 10f)
        val room = max(0f, bottom - top)
        return Panel((width - panelWidth) / 2f, max(top, bottom - min(panelHeight, room)), panelWidth, room)
    }

    fun valueColumns(width: Float, portrait: Boolean, count: Int): Int =
        if (portrait && width < 600f) 3 else count.coerceAtLeast(1)
}
