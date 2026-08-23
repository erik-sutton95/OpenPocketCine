package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.assists.CrushClipCompensation
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.math.abs
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FeedUpscaleTest {
    @Test
    fun reconstructsOnlyWhenThePanelMagnifies() {
        assertTrue(
            FeedUpscaler.shouldReconstructToDisplay(1280f, 720f, 1920f, 1080f),
        )
        assertTrue(
            !FeedUpscaler.shouldReconstructToDisplay(1280f, 720f, 1080f, 608f),
            "portrait S25 well minifies 720p — cubic would alias",
        )
        assertTrue(!FeedUpscaler.shouldReconstructToDisplay(1280f, 720f, 1280f, 720f))
        assertTrue(!FeedUpscaler.shouldReconstructToDisplay(0f, 720f, 1920f, 1080f))
    }
}

class LiveColorScienceTest {
    private val transfers = MonitorTransfer.entries

    @BeforeTest
    fun resetCeiling() {
        ScopeExposureCeiling.reset()
    }

    @Test
    fun colorModeMapsToMonitorTransfer() {
        assertEquals(MonitorTransfer.REC709, MonitorTransfer.fromColorMode(CameraCommands.COLOR_NORMAL))
        assertEquals(MonitorTransfer.HDR, MonitorTransfer.fromColorMode(CameraCommands.COLOR_HDR))
        assertEquals(MonitorTransfer.DLOG, MonitorTransfer.fromColorMode(CameraCommands.COLOR_DLOG))
        assertEquals(MonitorTransfer.DLOG2, MonitorTransfer.fromColorMode(CameraCommands.COLOR_DLOG2))
        assertEquals(MonitorTransfer.DLOG, MonitorTransfer.fromColorMode(MonitorTransfer.COLOR_DLOG_M))
    }

    @Test
    fun dLog2PaperAnchors() {
        fun e(linear: Double) = LiveColorScience.encode(linear, MonitorTransfer.DLOG2)
        assertEquals(0.062561, e(0.0), 1e-6)
        assertEquals(0.304985337243402, e(0.18), 1e-12)
        assertEquals(1.0, e(475.0), 1e-9)
    }

    @Test
    fun dLogWhitePaperAnchors() {
        fun e(linear: Double) = LiveColorScience.encode(linear, MonitorTransfer.DLOG)
        assertEquals(95.0, e(0.0) * 1023, 0.5)
        assertEquals(408.0, e(0.18) * 1023, 0.5)
        assertEquals(1.0, e(42.0), 1e-5)
    }

    @Test
    fun rec709AndHlgEighteenPercent() {
        assertEquals(0.409, LiveColorScience.encode(0.18, MonitorTransfer.REC709), 1e-3)
        assertEquals(0.0, LiveColorScience.encode(0.0, MonitorTransfer.REC709), 0.0)
        assertEquals(0.75, LiveColorScience.encode(1.0, MonitorTransfer.HDR), 1e-6)
        assertEquals(0.378, LiveColorScience.encode(0.18, MonitorTransfer.HDR), 1e-3)
    }

    @Test
    fun liveTapCeilingUsesMeasuredPreviewMax() {
        assertEquals(247, ScopeExposureCeiling.clipByte(MonitorTransfer.DLOG2, 1600))
        assertEquals(223, ScopeExposureCeiling.clipByte(MonitorTransfer.DLOG, 1600))
        assertEquals(223, ScopeExposureCeiling.clipByte(MonitorTransfer.DLOG, 400))
        assertEquals(255, ScopeExposureCeiling.clipByte(MonitorTransfer.REC709, 1600))
        assertEquals(231, ScopeExposureCeiling.clipByte(MonitorTransfer.DLOG2, 800))
        assertEquals(247, ScopeExposureCeiling.clipByte(MonitorTransfer.DLOG2, 3200))
        assertEquals(
            ScopeDisplayScale.CLIP_LEVEL,
            ScopeDisplayScale.waveformLevel(247.0 / 255, MonitorTransfer.DLOG2, 1600),
            1e-9,
        )
        assertEquals(
            ScopeDisplayScale.CLIP_LEVEL,
            ScopeDisplayScale.waveformLevel(223.0 / 255, MonitorTransfer.DLOG, 1600),
            1e-9,
        )
        assertTrue(
            ScopeDisplayScale.waveformLevel(188.0 / 255, MonitorTransfer.DLOG2, 1600) <
                ScopeDisplayScale.CLIP_LEVEL - 0.05,
        )
        val ignored = ScopeExposureCeiling.observeTapMax(255, MonitorTransfer.DLOG2)
        assertEquals(247, ignored.first)
    }

