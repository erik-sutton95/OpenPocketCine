package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.assists.HistogramAssist
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.ParadeMode
import com.opencapture.openpocketcine.assists.VectorscopeGraticule
import com.opencapture.openpocketcine.assists.WaveformAxis
import com.opencapture.openpocketcine.assists.WaveformMode

/** Packed GPU slot / glass-plate layout. Policy only — no I/O. */
object GpuLiveLayout {
    const val SLOT_WAVE = 0
    const val SLOT_PARADE = 1
    const val SLOT_HISTO = 2
    const val SLOT_VECTOR = 3
    const val SLOT_STRIDE = 8
    const val PLATE_STRIDE = 9
    const val POINT_STRIDE = 2

    fun vertexCount(width: Int, height: Int, stride: Int = POINT_STRIDE): Int {
        val step = stride.coerceAtLeast(1)
        return (width / step).coerceAtLeast(1) * (height / step).coerceAtLeast(1)
    }

    fun waveMode(mode: WaveformMode): Int = if (mode == WaveformMode.LUMA) 0 else 1

    fun paradeMode(mode: ParadeMode): Int = if (mode == ParadeMode.YRGB) 1 else 0

    /**
     * Keep the last on-screen rect when a sibling unmounts and the bus is
     * briefly null. Off (visible=false) still clears the slot.
     */
    internal fun resolveSlotRect(visible: Boolean, incoming: GpuRect?, last: GpuRect?): GpuRect? {
        if (!visible) return null
        return incoming ?: last
    }

    fun packSlot(
        out: FloatArray,
        index: Int,
        visible: Boolean,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        mode: Int,
        intensity: Float,
        gain: Float = 1f,
    ) {
        val o = index * SLOT_STRIDE
        out[o] = if (visible) 1f else 0f
        out[o + 1] = x
        out[o + 2] = y
        out[o + 3] = w
        out[o + 4] = h
        out[o + 5] = mode.toFloat()
        out[o + 6] = intensity
        out[o + 7] = gain
    }

    /** Same RGBA as [com.opencapture.openpocketcine.LiveDesign.scopePlate]. */
    const val PANEL_FILL_R = 20f / 255f
    const val PANEL_FILL_G = 20f / 255f
    const val PANEL_FILL_B = 20f / 255f
    const val PANEL_FILL_A = 0.72f
    const val PANEL_CORNER_RADIUS_DP = 16f

    internal fun wavePlot(slotW: Float, slotH: Float, density: Float): GpuRect {
        val plot = WaveformAxis.plotRect(slotW, slotH, density)
        return GpuRect(plot.x, plot.y, plot.width, plot.height)
    }

    internal fun histoPlot(slotW: Float, slotH: Float, density: Float): GpuRect {
        val plot = HistogramAssist.plotRect(slotW, slotH, density)
        val inset = WaveformAxis.PLOT_INSET * density
        return GpuRect(
            plot.x + inset,
            plot.y,
            maxOf(1f, plot.width - inset * 2f),
            plot.height,
        )
    }

    internal fun vectorPlot(slotW: Float, slotH: Float, density: Float): GpuRect {
        val plot = VectorscopeGraticule.plotSquare(slotW, slotH, density)
        return GpuRect(plot.x, plot.y, plot.width, plot.height)
    }

    /**
     * GPU traces fill the Compose plot hole, not the whole panel. C++ must
     * not re-apply 6/26 dp gutters on top of this rect.
     */
    internal fun gpuTracePlot(
        tool: LiveAssistTool,
        panelW: Float,
        panelH: Float,
        density: Float,
    ): GpuRect =
        when (tool) {
            LiveAssistTool.WAVE, LiveAssistTool.PARADE -> wavePlot(panelW, panelH, density)
            LiveAssistTool.VECTOR -> vectorPlot(panelW, panelH, density)
            else -> GpuRect(0f, 0f, panelW, panelH)
        }

    internal fun slotFromPanelPlot(panelX: Float, panelY: Float, plot: GpuRect): GpuRect =
        GpuRect(panelX + plot.x, panelY + plot.y, plot.w, plot.h)

    /**
     * Plot used to punch the liquid-glass frame. HISTO is Compose-inside
     * (not a GPU slot) but still gets a glass ring around the same gutters.
     */
    internal fun chromePlot(
        tool: LiveAssistTool,
        panelW: Float,
        panelH: Float,
        density: Float,
    ): GpuRect? =
        when (tool) {
            LiveAssistTool.WAVE, LiveAssistTool.PARADE -> wavePlot(panelW, panelH, density)
            LiveAssistTool.VECTOR -> vectorPlot(panelW, panelH, density)
            LiveAssistTool.HISTO -> histoPlot(panelW, panelH, density)
            else -> null
        }

    /** Back-to-front GPU slot indices matching Compose last-moved stacking. */
    internal fun gpuDrawOrder(stack: List<LiveAssistTool>): IntArray =
        stack.mapNotNull(::gpuSlotIndex).toIntArray()

    internal fun gpuSlotIndex(tool: LiveAssistTool): Int? =
        when (tool) {
            LiveAssistTool.WAVE -> SLOT_WAVE
            LiveAssistTool.PARADE -> SLOT_PARADE
            LiveAssistTool.VECTOR -> SLOT_VECTOR
            else -> null
        }

    fun packPlate(
        out: FloatArray,
        index: Int,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        radius: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float,
    ) {
        val o = index * PLATE_STRIDE
        out[o] = x
        out[o + 1] = y
        out[o + 2] = w
        out[o + 3] = h
        out[o + 4] = radius
        out[o + 5] = r
        out[o + 6] = g
        out[o + 7] = b
        out[o + 8] = a
    }
}
