package com.opencapture.openpocketcine.feed

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PocketScopeSamplerTest {
    @BeforeTest
    fun resetCeiling() {
        ScopeExposureCeiling.reset()
    }

    @Test
    fun tapSizeMatchesIosNearestNeighbour() {
        val (w, h) = PocketScopeSampler.tapSize(1280, 720)
        assertEquals(213, w)
        assertEquals(120, h)
        assertEquals(PocketScopeSampler.MAX_WIDTH, 200)
        assertEquals(PocketScopeSampler.POINT_STRIDE, 2)
        assertEquals(1_000_000_000L / 15, PocketScopeSampler.BASE_MIN_INTERVAL_NS)
        assertEquals(1_000_000_000L / 10, PocketScopeSampler.DENSE_MIN_INTERVAL_NS)
        assertTrue(PocketScopeSampler.minIntervalNs(1) < PocketScopeSampler.minIntervalNs(3))
        assertEquals(3.0, PocketScopeSampler.thermalMultiplier(3))
        assertEquals(5.0, PocketScopeSampler.thermalMultiplier(4))
    }

    @Test
    fun sampleFillsHistogramsAndPoints() {
        val width = 8
        val height = 8
        val bytes = ByteArray(width * height * 4)
        for (i in bytes.indices step 4) {
            bytes[i] = 247.toByte()
            bytes[i + 1] = 16
            bytes[i + 2] = 78
            bytes[i + 3] = 255.toByte()
        }
        val bundle =
            PocketScopeSampler.sample(
                bytes = bytes,
                width = width,
                height = height,
                bytesPerRow = width * 4,
                transfer = MonitorTransfer.DLOG2,
                includePoints = true,
                includeVectorPoints = true,
                iso = 1600,
            )
        val pixels = ((width + 1) / 2) * ((height + 1) / 2)
        assertEquals(pixels, bundle.samples.points.size)
        assertEquals(pixels, bundle.samples.histogramRed.sum())
        assertEquals(pixels, bundle.vectorscopePoints.size)
        assertEquals(pixels, bundle.samples.histogramRed[247])
        assertEquals(pixels, bundle.samples.histogramGreen[16])
        assertEquals(pixels, bundle.samples.histogramBlue[78])
        assertTrue(bundle.histogramDisplay.red.any { it > 0f })
        assertEquals(MonitorTransfer.DLOG2, bundle.transfer)
        assertEquals(1L, bundle.revision)
    }

    @Test
    fun histogramDisplayConservesAfterRemapAndBlur() {
        val samples =
            ScopeSamples(
                histogramLuma = IntArray(256).also { it[16] = 40; it[247] = 10 },
                histogramRed = IntArray(256).also { it[16] = 40; it[247] = 10 },
                histogramGreen = IntArray(256).also { it[16] = 40; it[247] = 10 },
                histogramBlue = IntArray(256).also { it[16] = 40; it[247] = 10 },
                points = emptyList(),
            )
        val remapped = WaveformIre.remapHistogram(samples.histogramRed, MonitorTransfer.DLOG2, 1600)
        assertEquals(50, remapped.sum())
        assertEquals(40, remapped[0])
        assertEquals(10, remapped[255])
        val display =
            PocketScopeSampler.histogramDisplay(
                samples,
                ScopeHistogramDisplay.EMPTY,
                MonitorTransfer.DLOG2,
                1600,
            )
        assertTrue(display.red[0] > 0f)
        assertTrue(display.red[255] > 0f)
        assertTrue(display.red.sum() > 0f)
    }

    @Test
    fun vectorscopeBinsRec709RedLeftAndUp() {
        val bin = VectorscopeRaster.binIndex(191, 0, 0)!!
        assertTrue(bin.first < VectorscopeRaster.BINS / 2)
        assertTrue(bin.second > VectorscopeRaster.BINS / 2)
        val pixels =
            VectorscopeRaster.pixels(
                listOf(ScopePoint(0.0, 0.0, 191, 0, 0, 40)),
                gain = 1.0,
                intensity = 1.0,
            )
        assertTrue(pixels != null && pixels.any { it != 0.toByte() })
    }

    @Test
    fun packedCubeMapReadsRedFastestLattice() {
        val size = 2
        val rgba = ByteArray(size * size * size * 4)
        for (g in 0 until size) {
            for (b in 0 until size) {
                for (r in 0 until size) {
                    val dst = (g * size * size + b * size + r) * 4
                    rgba[dst] = (r * 255).toByte()
                    rgba[dst + 1] = (g * 255).toByte()
                    rgba[dst + 2] = (b * 255).toByte()
                    rgba[dst + 3] = 255.toByte()
                }
            }
        }
        val cube = FeedEffectsCube(size, rgba)
        val mapped = cube.map(1f, 0f, 0f)
        assertEquals(1f, mapped.first, 1e-5f)
        assertEquals(0f, mapped.second, 1e-5f)
        assertEquals(0f, mapped.third, 1e-5f)
    }

    private fun assertEquals(expected: Float, actual: Float, absoluteTolerance: Float) {
        kotlin.test.assertTrue(
            kotlin.math.abs(expected - actual) <= absoluteTolerance,
            "expected $expected but was $actual",
        )
    }
}