    @Test
    fun paperBlackAndEighteenPercentOnWave() {
        val black = LiveColorScience.encode(0.0, MonitorTransfer.DLOG2)
        assertEquals(0.0, ScopeDisplayScale.monitorPercent(black, MonitorTransfer.DLOG2, 1600), 1e-9)
        val grey = LiveColorScience.encode(0.18, MonitorTransfer.DLOG2)
        assertEquals(30.50, ScopeDisplayScale.monitorPercent(grey, MonitorTransfer.DLOG2, 1600), 0.5)
        assertEquals(100.0, ScopeDisplayScale.monitorPercent(247.0 / 255, MonitorTransfer.DLOG2, 1600), 0.05)
        val dlogGrey = LiveColorScience.encode(0.18, MonitorTransfer.DLOG)
        assertEquals(39.88, ScopeDisplayScale.monitorPercent(dlogGrey, MonitorTransfer.DLOG, 400), 0.5)
        assertEquals(0.0, WaveformIre.ire(black, MonitorTransfer.DLOG2, 1600), 1e-9)
        assertEquals(30.50, WaveformIre.ire(grey, MonitorTransfer.DLOG2, 1600), 0.5)
        assertEquals(100.0, WaveformIre.ire(247.0 / 255, MonitorTransfer.DLOG2, 1600), 0.05)
    }

    @Test
    fun signalNativeInvertsMonitorPercent() {
        for (transfer in transfers) {
            for (percent in listOf(0.0, 18.0, 55.0, 100.0)) {
                val native = ScopeDisplayScale.signalNative(percent, transfer)
                assertEquals(
                    percent,
                    ScopeDisplayScale.monitorPercent(native, transfer),
                    1e-6,
                    "$transfer $percent",
                )
            }
        }
    }

    @Test
    fun histogramRemapConservesAndAnchors() {
        val bins = IntArray(256)
        bins[5] = 15
        bins[16] = 100
        bins[78] = 50
        bins[247] = 25
        bins[255] = 10
        val out = ScopeDisplayScale.remapHistogram(bins, MonitorTransfer.DLOG2)
        assertEquals(200, out.sum())
        assertTrue(out[12] + out[13] >= 100)
        assertEquals(25, out[242])
        assertEquals(10, out[255])
        assertEquals(15, out.slice(0..11).sum())

        val dlogBins = IntArray(256)
        dlogBins[18] = 15
        dlogBins[24] = 100
        dlogBins[102] = 50
        dlogBins[223] = 25
        dlogBins[255] = 10
        val dlogOut = ScopeDisplayScale.remapHistogram(dlogBins, MonitorTransfer.DLOG)
        assertEquals(200, dlogOut.sum())
        assertEquals(25, dlogOut[242])
        assertEquals(10, dlogOut[255])
    }

    @Test
    fun waveformIreHistogramRemapPinsBlackAndClip() {
        val bins = IntArray(256)
        bins[16] = 100
        bins[78] = 50
        bins[247] = 25
        val out = WaveformIre.remapHistogram(bins, MonitorTransfer.DLOG2)
        assertEquals(175, out.sum())
        assertEquals(100, out[0])
        assertEquals(25, out[255])
        val greyBucket = kotlin.math.round(30.50 / 100.0 * 255).toInt()
        assertEquals(50, out[greyBucket])
    }

