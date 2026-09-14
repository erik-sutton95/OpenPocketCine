package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CompressedAccessUnitAdmissionTest {
    private val start = byteArrayOf(0, 0, 0, 1)
    private val avcKey =
        start + byteArrayOf(0x67, 0x11) + start + byteArrayOf(0x68, 0x22) + start + byteArrayOf(0x65, 0x33)
    private val hevcParams = start + byteArrayOf(0x40, 1) + start + byteArrayOf(0x42, 1) + start + byteArrayOf(0x44, 1)
    private fun pSlice(n: Int) = start + byteArrayOf(0x41, n.toByte())
    private fun trail(n: Int) = start + byteArrayOf(0x02, n.toByte())

    @Test
    fun allRandomAccessBacklogIsStrictlyBounded() {
        val q = CompressedAccessUnitAdmission()
        repeat(25) { q.offer(avcKey) }
        val delivery = q.takeDelivery()
        assertTrue(delivery.accessUnits.size <= CompressedAccessUnitAdmission.MAX_PENDING)
        assertTrue(delivery.discontinuity)
    }

    @Test
    fun overflowDoesNotDeliverDependantsOfDroppedReference() {
        val q = CompressedAccessUnitAdmission()
        q.offer(avcKey)
        repeat(14) { q.offer(pSlice(it + 1)) }
        val delivery = q.takeDelivery()
        assertTrue(delivery.discontinuity)
        assertEquals(1, delivery.accessUnits.size)
        assertTrue(delivery.accessUnits.single().contentEquals(avcKey))
        q.offer(pSlice(15))
        assertTrue(q.takeDelivery().accessUnits.isEmpty())
        q.offer(avcKey)
        q.offer(pSlice(17))
        val recovered = q.takeDelivery().accessUnits
        assertTrue(recovered.first().contentEquals(avcKey))
        assertTrue(recovered.size in 1..2)
    }

    @Test
    fun incompleteLossRejectsDependentFramesUntilIrap() {
        val q = CompressedAccessUnitAdmission()
        q.offer(avcKey)
        q.offer(pSlice(1))
        q.noteIncompleteLoss()
        val cleared = q.takeDelivery()
        assertTrue(cleared.discontinuity)
        assertTrue(cleared.accessUnits.isEmpty())
        q.offer(pSlice(2))
        assertTrue(q.takeDelivery().accessUnits.isEmpty())
        q.offer(avcKey)
        q.offer(pSlice(3))
        val next = q.takeDelivery().accessUnits
        assertTrue(next.first().contentEquals(avcKey))
        assertTrue(next.size in 1..2)
    }

    @Test
    fun pocketParameterSetsSurviveOverload() {
        val q = CompressedAccessUnitAdmission()
        q.offer(hevcParams)
        repeat(11) { q.offer(trail(it + 1)) }
        val pending = q.takeDelivery().accessUnits
        assertTrue(pending.size <= CompressedAccessUnitAdmission.MAX_PENDING)
        assertTrue(pending.any { it.contentEquals(hevcParams) })
    }

    @Test
    fun memoryCapDropsDependantsEvenWhenCountIsUnderEight() {
        val q = CompressedAccessUnitAdmission(maxPending = 8, maxBytes = 50)
        val hugeKey = start + byteArrayOf(0x67, 0x11) + ByteArray(36) { 1 } +
            start + byteArrayOf(0x65, 0x33)
        q.offer(hugeKey)
        q.offer(pSlice(1))
        q.offer(pSlice(2))
        val delivery = q.takeDelivery()
        assertTrue(delivery.discontinuity)
        assertEquals(1, delivery.accessUnits.size)
        assertTrue(delivery.accessUnits.single().contentEquals(hugeKey))
    }

    @Test
    fun oversizedIrapCannotBypassByteCapAndNextValidIrapRecovers() {
        val q = CompressedAccessUnitAdmission(maxBytes = 50)
        q.offer(start + byteArrayOf(0x65, 0x11) + ByteArray(100))
        val oversized = q.takeDelivery()
        assertTrue(oversized.discontinuity)
        assertTrue(oversized.accessUnits.isEmpty())
        assertTrue(q.queuedBytes <= 50)
        q.offer(avcKey)
        q.offer(pSlice(1))
        assertEquals(2, q.takeDelivery().accessUnits.size)
    }

    @Test
    fun pendingCountNeverExceedsCap() {
        val q = CompressedAccessUnitAdmission()
        q.offer(avcKey)
        repeat(40) { q.offer(pSlice(it)) }
        assertTrue(q.pendingCount <= CompressedAccessUnitAdmission.MAX_PENDING)
        assertTrue(q.queuedBytes <= CompressedAccessUnitAdmission.MAX_BYTES)
    }

    @Test
    fun hopIsSingleFlightUntilDrainOrRelease() {
        val q = CompressedAccessUnitAdmission()
        assertTrue(q.offer(avcKey))
        assertFalse(q.offer(avcKey))
        q.takeDelivery()
        assertTrue(q.offer(avcKey))
        q.releaseScheduledHop()
        assertTrue(q.offer(avcKey))
    }
}
