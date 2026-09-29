package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScopeGeometryTest {
    /** Swift `falseColorClip(.limits)` + `falseColorBands(.limits)` clip edge, probed 2026-09-29. */
    @Test
    fun limitsKeyClipsOnTheSwiftShelfForLogAnd709() {
        val swift =
            mapOf(
                (MonitorTransfer.DLOG2 to false) to 97.1251,
                (MonitorTransfer.DLOG2 to true) to 97.2549,
                (MonitorTransfer.DLOG to false) to 96.5308,
                (MonitorTransfer.DLOG to true) to 97.2549,
                (MonitorTransfer.DLOGM to false) to 97.2549,
                (MonitorTransfer.REC709 to false) to 97.2549,
            )
        for ((key, edge) in swift) {
            val (transfer, rec709) = key
            val clip = FalseColorBands.bands(FalseColorScale.LIMITS, transfer, rec709)[3]
            assertEquals(edge, clip.lowerBound, 0.01, "$transfer rec709=$rec709")
        }
    }

    @Test
    fun waveformPlotGuttersDoNotScaleWithPanelSoIre100StaysOnTheGuide() {
        val d = 3f
        val scale = 1.6f
        val base = ScopePanelSize.waveform
        val live =
            WaveformAxis.plotRect(base.width * scale * d, base.height * scale * d, d)
        assertEquals(WaveformAxis.TITLE_HEIGHT * d, live.minY, 0.01f)
        assertEquals(WaveformAxis.SIDE_PAD * d, live.minX, 0.01f)
        val y100 = WaveformAxis.plotY(100.0, live, d)
        assertEquals(live.minY + WaveformAxis.PLOT_INSET * d, y100, 0.01f)
        val baked = ScopeTraceRaster.wavePlot
        val stretchedY100 = (baked.minY + WaveformAxis.PLOT_INSET) * scale * d
        assertTrue(
            kotlin.math.abs(stretchedY100 - y100) > 20f,
            "full-panel stretch would put IRE 100 at $stretchedY100, guides at $y100",
        )
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
        assertEquals(0.25, WaveformAssist.intensity(100), 1e-9)
        assertEquals(0.0, WaveformAssist.intensity(0), 1e-9)
        assertEquals(0.5, WaveformAssist.intensity(200), 1e-9)
        assertEquals(1.0, ParadeAssist.intensity(100), 1e-9)
        assertEquals(2.0, ParadeAssist.intensity(200), 1e-9)
        assertEquals(1.0, VectorscopeAssist.intensity(100), 1e-9)
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
    fun paradeLanesSplitThePlot() {
        assertEquals(3, ParadeMode.RGB.laneCount)
        assertEquals(4, ParadeMode.YRGB.laneCount)
        val plot = WaveformAxis.plotRect(250f, 153f)
        val w = ParadeAssist.laneWidth(ParadeMode.RGB, plot)
        assertEquals(plot.width / 3f, w, 0.01f)
    }

    @Test
    fun plotGuttersScaleWithDensityLikeIosPoints() {
        val d = 2.75f
        val size = ScopePanelSize.histogram
        val at1 = HistogramAssist.plotRect(size.width, size.height)
        val atD = HistogramAssist.plotRect(size.width * d, size.height * d, d)
        assertEquals(at1.minX * d, atD.minX, 0.02f)
        assertEquals(at1.minY * d, atD.minY, 0.02f)
        assertEquals(at1.width * d, atD.width, 0.02f)
        assertEquals(HistogramAssist.trafficGutter * d, atD.minX, 0.02f)
        assertEquals(WaveformAxis.TITLE_HEIGHT * d, atD.minY, 0.02f)
        val wave = WaveformAxis.plotRect(250f * d, 153f * d, d)
        assertEquals(WaveformAxis.SIDE_PAD * d, wave.minX, 0.02f)
        assertEquals(WaveformAxis.TITLE_HEIGHT * d, wave.minY, 0.02f)
    }

    @Test
    fun traceRasterSkipsEmptyPointLists() {
        val table = FloatArray(256)
        assertEquals(null, ScopeTraceRaster.waveformArgb(emptyList(), emptyList(), table, WaveformMode.RGB, 1.0))
        assertEquals(null, ScopeTraceRaster.paradeArgb(emptyList(), emptyList(), table, ParadeMode.RGB, 1.0))
    }

    @Test
    fun waveformRasterIsPlotSizedAndTransparentWhereEmpty() {
        val table = FloatArray(256) { it * 100f / 255f }
        val mid = com.opencapture.openpocketcine.feed.ScopePoint(0.5, 0.5, 128, 128, 128, 128)
        val px =
            ScopeTraceRaster.waveformArgb(
                listOf(mid),
                emptyList(),
                table,
                WaveformMode.LUMA,
                WaveformAssist.intensity(100),
            )
        requireNotNull(px)
        assertEquals(ScopeTraceRaster.wavePlotW * ScopeTraceRaster.wavePlotH, px.size)
        assertEquals(0, px[0] ushr 24)
        assertTrue(px.any { ((it shr 16) and 0xFF) > 20 })
    }

    @Test
    fun retainedTraceReusesThePreviousLiveLayerAsTheTrail() {
        val table = FloatArray(256) { it * 100f / 255f }
        fun frame(seed: Int) = List(400) { i ->
            val v = (i * 37 + seed * 11) % 256
            com.opencapture.openpocketcine.feed.ScopePoint((i % 200) / 200.0, 0.5, v, 255 - v, (v * 3) % 256, v)
        }
        val a = frame(1)
        val b = frame(2)
        val c = frame(3)
        val intensity = WaveformAssist.intensity(100)
        val layers = ScopeTraceRaster.TraceLayers()
        for (mode in WaveformMode.entries) {
            layers.waveformArgb(a, emptyList(), table, mode, intensity)
            // b's trail is a's samples: the retained live layer stands in for a re-splat.
            val reused = requireNotNull(layers.waveformArgb(b, a, table, mode, intensity)).copyOf()
            val fresh = requireNotNull(ScopeTraceRaster.waveformArgb(b, a, table, mode, intensity))
            assertTrue(reused.indices.all { channelsWithin(reused[it], fresh[it], 1) }, "$mode reuse matches a fresh build")
            // A trail that is not the previous samples is splatted, not reused.
            val skipped = requireNotNull(layers.waveformArgb(c, a, table, mode, intensity)).copyOf()
            val skippedFresh = requireNotNull(ScopeTraceRaster.waveformArgb(c, a, table, mode, intensity))
            assertTrue(skipped.indices.all { channelsWithin(skipped[it], skippedFresh[it], 1) }, "$mode fallback matches")
        }
        layers.paradeArgb(a, emptyList(), table, ParadeMode.RGB, intensity)
        val parade = requireNotNull(layers.paradeArgb(b, a, table, ParadeMode.RGB, intensity)).copyOf()
        val paradeFresh = requireNotNull(ScopeTraceRaster.paradeArgb(b, a, table, ParadeMode.RGB, intensity))
        assertTrue(parade.indices.all { channelsWithin(parade[it], paradeFresh[it], 1) })
    }

    private fun channelsWithin(x: Int, y: Int, tolerance: Int) =
        (0 until 32 step 8).all { kotlin.math.abs(((x ushr it) and 0xFF) - ((y ushr it) and 0xFF)) <= tolerance }

    @Test
    fun vectorscopeRasterIsPlotSizedAndTransparentWhereEmpty() {
        val white = com.opencapture.openpocketcine.feed.ScopePoint(0.5, 0.5, 255, 255, 255, 255)
        val px =
            ScopeTraceRaster.vectorscopeArgb(
                listOf(white),
                emptyList(),
                1.0,
                1.0,
            )
        requireNotNull(px)
        assertEquals(ScopeTraceRaster.vectorPlotW * ScopeTraceRaster.vectorPlotH, px.size)
        assertEquals(0, px[0] ushr 24)
        assertTrue(px.any { ((it shr 16) and 0xFF) > 20 })
    }

    @Test
    fun movablePanelClampSnapAndStoredCenter() {
        assertEquals(0.6, MovablePanelMath.clampedScale(0.2), 1e-9)
        assertEquals(1.6, MovablePanelMath.clampedScale(3.0), 1e-9)
        val size = MovablePanelMath.panelSize(ScopePanelSize.vectorscope, 2.0)
        assertEquals(304f, size.width)
        assertEquals(304f, size.height)
        val snapped = MovablePanelMath.snap(AssistPoint(11f, 23f))
        assertEquals(12f, snapped.x, 0.01f)
        assertEquals(24f, snapped.y, 0.01f)

        val bounds = AssistRect(0f, 0f, 800f, 400f)
        val feed = AssistRect(40f, 20f, 720f, 360f)
        val offFeed = MovablePanelMath.clamp(AssistPoint(30f, 200f), AssistSize(40f, 40f), bounds)
        assertEquals(30f, offFeed.x, 0.01f)
        assertTrue(offFeed.x < feed.minX)
        val stored = StoredCenter(AssistPoint(750f, 125f), AssistRect(0f, 0f, 1000f, 500f))
        assertEquals(0.75, stored.xFraction, 0.001)
        assertEquals(0.25, stored.yFraction, 0.001)
    }

    @Test
    fun unplacedWindowedScopeStartsAtCanvasCenterThenClampsToMovement() {
        val canvas = AssistRect(0f, 0f, 874f, 402f)
        val movement = AssistRect(8f, 8f, 858f, 386f)
        val size = ScopePanelSize.histogram
        val fallback = AssistPoint(canvas.midX, canvas.midY)
        val raw = MovablePanelMath.resolvedCenter(null, null, fallback, size, canvas)
        assertEquals(canvas.midX, raw.x, 0.05f)
        assertEquals(canvas.midY, raw.y, 0.05f)
        val fitted = MovablePanelMath.clampWithGrip(raw, size, movement, MovablePanelMath.GRIP_EXTERIOR_DP)
        assertEquals(canvas.midX, fitted.x, 0.05f)
        assertEquals(canvas.midY, fitted.y, 0.05f)
        assertTrue(fitted.y + size.height / 2f <= movement.maxY + 0.05f)
    }

    @Test
    fun audioFreshMeterStartsAtLeftAndCanvasVerticalCenter() {
        val canvas = AssistRect(40f, 20f, 844f, 390f)
        val movement = AssistRect(54f, 70f, 812f, 268f)
        val size = ScopePanelSize.audio
        val center = AudioAssist.defaultCenter(canvas, movement, size)
        assertEquals(movement.minX + size.width / 2f, center.x, 0.05f)
        assertEquals(canvas.midY, center.y, 0.05f)
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
    fun audioMetersHideWhenStatusHasNoFields() {
        assertNull(CameraStatus().audioMetersLeftRight())
        val silent = audioOverlayChannels(CameraStatus())
        assertEquals(AudioAssist.FLOOR_DB, silent.first.levelDB, 0.01)
        assertEquals(AudioAssist.FLOOR_DB, silent.second.levelDB, 0.01)
        val live = audioOverlayChannels(CameraStatus(audioMetersLeft = -21.0, audioMetersRight = -14.0))
        assertEquals(-21.0, live.first.levelDB, 0.01)
        assertEquals(-14.0, live.second.levelDB, 0.01)
    }

    @Test
    fun zebraNativeUnitShows0To255NotIre() {
        val transfer = MonitorTransfer.DLOG2
        assertEquals(100, ZebraEditor.displayValue(100.0, ZebraUnit.IRE, transfer))
        assertEquals(100, ZebraEditor.editorMaximum(ZebraUnit.IRE))
        assertEquals(255, ZebraEditor.editorMaximum(ZebraUnit.NATIVE))
        val nativeClip = ZebraEditor.displayValue(100.0, ZebraUnit.NATIVE, transfer)
        assertTrue(nativeClip in 240..255, "D-Log2 clip maps near code 247, was $nativeClip")
        assertEquals(
            100.0,
            ZebraEditor.ireFromDisplay(nativeClip, ZebraUnit.NATIVE, transfer),
            0.5,
        )
    }

    @Test
    fun falseColorVideoRulerUsesVideoModeIre() {
        assertEquals(FalseColorScale.STOPS, FalseColorScale.fromMenuLabel("Video"))
        assertEquals(FalseColorScale.STOPS, FalseColorScale.fromPersisted("PStops"))
        assertEquals(FalseColorScale.STOPS, FalseColorScale.fromPersisted("ZC Stops"))
        assertEquals("Video", FalseColorScale.STOPS.menuLabel)
        val transfer = MonitorTransfer.DLOG2
        val stops = FalseColorReference.segments(FalseColorScale.STOPS, transfer)
        assertEquals(9, stops.size)
        assertEquals(0.0, stops[0].lowerFraction, 1e-4)
        assertEquals(0.05, stops[0].upperFraction, 1e-4)
        assertEquals(0.41, stops[3].lowerFraction, 1e-4)
        assertEquals(0.49, stops[3].upperFraction, 1e-4)
        assertEquals(1.0, stops.last().upperFraction, 1e-9)
        assertTrue(stops[2].upperFraction < stops[3].lowerFraction)
        assertEquals(
            listOf("crush", "18%", "skin", "clip"),
            FalseColorReference.axisLabels(FalseColorScale.STOPS),
        )
        assertEquals("D-Log2", FalseColorReference.curveKeyLabel(CameraCommands.COLOR_DLOG2))
        val ire = FalseColorReference.segments(FalseColorScale.IRE, transfer)
        assertEquals(6, ire.size)
        assertEquals(0.0, ire[0].lowerFraction, 1e-4)
        assertEquals(0.025, ire[0].upperFraction, 1e-4)
        assertEquals(0.38, ire[2].lowerFraction, 1e-4)
        assertEquals(0.42, ire[2].upperFraction, 1e-4)
        assertEquals(0.80, ire[4].lowerFraction, 1e-4)
        assertEquals(0.95, ire[4].upperFraction, 1e-4)
        assertEquals(1.0, ire.last().upperFraction, 1e-9)
        assertTrue(ire[1].upperFraction < ire[2].lowerFraction)
    }

    @Test
    fun unknownSavedScaleFallsBackToCineStop() {
        assertEquals(FalseColorScale.SCENE_STOPS, FalseColorScale.fromPersisted("unknown"))
        assertEquals(FalseColorScale.SCENE_STOPS, FalseColorScale.fromMenuLabel("unknown"))
    }

    @Test
    fun savedCineStopKeyKeepsTheVideoScale() {
        // "CineStop" was the Video scale's saved key before the scene-stop scale took the name.
        assertEquals(FalseColorScale.STOPS, FalseColorScale.fromPersisted("CineStop"))
        assertEquals(FalseColorScale.SCENE_STOPS, FalseColorScale.fromPersisted("SceneStops"))
        assertEquals(FalseColorScale.SCENE_STOPS, FalseColorScale.fromMenuLabel("CineStop"))
        assertEquals("CineStop", FalseColorScale.SCENE_STOPS.menuLabel)
    }

    @Test
    fun cineStopMatchesCoreZonesAndFollowsTheCeiling() {
        val bands = FalseColorBands.sceneStopBands()
        assertEquals(
            listOf("crush", "shadows", "−2", "−1", "18%", "+1", "+2", "highlights", "clip"),
            bands.map { it.label },
        )
        fun label(stops: Double) = bands.firstOrNull { it.contains(stops) }?.label
        assertEquals("crush", label(Double.NEGATIVE_INFINITY))
        assertEquals("−2", label(-2.0))
        assertEquals("18%", label(0.0))
        assertEquals("+1", label(1.0))
        assertEquals("+2", label(2.0))
        assertEquals("shadows", label(-6.0))
        assertEquals("highlights", label(10.0))
        assertEquals("clip", label(10.6))
        listOf(-5.0, -3.0).forEach { assertEquals("shadows", label(it)) }
        listOf(3.0, 5.0, 9.4).forEach { assertEquals("highlights", label(it)) }
        val gray = bands.first { it.label == "18%" }
        assertEquals(gray.red, gray.green, 0.0)
        assertEquals(gray.green, gray.blue, 0.0)

        val rec709 = FalseColorBands.sceneStopBands(FalseColorBands.clipStops(MonitorTransfer.REC709))
        assertEquals("+2", rec709.first { it.contains(2.0) }.label)
        assertEquals("clip", rec709.last().label)

        assertEquals(
            listOf("−6", "−4", "−2", "18%", "+2", "+4", "+6", "+8", "clip"),
            FalseColorReference.sceneStopMarkers(MonitorTransfer.DLOG2).map { it.label },
        )
        assertEquals(
            listOf("−6", "−4", "−2", "18%", "clip"),
            FalseColorReference.sceneStopMarkers(MonitorTransfer.REC709).map { it.label },
        )
        assertTrue(FalseColorReference.axisLabels(FalseColorScale.SCENE_STOPS).isEmpty())
    }
}
