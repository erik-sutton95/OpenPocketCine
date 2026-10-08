package com.opencapture.openpocketcine.feed

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.media.MonitorLUTCube
import com.opencapture.opencine.runtime.InspectorPreviewFrame
import com.opencapture.opencine.runtime.InspectorPreviewRenderer as SharedPreviewRenderer
import com.opencapture.opencine.runtime.NativeGlBackend
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED input, actual EGL/GPU shaders and pixel reads against the original SDK adapter. */
@RunWith(AndroidJUnit4::class)
class NativeGlBackendPixelParityTest {
    @Test fun productionEffectsMatchOriginalBackendThroughLookChangesAndResize() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val original = SharedPreviewRenderer { OriginalMedia3GlBackend(it) }
        val shared = SharedPreviewRenderer { NativeGlBackend.create(it) }
        val grade = cube { r, g, b -> floatArrayOf(1f - b, r * 0.72f, g) }
        val paint = cube { r, g, b -> floatArrayOf(g, 1f - r, b * 0.25f) }
        val weight = cube { r, _, _ -> floatArrayOf(r, r, r) }
        val plans = listOf(
            "identity" to FeedEffectsRenderPlan.IDENTITY,
            "grade" to plan(lut = grade),
            "zebra" to plan(zebra = true),
            "zebra-uniform-change" to plan(zebra = true, zebraLevel = 0.35f),
            "peaking" to plan(peaking = true),
            "false-color" to plan(paint = paint, weight = weight),
            "combined-vertical-split" to plan(grade, paint, weight, peaking = true, zebra = true, split = true),
            "combined-horizontal-split" to plan(grade, paint, weight, peaking = true, zebra = true, split = true, vertical = false),
            "identity-after-effects" to FeedEffectsRenderPlan.IDENTITY,
        )
        try {
            // Odd sizes, asymmetric rows, and channel-specific edges expose packing/orientation bugs.
            for ((width, height) in listOf(17 to 13, 31 to 9, 7 to 23)) {
                val input = frame(width, height)
                for ((name, look) in plans) {
                    val expected = original.render(context, look, input)
                    val actual = shared.render(context, look, input)
                    try {
                        val expectedPixels = pixels(expected)
                        val actualPixels = pixels(actual)
                        if (name.startsWith("identity")) {
                            assertTrue(expectedPixels.toSet().size > 32, "Original identity produced a flat picture")
                            assertTrue(actualPixels.toSet().size > 32, "Shared identity produced a flat picture")
                        }
                        assertEquals(expected.width, actual.width)
                        assertEquals(expected.height, actual.height)
                        for (i in expectedPixels.indices) {
                            assertEquals(expectedPixels[i], actualPixels[i], "$name ${width}x$height pixel $i")
                        }
                    } finally {
                        expected.recycle()
                        actual.recycle()
                    }
                }
            }
        } finally {
            shared.close()
            original.close()
        }
    }

    private fun pixels(bitmap: Bitmap) = IntArray(bitmap.width * bitmap.height).also {
        bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    }

    private fun frame(width: Int, height: Int) = InspectorPreviewFrame(width, height,
        ByteArray(width * height * 4) { index ->
            val pixel = index / 4
            val x = pixel % width
            val y = pixel / width
            when (index % 4) {
                0 -> (x * 29 + y * 11) % 256
                1 -> if (x % 4 == 0) 255 else (x * 7 + y * 37) % 256
                2 -> if (y % 3 == 0) 0 else (x * 47 + y * 13) % 256
                else -> 255
            }.toByte()
        })

    private fun cube(map: (Float, Float, Float) -> FloatArray): MonitorLUTCube {
        val size = 3
        val rgb = FloatArray(size * size * size * 3)
        for (b in 0 until size) for (g in 0 until size) for (r in 0 until size) {
            val value = map(r / 2f, g / 2f, b / 2f)
            val offset = (r + g * size + b * size * size) * 3
            value.copyInto(rgb, offset)
        }
        return MonitorLUTCube.fromRGB(size, rgb)
    }

    private fun plan(lut: MonitorLUTCube? = null, paint: MonitorLUTCube? = null,
        weight: MonitorLUTCube? = null, peaking: Boolean = false, zebra: Boolean = false,
        zebraLevel: Float = 0.70f, split: Boolean = false, vertical: Boolean = true) = FeedEffectsRenderPlan(
        lutCube = lut, falseColorPaint = paint, falseColorWeight = weight,
        peaking = peaking, peakingColor = floatArrayOf(1f, 0.2f, 0.1f),
        peakingRatioThreshold = 1.2f, peakingNoiseGate = 0.0001f,
        zebraHighlightOn = zebra, zebraHighlightCode = zebraLevel,
        zebraHighlightColor = floatArrayOf(0.2f, 0.8f, 1f),
        zebraMidtoneOn = zebra, zebraMidtoneCode = 0.5f, zebraMidtoneHalf = 0.10f,
        zebraMidtoneColor = floatArrayOf(1f, 0.6f, 0.1f), splitComparison = split, splitVertical = vertical,
    )
}