    @Test
    fun trafficEdgesFollowTheAnchors() {
        val dlog2 = ScopeAnchors.make(MonitorTransfer.DLOG2, 1600)
        assertEquals(247, dlog2.clipEdgeByte)
        assertTrue(dlog2.clipFloorByte <= 237)
        assertTrue(dlog2.clipFloorByte > 188)
        assertEquals(223, ScopeAnchors.make(MonitorTransfer.DLOG, 1600).clipEdgeByte)
        assertEquals(223, ScopeAnchors.make(MonitorTransfer.DLOG, 400).clipEdgeByte)
    }

    @Test
    fun subBlackNoiseDoesNotCrush() {
        for ((transfer, code) in listOf(MonitorTransfer.DLOG2 to 10, MonitorTransfer.DLOG to 18)) {
            val bins = spike(code)
            val reading = ScopeTrafficLights.reading(bins, bins, bins, transfer)
            assertFalse(reading.anyCrush, transfer.name)
            assertFalse(reading.anyClip, transfer.name)
        }
    }

    @Test
    fun toePileUpCrushes() {
        for (transfer in transfers) {
            val floor = transfer.scopeAnchors(1600).crushFloorByte
            val bins = spike(floor + 1)
            val reading = ScopeTrafficLights.reading(bins, bins, bins, transfer)
            assertTrue(reading.anyCrush, transfer.name)
            assertFalse(reading.anyClip, transfer.name)
        }
    }

    @Test
    fun curveTopClips() {
        for (transfer in transfers) {
            val bins = spike(255)
            val reading = ScopeTrafficLights.reading(bins, bins, bins, transfer)
            assertTrue(reading.anyClip, transfer.name)
            assertFalse(reading.anyCrush, transfer.name)
        }
    }

    @Test
    fun recoverableDLog2HighlightDoesNotClipLights() {
        val bins = spike(188)
        val reading = ScopeTrafficLights.reading(bins, bins, bins, MonitorTransfer.DLOG2)
        assertFalse(reading.anyClip)
        assertFalse(reading.anyCrush)
    }

    @Test
    fun compensationThresholdLightsCrushBand() {
        val bins = IntArray(256)
        bins[16] = 5
        bins[128] = 95
        val strict = ScopeTrafficLights.reading(bins, bins, bins, MonitorTransfer.DLOG2, threshold = 0.10)
        val forgiving =
            ScopeTrafficLights.reading(
                bins,
                bins,
                bins,
                MonitorTransfer.DLOG2,
                threshold = CrushClipCompensation.QUARTER.pixelFractionThreshold,
            )
        assertFalse(strict.red.crush)
        assertTrue(forgiving.red.crush)
        assertFalse(forgiving.red.clip)
    }

    @Test
    fun lumaClipLightsEveryLamp() {
        val mid = spike(128)
        val luma = spike(255)
        val reading =
            ScopeTrafficLights.reading(
                red = mid,
                green = mid,
                blue = mid,
                transfer = MonitorTransfer.DLOG2,
                luma = luma,
            )
        assertTrue(reading.anyClip)
        assertTrue(reading.red.clip)
        assertTrue(reading.green.clip)
        assertTrue(reading.blue.clip)
    }

    @Test
    fun inferredTransferFromTapSignature() {
        assertEquals(
            MonitorTransfer.DLOG2,
            MonitorTransfer.inferred(16, 188, MonitorTransfer.REC709),
        )
        assertEquals(
            MonitorTransfer.DLOG,
            MonitorTransfer.inferred(24, 200, MonitorTransfer.REC709),
        )
        assertEquals(
            MonitorTransfer.DLOG,
            MonitorTransfer.inferred(16, 188, MonitorTransfer.DLOG),
        )
    }

    private fun spike(code: Int, count: Int = 1000): IntArray {
        val bins = IntArray(256)
        bins[code] = count
        return bins
    }

    private fun assertEquals(expected: Double, actual: Double, absoluteTolerance: Double) {
        assertTrue(
            abs(expected - actual) <= absoluteTolerance,
            "expected $expected but was $actual (tol $absoluteTolerance)",
        )
    }
}
