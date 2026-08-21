package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScopeGeometryTest {
    @Test
    fun panelSizesMatchIos() {
        assertEquals(250f, ScopePanelSize.waveform.width)
        assertEquals(153f, ScopePanelSize.waveform.height)
        assertEquals(250f, ScopePanelSize.parade.width)
        assertEquals(153f, ScopePanelSize.parade.height)
        assertEquals(250f, ScopePanelSize.histogram.width)
        assertEquals(77f, ScopePanelSize.histogram.height)
        assertEquals(190f, ScopePanelSize.vectorscope.width)
        assertEquals(190f, ScopePanelSize.vectorscope.height)
        assertEquals(74f, ScopePanelSize.trafficLights.width)
        assertEquals(168f, ScopePanelSize.trafficLights.height)
        assertEquals(28f, ScopePanelSize.audio.width)
        assertEquals(168f, ScopePanelSize.audio.height)
    }

    @Test
    fun waveformAxisPinsZeroAndOneHundredOnPlotEdges() {
        val size = ScopePanelSize.waveform
        val plot = WaveformAxis.plotRect(size.width, size.height)
        assertEquals(WaveformAxis.TITLE_HEIGHT, plot.minY, 0.01f)
        assertEquals(size.height - WaveformAxis.BOTTOM_PAD, plot.maxY, 0.01f)
        val line0 = WaveformAxis.plotY(0.0, plot)
        val line100 = WaveformAxis.plotY(100.0, plot)
        assertEquals(plot.maxY - WaveformAxis.PLOT_INSET, line0, 0.01f)
        assertEquals(plot.minY + WaveformAxis.PLOT_INSET, line100, 0.01f)
        assertEquals(plot.minX + WaveformAxis.PLOT_INSET, WaveformAxis.plotX(0.0, plot), 0.01f)
        assertEquals(plot.maxX - WaveformAxis.PLOT_INSET, WaveformAxis.plotX(100.0, plot), 0.01f)
        assertEquals(30.50, WaveformAxis.middleGrayIRE(CameraCommands.COLOR_DLOG2), 0.01)
        assertEquals(39.88, WaveformAxis.middleGrayIRE(CameraCommands.COLOR_DLOG), 0.01)
        assertEquals(40.9, WaveformAxis.middleGrayIRE(CameraCommands.COLOR_NORMAL), 0.05)
    }

    @Test
    fun histogramPlotUsesGutteredWaveAxis() {
        val size = ScopePanelSize.histogram
        val plot = HistogramAssist.plotRect(size.width, size.height)
        assertEquals(HistogramAssist.trafficGutter, plot.minX, 0.01f)
        assertEquals(WaveformAxis.TITLE_HEIGHT, plot.minY, 0.01f)
        assertEquals(size.width - HistogramAssist.trafficGutter * 2f, plot.width, 0.01f)
        assertEquals(
            HistogramAssist.ireX(0.0, plot),
            plot.minX + WaveformAxis.PLOT_INSET,
            0.01f,
        )
        assertEquals(
            HistogramAssist.ireX(100.0, plot),
            plot.maxX - WaveformAxis.PLOT_INSET,
            0.01f,
        )
        val clip = HistogramAssist.ireX(HistogramAssist.CLIP_ZONE_IRE, plot)
        assertTrue(clip > HistogramAssist.ireX(50.0, plot))
        assertTrue(clip < HistogramAssist.ireX(100.0, plot))
    }

    @Test
    fun paradeLanesAndVectorChip() {
        assertEquals(3, ParadeMode.RGB.laneCount)
        assertEquals(4, ParadeMode.YRGB.laneCount)
        assertEquals(listOf("R", "G", "B"), ParadeMode.RGB.laneLabels)
        assertEquals(listOf("Y", "R", "G", "B"), ParadeMode.YRGB.laneLabels)
        assertEquals("RGB", ParadeAssist.chip(ParadeMode.RGB))
        assertEquals("YRGB parade", ParadeAssist.accessibilityLabel(ParadeMode.YRGB))
        val plot = WaveformAxis.plotRect(250f, 153f)
        val w = ParadeAssist.laneWidth(ParadeMode.RGB, plot)
        assertEquals(plot.width / 3f, w, 0.01f)
        assertEquals("MON · 1X", VectorscopeAssist.chip(VectorscopeZoom.X1))
        assertEquals(2.0, VectorscopeZoom.X2.gain)
        assertEquals(4.0, VectorscopeZoom.X4.gain)
    }

    @Test
    fun movablePanelClampSnapAndDefaultCenters() {
        assertEquals(0.6, MovablePanelMath.clampedScale(0.2), 1e-9)
        assertEquals(1.6, MovablePanelMath.clampedScale(3.0), 1e-9)
        val size = MovablePanelMath.panelSize(ScopePanelSize.vectorscope, 2.0)
        assertEquals(304f, size.width)
        assertEquals(304f, size.height)
        val snapped = MovablePanelMath.snap(AssistPoint(11f, 23f))
        assertEquals(12f, snapped.x, 0.01f)
        assertEquals(24f, snapped.y, 0.01f)
        assertEquals(2 * 100_000 + 1, MovablePanelMath.hapticCell(AssistPoint(44f, 22f)))

        val bounds = AssistRect(0f, 0f, 800f, 400f)
        val feed = AssistRect(40f, 20f, 720f, 360f)
        val wave = ScopePanelSize.waveform
        val topLeading = MovablePanelMath.defaultCenterTopLeading(feed, wave, bounds)
        assertEquals(feed.minX + wave.width / 2f, topLeading.x, 0.5f)
        val topTrailing = MovablePanelMath.defaultCenterTopTrailing(feed, ScopePanelSize.vectorscope, bounds)
        assertEquals(feed.maxX - 190f / 2f, topTrailing.x, 0.5f)
        val stored = StoredCenter(AssistPoint(750f, 125f), AssistRect(0f, 0f, 1000f, 500f))
        assertEquals(0.75, stored.xFraction, 0.001)
        assertEquals(0.25, stored.yFraction, 0.001)
    }

    @Test
    fun trafficLightsCompensationAndNeutralDisplay() {
        assertEquals(listOf("0", "0.25", "0.5", "0.75", "1.0"), CrushClipCompensation.entries.map { it.label })
        assertEquals(listOf(0, 2, 5, 7, 10), CrushClipCompensation.entries.map { it.raw })
        assertEquals(0.025, CrushClipCompensation.QUARTER.pixelFractionThreshold, 1e-12)
        assertEquals(0.10, CrushClipCompensation.ONE.pixelFractionThreshold, 1e-12)
        val neutral = TrafficLightsAssist.channelDisplay(0.5)
        assertEquals(TrafficLightsAssist.BarSide.NEUTRAL, neutral.side)
        val over = TrafficLightsAssist.channelDisplay(0.8)
        assertEquals(TrafficLightsAssist.BarSide.OVER, over.side)
        val under = TrafficLightsAssist.channelDisplay(0.2)
        assertEquals(TrafficLightsAssist.BarSide.UNDER, under.side)
    }

    @Test
    fun vectorscopeGraticuleSkinAndTargets() {
        val square = VectorscopeGraticule.plotSquare(190f, 190f)
        assertEquals(square.width, square.height, 0.01f)
        val skin = VectorscopeGraticule.skinEnd(square)
        // 123° from +B-Y (right) is the NTSC I/skin axis in Q2 (left, up).
        assertTrue(skin.x < square.midX)
        assertTrue(skin.y < square.midY)
        val r = VectorscopeGraticule.targetCenter(191, 0, 0, square)
        // Rec.709 red: B−Y negative (left), R−Y positive (up).
        assertTrue(r.x < square.midX)
        assertTrue(r.y < square.midY)
    }

    @Test
    fun lumaHistogramIs256Bins() {
        val empty = LiveLumaHistogram.empty()
        assertEquals(256, empty.size)
        assertTrue(empty.all { it == 0 })
        val white = IntArray(4) { 0xFFFFFFFF.toInt() }
        val bins = LiveLumaHistogram.fromArgb(white)
        assertEquals(4, bins[255])
        val black = IntArray(3) { 0xFF000000.toInt() }
        assertEquals(3, LiveLumaHistogram.fromArgb(black)[0])
    }

    @Test
    fun audioMetersHideWhenStatusHasNoFields() {
        assertNull(CameraStatus().audioMetersLeftRight())
        assertEquals("—", AudioAssist.displayedSensitivity(null))
        assertEquals("STEREO", AudioAssist.displayedSensitivity("  stereo "))
        val yTop = AudioAssist.y(0.0, 0f, 100f)
        val yFloor = AudioAssist.y(AudioAssist.FLOOR_DB, 0f, 100f)
        assertEquals(0f, yTop, 0.01f)
        assertEquals(100f, yFloor, 0.01f)
    }

    @Test
    fun zebraAndPeakingDefaultsMatchIos() {
        assertEquals(100.0, LiveZebra.HIGHLIGHT_IRE)
        assertEquals(55.0, LiveZebra.MIDTONE_IRE)
        val state = LiveAssistState()
        assertEquals(PeakingColor.RED, state.peakingColor)
        assertEquals(PeakingSense.MED, state.peakingSensitivity)
        assertEquals(2.10, state.peakingSensitivity.ratioThreshold, 1e-12)
        assertEquals(ZebraPaint.WHITE, state.zebraHighlightColor)
        assertEquals(ZebraPaint.AMBER, state.zebraMidtoneColor)
        assertEquals(100.0, state.zebraHighlightIRE)
        assertEquals(55.0, state.zebraMidtoneIRE)
        assertEquals(FalseColorScale.STOPS, state.falseColorScale)
        assertTrue(state.falseColorReference)
        assertEquals(
            listOf("0–4", "5", "10–12", "18%", "55–61", "92–93", "94–95", "96–98", "99–100"),
            FalseColorBands.legendLabels(FalseColorScale.IRE),
        )
        val red = PeakingColor.RED.rgb
        assertEquals(255.0 / 255, red.first, 1e-12)
        assertEquals(72.0 / 255, red.second, 1e-12)
        assertEquals(64.0 / 255, red.third, 1e-12)
    }

    @Test
    fun preferredPopupWidth() {
        assertEquals(472f, AssistLongPress.preferredWidthDp(LiveAssistTool.GUIDES))
        assertEquals(400f, AssistLongPress.preferredWidthDp(LiveAssistTool.PEAK))
        assertEquals(400f, AssistLongPress.preferredWidthDp(LiveAssistTool.LUT))
        assertEquals(250L, AssistLongPress.CHIP_MS)
        assertEquals(300L, AssistLongPress.PANEL_MS)
    }
}
