package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.assists.HistogramAssist
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.ParadeMode
import com.opencapture.openpocketcine.assists.VectorscopeGraticule
import com.opencapture.openpocketcine.assists.WaveformAxis
import com.opencapture.openpocketcine.assists.WaveformMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GpuLiveLayoutTest {
    @Test
    fun idleScopePolicyDoesNotTapEveryFrame() {
        assertEquals(false, ScopeTapPolicy.IDLE.needsTap)
        assertEquals(0, ScopeTapPolicy.IDLE.activeScopeCount)
    }

    @Test
    fun composeScopesDoNotUseAGpuPlotHole() {
        assertEquals(false, GpuOverlayBus.usesGpuSlot(LiveAssistTool.WAVE))
        assertEquals(false, GpuOverlayBus.usesGpuSlot(LiveAssistTool.PARADE))
        assertEquals(false, GpuOverlayBus.usesGpuSlot(LiveAssistTool.VECTOR))
        assertEquals(false, GpuOverlayBus.usesGpuSlot(LiveAssistTool.HISTO))
    }

    @Test
    fun tapVertexCountMatchesCpuStrideWalk() {
        val (w, h) = PocketScopeSampler.tapSize(1280, 720)
        assertEquals(213, w)
        assertEquals(120, h)
        val stride = PocketScopeSampler.POINT_STRIDE
        assertEquals((w / stride) * (h / stride), GpuLiveLayout.vertexCount(w, h, stride))
        assertEquals(1280 / 2 * 720 / 2, GpuLiveLayout.vertexCount(1280, 720, 2))
    }

    @Test
    fun packedSlotAndPlateLayout() {
        val slots = FloatArray(GpuLiveLayout.SLOT_STRIDE * 4)
        GpuLiveLayout.packSlot(slots, GpuLiveLayout.SLOT_WAVE, true, 10f, 20f, 250f, 153f, 1, 0.25f)
        assertEquals(1f, slots[0])
        assertEquals(250f, slots[3])
        assertEquals(GpuLiveLayout.waveMode(WaveformMode.RGB).toFloat(), slots[5])
        assertEquals(0, GpuLiveLayout.waveMode(WaveformMode.LUMA))
        assertEquals(1, GpuLiveLayout.paradeMode(ParadeMode.YRGB))
        val plates = FloatArray(GpuLiveLayout.PLATE_STRIDE)
        GpuLiveLayout.packPlate(plates, 0, 1f, 2f, 3f, 4f, 16f, 0f, 0f, 0f, 0.52f)
        assertEquals(16f, plates[4])
        assertEquals(0.52f, plates[8])
    }

    @Test
    fun scopePlotsMatchComposeGuttersAtDeviceDensity() {
        val d = 3f
        val wave = GpuLiveLayout.wavePlot(250f * d, 153f * d, d)
        val axis = WaveformAxis.plotRect(250f * d, 153f * d, d)
        assertEquals(axis.x, wave.x, 0.01f)
        assertEquals(axis.y, wave.y, 0.01f)
        assertEquals(axis.width, wave.w, 0.01f)
        assertEquals(axis.height, wave.h, 0.01f)
        val histo = GpuLiveLayout.histoPlot(250f * d, 77f * d, d)
        val plot = HistogramAssist.plotRect(250f * d, 77f * d, d)
        val inset = WaveformAxis.PLOT_INSET * d
        assertEquals(plot.minX + inset, histo.x, 0.01f)
        assertEquals(plot.width - inset * 2f, histo.w, 0.01f)
        val vector = GpuLiveLayout.vectorPlot(190f * d, 190f * d, d)
        val square = VectorscopeGraticule.plotSquare(190f * d, 190f * d, d)
        assertEquals(square.x, vector.x, 0.01f)
        assertEquals(square.width, vector.w, 0.01f)
        assertEquals(20f / 255f, GpuLiveLayout.PANEL_FILL_R, 0.001f)
        assertEquals(0.72f, GpuLiveLayout.PANEL_FILL_A)
        assertEquals(16f, GpuLiveLayout.PANEL_CORNER_RADIUS_DP)
    }

    @Test
    fun gpuTraceSlotIsComposePlotNotThePanel() {
        val d = 2.75f
        val panelX = 80f
        val panelY = 40f
        val waveW = 250f * d
        val waveH = 153f * d
        val wavePlot = WaveformAxis.plotRect(waveW, waveH, d)
        val wave =
            GpuLiveLayout.slotFromPanelPlot(
                panelX,
                panelY,
                GpuLiveLayout.gpuTracePlot(LiveAssistTool.WAVE, waveW, waveH, d),
            )
        assertEquals(panelX + wavePlot.x, wave.x, 0.01f)
        assertEquals(panelY + wavePlot.y, wave.y, 0.01f)
        assertEquals(wavePlot.width, wave.w, 0.01f)
        assertEquals(wavePlot.height, wave.h, 0.01f)
        assertTrue(wave.w < waveW)
        assertTrue(wave.h < waveH)
        val parade =
            GpuLiveLayout.gpuTracePlot(LiveAssistTool.PARADE, waveW, waveH, d)
        assertEquals(wavePlot.x, parade.x, 0.01f)
        val vecW = 190f * d
        val vecH = 190f * d
        val square = VectorscopeGraticule.plotSquare(vecW, vecH, d)
        val vector =
            GpuLiveLayout.slotFromPanelPlot(
                10f,
                20f,
                GpuLiveLayout.gpuTracePlot(LiveAssistTool.VECTOR, vecW, vecH, d),
            )
        assertEquals(10f + square.x, vector.x, 0.01f)
        assertEquals(20f + square.y, vector.y, 0.01f)
        assertEquals(square.width, vector.w, 0.01f)
        assertEquals(square.height, vector.h, 0.01f)
        assertEquals(vector.w, vector.h, 0.01f)
        assertTrue(vector.w < vecW)
    }

    @Test
    fun chromePlotAndGpuDrawOrderFollowComposeStack() {
        val d = 2.75f
        val histo = GpuLiveLayout.chromePlot(LiveAssistTool.HISTO, 250f * d, 77f * d, d)
        requireNotNull(histo)
        assertTrue(histo.w < 250f * d)
        assertEquals(null, GpuLiveLayout.chromePlot(LiveAssistTool.LIGHTS, 74f, 168f, 1f))
        val order =
            GpuLiveLayout.gpuDrawOrder(
                listOf(
                    LiveAssistTool.VECTOR,
                    LiveAssistTool.HISTO,
                    LiveAssistTool.WAVE,
                    LiveAssistTool.PARADE,
                ),
            )
        assertEquals(GpuLiveLayout.SLOT_VECTOR, order[0])
        assertEquals(GpuLiveLayout.SLOT_WAVE, order[1])
        assertEquals(GpuLiveLayout.SLOT_PARADE, order[2])
        assertEquals(3, order.size)
    }

    @Test
    fun resolveSlotRectKeepsLastWhileVisible() {
        val last = GpuRect(10f, 20f, 250f, 153f)
        assertEquals(last, GpuLiveLayout.resolveSlotRect(true, null, last))
        assertEquals(GpuRect(1f, 2f, 3f, 4f), GpuLiveLayout.resolveSlotRect(true, GpuRect(1f, 2f, 3f, 4f), last))
        assertEquals(null, GpuLiveLayout.resolveSlotRect(false, last, last))
        assertEquals(null, GpuLiveLayout.resolveSlotRect(true, null, null))
    }
}
