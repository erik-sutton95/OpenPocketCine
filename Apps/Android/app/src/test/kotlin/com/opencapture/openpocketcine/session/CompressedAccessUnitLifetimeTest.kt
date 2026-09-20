package com.opencapture.openpocketcine.session

import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CompressedAccessUnitLifetimeTest {
    private fun key(id: Int) = byteArrayOf(0, 0, 0, 1, 0x65, id.toByte())
    private fun dependent(id: Int) = byteArrayOf(0, 0, 0, 1, 0x41, id.toByte())

    @Test
    fun retiredQueuedDrainCannotConsumeReplacementFirstPictureOrDiscontinuity() {
        val admission = CompressedAccessUnitAdmission()
        val tasks = ArrayDeque<() -> Unit>()
        val delivered = mutableListOf<Int>()
        var discontinuities = 0
        var current = 0L
        fun schedule(epoch: Long) {
            tasks.addLast {
                admission.drain(epoch, { epoch == current }, { discontinuities += 1 }) {
                    delivered += it.last().toInt()
                }
            }
        }
        assertTrue(admission.offer(key(11), current))
        schedule(current)
        current += 1
        admission.reset(current)
        assertTrue(admission.noteIncompleteLoss(current))
        assertFalse(admission.offer(key(22), current))
        schedule(current)

        tasks.removeFirst().invoke() // Old decode-executor task runs first.
        assertEquals(1, admission.pendingCount, "retired drain must leave the new keyframe queued")
        assertEquals(0, discontinuities)
        tasks.removeFirst().invoke()
        assertEquals(listOf(22), delivered)
        assertEquals(1, discontinuities, "the current owner must receive its discontinuity")
    }

    @Test
    fun retiredRejectedTaskCannotReleaseReplacementScheduledHop() {
        val admission = CompressedAccessUnitAdmission()
        assertTrue(admission.offer(key(11), 0))
        admission.reset(1)
        assertTrue(admission.offer(key(22), 1))
        admission.releaseScheduledHop(0)
        assertFalse(admission.offer(dependent(23), 1), "replacement still owns its queued drain")
        assertEquals(listOf(22, 23), admission.takeDelivery(1).accessUnits.map { it.last().toInt() })
        admission.releaseScheduledHop(1)
        assertTrue(admission.offer(key(24), 1), "current rejection may release its own slot")
    }

    @Test
    fun retiredReceiveCannotClearOrAppendToReplacementQueue() {
        val admission = CompressedAccessUnitAdmission()
        admission.reset(1)
        assertTrue(admission.offer(key(22), 1))
        assertFalse(admission.noteIncompleteLoss(0))
        assertFalse(admission.offer(key(11), 0))
        assertFalse(admission.offer(dependent(23), 1))
        val delivery = admission.takeDelivery(1)
        assertFalse(delivery.discontinuity)
        assertEquals(listOf(22, 23), delivery.accessUnits.map { it.last().toInt() })
    }

    @Test
    fun lateRetirementCannotRewindOrClearNewerEndpoint() {
        val admission = CompressedAccessUnitAdmission()
        admission.reset(2)
        assertTrue(admission.offer(key(22), 2))
        admission.reset(1) // A preceding close fence resumes after TX retirement.
        assertEquals(listOf(22), admission.takeDelivery(2).accessUnits.map { it.last().toInt() })
        assertFalse(admission.offer(key(11), 1))
    }

    @Test
    fun retainedOldKeyframeCannotClearOutstandingReferenceLoss() {
        val admission = CompressedAccessUnitAdmission()
        val references = DecoderRandomAccessHold()
        references.onNewDecoder()
        admission.offer(key(11))
        repeat(10) { admission.offer(dependent(it)) }
        val painted = mutableListOf<Int>()
        admission.drain(0, { true }, references::noteBrokenReferences) {
            if (CompressedAccessUnitAdmission.hasRandomAccess(it)) references.onIrapAccepted()
            painted += it.last().toInt()
        }
        assertEquals(listOf(11), painted, "the retained image may still paint")
        assertTrue(references.awaitingIdr, "old IRAP cannot clear the queue's demand for a new IRAP")
        assertFalse(references.hasDecodableReferences)
        admission.offer(dependent(12))
        assertTrue(admission.takeDelivery().accessUnits.isEmpty())
        admission.offer(key(22))
        admission.drain(0, { true }, references::noteBrokenReferences) {
            if (CompressedAccessUnitAdmission.hasRandomAccess(it)) references.onIrapAccepted()
        }
        assertFalse(references.awaitingIdr)
    }

    @Test
    fun recoverableKeyframeSuffixClearsLossBeforeDeliveringItsReferences() {
        val admission = CompressedAccessUnitAdmission(maxPending = 2)
        val references = DecoderRandomAccessHold()
        references.onNewDecoder()
        admission.offer(key(11))
        admission.offer(dependent(12))
        admission.offer(key(22))
        admission.offer(dependent(23))
        val delivered = mutableListOf<Int>()
        admission.drain(0, { true }, references::noteBrokenReferences) {
            val irap = CompressedAccessUnitAdmission.hasRandomAccess(it)
            if (references.shouldAccept(irap)) {
                if (irap) references.onIrapAccepted()
                delivered += it.last().toInt()
            }
        }
        assertEquals(listOf(22, 23), delivered)
        assertFalse(references.awaitingIdr)
    }

    @Test
    fun replacementDuringDeliveryStopsOldBatchWithoutHoldingQueueLock() {
        val admission = CompressedAccessUnitAdmission()
        admission.offer(key(11), 0)
        admission.offer(dependent(12), 0)
        var current = 0L
        val delivered = mutableListOf<Int>()
        val retirement = Executors.newSingleThreadExecutor()
        try {
            admission.drain(0, { current == 0L }, {}) {
                delivered += it.last().toInt()
                current = 1
                retirement.submit {
                    admission.reset(1)
                    admission.offer(key(22), 1)
                }.get(1, TimeUnit.SECONDS)
            }
        } finally {
            retirement.shutdownNow()
        }
        admission.drain(1, { current == 1L }, {}) { delivered += it.last().toInt() }
        assertEquals(listOf(11, 22), delivered)
    }
}
