package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InspectorPreviewAdmissionTest {
    @Test fun onlyOwningDomainCapturesAtMostFiveTimesPerSecond() {
        val gate = InspectorPreviewAdmission()
        val owner = Any()
        gate.activate(owner, true)
        assertNull(gate.acquire(owner, false, 0))
        assertNull(gate.acquire(Any(), true, 0))
        val first = assertNotNull(gate.acquire(owner, true, 0))
        assertNull(gate.acquire(owner, true, 500_000_000))
        gate.complete(first)
        assertNull(gate.acquire(owner, true, 199_999_999))
        assertNotNull(gate.acquire(owner, true, 200_000_000))
    }

    @Test fun switchingOrClosingDropsLateResultsWithoutQueuingAnotherJob() {
        val gate = InspectorPreviewAdmission()
        val old = Any(); val next = Any()
        gate.activate(old, false)
        val pending = assertNotNull(gate.acquire(old, false, 0))
        gate.deactivate(old)
        gate.activate(next, true)
        assertFalse(gate.isCurrent(pending))
        assertNull(gate.acquire(next, true, 1_000_000_000))
        gate.complete(pending)
        val current = assertNotNull(gate.acquire(next, true, 1_000_000_000))
        gate.deactivate(old)
        assertTrue(gate.isCurrent(current))
        gate.deactivate(next)
        assertFalse(gate.isCurrent(current))
    }

    @Test fun optionsSourceAndWindowInvalidationRejectsTheOldEpoch() {
        val gate = InspectorPreviewAdmission(); val owner = Any()
        gate.activate(owner, false)
        val pending = assertNotNull(gate.acquire(owner, false, 0))
        gate.invalidate(owner)
        assertFalse(gate.isCurrent(pending))
        assertNull(gate.acquire(owner, false, 900_000_000))
        gate.complete(pending)
        val current = assertNotNull(gate.acquire(owner, false, 900_000_000))
        gate.complete(pending)
        assertNull(gate.acquire(owner, false, 2_000_000_000))
        assertTrue(gate.isCurrent(current))
    }

    @Test fun rapidOptionChangesDoNotResetTheFiveHertzBudget() {
        val gate = InspectorPreviewAdmission(); val owner = Any()
        gate.activate(owner, false)
        val first = assertNotNull(gate.acquire(owner, false, 0))
        gate.complete(first)
        gate.invalidate(owner)
        assertNull(gate.acquire(owner, false, 50_000_000))
        assertNotNull(gate.acquire(owner, false, 200_000_000))
    }

    @Test fun shaderSensitivityAndMidtoneWidthParticipateInPreviewIdentity() {
        fun plan(ratio: Float = 2.1f, noise: Float = .001f, half: Float = .02f) = FeedEffectsRenderPlan(
            lutCube = null, falseColorPaint = null, falseColorWeight = null, peaking = true,
            peakingColor = floatArrayOf(1f,0f,0f), peakingRatioThreshold = ratio, peakingNoiseGate = noise,
            zebraHighlightOn = false, zebraHighlightCode = 1f, zebraHighlightColor = floatArrayOf(1f,1f,1f),
            zebraMidtoneOn = true, zebraMidtoneCode = .5f, zebraMidtoneHalf = half,
            zebraMidtoneColor = floatArrayOf(1f,1f,1f), splitComparison = false, splitVertical = true)
        val baseline = plan().playbackLookKey
        assertNotEquals(baseline, plan(ratio = 1.5f).playbackLookKey)
        assertNotEquals(baseline, plan(noise = .003f).playbackLookKey)
        assertNotEquals(baseline, plan(half = .04f).playbackLookKey)
        assertEquals(baseline, plan().playbackLookKey)
    }

    @Test fun portraitRastersStayInsideTheBudgetAndBottomUpRowsAreNormalized() {
        val portrait = InspectorPreviewFrame.fromTap(ByteArray(200 * 360 * 4), 200, 360, false)
        assertEquals(66, portrait.width)
        assertEquals(120, portrait.height)
        val frame = InspectorPreviewFrame.fromTap(byteArrayOf(1,2,3,4,5,6,7,8), 1, 2, true)
        assertEquals(listOf<Byte>(5,6,7,8,1,2,3,4), frame.rgba.toList())
    }
}
