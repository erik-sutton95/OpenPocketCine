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
        val ceiling = status.maxY
        val wide = tablet && vw / frameRatio > max(0f, floor - ceiling)
        val h = if (wide) max(0f, floor - ceiling) else vw / frameRatio
        val w = if (wide) h * frameRatio else vw
        val y = if (h > vh || h > floor - ceiling) {
            // Impossible chrome clearance yields to canvas-centered picture placement.
            (vh - h) / 2f
        } else {
            val ideal = (vh - h) / 2f
            max(ceiling, min(ideal, floor - h))
        }
        return MonitorPortraitLayout(status, MonitorRect((vw - w) / 2f, y, w, h),
            MonitorRect(14f, valuesY, max(0f, vw - 28f), valuesH), system, floor)
    }

    /** Portrait tools follow the lower controls floor, independently of picture crop. */
    fun portraitAssists(floor: Float, tablet: Boolean): MonitorRect = MonitorRect(
        if (tablet) 14f else 10f,
        max(0f, floor - if (tablet) 102f else 94f),
        if (tablet) 60f else 52f,
        if (tablet) 86f else 78f,
    )

    fun portraitAspect(width: Float, floor: Float): MonitorRect =
        MonitorRect(max(0f, width) / 2f - 24f, max(0f, floor - 56f), 48f, 48f)

    /** Landscape readouts share the format row's center and stay inside the picture. */
    fun recordingReadoutTrailingInset(statusRight: Float, pictureRight: Float): Float =
        max(8f, statusRight - pictureRight + 12f)
    /** Landscape cutout-phone lock/settings/media drop, as a fraction of HUD height. */
    const val CUTOUT_CORNER_INSET = 0.025f

    fun portraitReadoutTop(tablet: Boolean, safeTop: Float, statusTop: Float, pictureTop: Float): Float {
        // STBY / clock / REC SETUP follow the independent status row, not the feed.
        return statusTop
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

    /** Format / color / mode hang from the top edge. Portrait sits 6dp below the info bar. */
    fun topPanel(panelHeight: Float, width: Float, height: Float, safeLeading: Float,
        safeTrailing: Float, safeTop: Float, safeBottom: Float, portraitCeiling: Float? = null,
        portraitFloor: Float? = null): Panel {
        val edge = max(14f, max(safeLeading, safeTrailing) + 4f)
        val panelWidth = min(if (min(width, height) >= 600f) 620f else 480f, max(0f, width - edge * 2f))
        val portrait = height > width
        val top = if (portrait && portraitCeiling != null) min(height, max(0f, portraitCeiling + 6f))
            else 0f
        val bottom = if (portrait && portraitFloor != null) min(height, portraitFloor - 12f)
            else height - max(0f, safeBottom)
        val room = max(0f, bottom - top)
        return Panel((width - panelWidth) / 2f, top, panelWidth, room)
    }

    fun valueColumns(width: Float, portrait: Boolean, count: Int): Int =
        if (portrait && width < 600f) 3 else count.coerceAtLeast(1)

    fun readoutValueSize(tablet: Boolean): Float = if (tablet) 18f else 16f
    const val READOUT_LABEL_SIZE = 9f
    const val READOUT_LABEL_TRACKING = 1.26f

    const val COMPACT_CAPTURE_HEIGHT = 128f
    const val CAPTURE_DRUM_HEIGHT = 86f
    const val CAPTURE_HEADER_HEIGHT = 22f
    const val CAPTURE_STACK_GAP = 8f
    fun captureTopPadding(fromTop: Boolean, portrait: Boolean, compact: Boolean): Float =
        if (!fromTop) 11f else if (compact || portrait) 12f else 16f

    fun compactCaptureBottomPadding(topPadding: Float): Float =
        max(0f, COMPACT_CAPTURE_HEIGHT - topPadding - CAPTURE_HEADER_HEIGHT - CAPTURE_STACK_GAP - CAPTURE_DRUM_HEIGHT)

    fun showsRecordingCategoryTabs(portrait: Boolean, compact: Boolean): Boolean =
        portrait && !compact

    fun showsCaptureGrabber(compact: Boolean, fromTop: Boolean): Boolean =
        !compact && !fromTop

    fun cameraPageTitleSize(tablet: Boolean): Float = if (tablet) 24f else 19f
    const val CAMERA_CARD_CORNER = 13f
    const val SETTINGS_TITLE_CONTENT_GAP = 8f
    const val SETTINGS_TITLE_MIN_HEIGHT = 24f
    const val DISP_SIZE = 12f
    const val DISP_TRACKING = 0.48f
    const val CAPTURE_PANEL_CORNER = 16f

    /** Portrait floating popups round every corner; landscape attached edges stay square. */
    fun capturePanelTopCorner(fromTop: Boolean, portrait: Boolean): Float =
        if (!fromTop || portrait) CAPTURE_PANEL_CORNER else 0f

    fun capturePanelBottomCorner(fromTop: Boolean, portrait: Boolean): Float =
        if (fromTop || portrait) CAPTURE_PANEL_CORNER else 0f
}
