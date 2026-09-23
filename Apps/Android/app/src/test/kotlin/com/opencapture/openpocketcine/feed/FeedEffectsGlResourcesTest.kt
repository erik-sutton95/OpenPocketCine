package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FeedEffectsGlResourcesTest {
    private val lut = FeedEffectsCube(2, ByteArray(2 * 2 * 2 * 4))
    private val paint = FeedEffectsCube(2, ByteArray(2 * 2 * 2 * 4))
    private val weight = FeedEffectsCube(2, ByteArray(2 * 2 * 2 * 4))

    private fun plan(
        lutCube: FeedEffectsCube? = lut,
        falseColorPaint: FeedEffectsCube? = null,
        falseColorWeight: FeedEffectsCube? = null,
        peaking: Boolean = false,
        zebraHighlightCode: Float = 1f,
        scopeTap: ScopeTapPolicy = ScopeTapPolicy.IDLE,
    ) = FeedEffectsRenderPlan(
        lutCube = lutCube, falseColorPaint = falseColorPaint, falseColorWeight = falseColorWeight,
        peaking = peaking, peakingColor = floatArrayOf(1f, 0f, 0f), peakingRatioThreshold = 2.1f,
        peakingNoiseGate = .001f, zebraHighlightOn = true, zebraHighlightCode = zebraHighlightCode,
        zebraHighlightColor = floatArrayOf(1f, 1f, 1f), zebraMidtoneOn = false, zebraMidtoneCode = .5f,
        zebraMidtoneHalf = .02f, zebraMidtoneColor = floatArrayOf(1f, 1f, 1f), splitComparison = false,
        splitVertical = true, scopeTap = scopeTap,
    )

    @Test fun scopeAndScalarChangesKeepProgramsAndCubes() {
        val base = plan()
        assertTrue(base.sharesGlResources(plan(scopeTap = ScopeTapPolicy(waveform = true, iso = 800))))
        assertTrue(base.sharesGlResources(plan(zebraHighlightCode = .9f)))
    }

    @Test fun cubeOrPeakingChangesRebuild() {
        val base = plan()
        assertFalse(base.sharesGlResources(plan(lutCube = null)))
        assertFalse(base.sharesGlResources(plan(lutCube = FeedEffectsCube(2, ByteArray(32)))))
        assertFalse(base.sharesGlResources(plan(falseColorPaint = paint, falseColorWeight = weight)))
        assertFalse(base.sharesGlResources(plan(peaking = true)))
    }
}
