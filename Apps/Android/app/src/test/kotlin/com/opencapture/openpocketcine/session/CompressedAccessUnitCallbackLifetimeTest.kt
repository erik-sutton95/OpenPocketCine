package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CompressedAccessUnitCallbackLifetimeTest {
    @Test
    fun epochChangeAfterAdmissionCheckCannotSeedTheReplacementDecoderWithAnOldIrap() {
        val admission = CompressedAccessUnitAdmission()
        val references = DecoderRandomAccessHold()
        val decoderLock = Any()
        val ownership = DecoderInputOwnership(decoderLock)
        val owner = ownership.claim()
        val current = AtomicLong(0)
        val checked = CountDownLatch(1)
        val resume = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val delivered = mutableListOf<Int>()
        val oldKey = byteArrayOf(0, 0, 0, 1, 0x65, 11)
        val newKey = byteArrayOf(0, 0, 0, 1, 0x65, 22)
        references.onNewDecoder()
        assertTrue(admission.offer(oldKey, 0))
        try {
            val retired = executor.submit {
                admission.drain(
                    0,
                    isCurrent = {
                        // Pin the interleaving after the driver's epoch read
                        // but before its callback. Rebinding retains callbacks.
                        val accepted = current.get() == 0L
                        checked.countDown()
                        check(resume.await(2, TimeUnit.SECONDS))
                        accepted
                    },
                    onDiscontinuity = {
                        ownership.withCurrent(owner, 0, Unit) { references.noteBrokenReferences() }
                    },
                    onAccessUnit = {
                        ownership.withCurrent(owner, 0, Unit) {
                            if (CompressedAccessUnitAdmission.hasRandomAccess(it)) references.onIrapAccepted()
                            delivered += it.last().toInt()
                        }
                    },
                )
            }
            assertTrue(checked.await(2, TimeUnit.SECONDS))
            current.incrementAndGet()
            ownership.advance(owner, 1)
            admission.reset(1)
            synchronized(decoderLock) { references.onNewDecoder() }
            assertTrue(admission.offer(newKey, 1))
            resume.countDown()
            retired.get(2, TimeUnit.SECONDS)

            assertEquals(1, admission.pendingCount, "The proven queue ownership fix remains intact")
            assertTrue(
                references.awaitingIdr,
                "An old callback admitted before retirement cannot establish the replacement decoder's references",
            )
            assertTrue(delivered.isEmpty(), "Replacement picture proof must not come from the retired IRAP")
            admission.drain(
                1,
                isCurrent = { current.get() == 1L },
                onDiscontinuity = {
                    ownership.withCurrent(owner, 1, Unit) { references.noteBrokenReferences() }
                },
                onAccessUnit = {
                    ownership.withCurrent(owner, 1, Unit) {
                        if (CompressedAccessUnitAdmission.hasRandomAccess(it)) references.onIrapAccepted()
                        delivered += it.last().toInt()
                    }
                },
            )
            assertFalse(references.awaitingIdr, "The replacement endpoint can still establish picture")
            assertEquals(listOf(22), delivered)
        } finally {
            resume.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun delayedDiscontinuityCannotInvalidateReplacementReferences() {
        val admission = CompressedAccessUnitAdmission()
        val decoderLock = Any()
        val ownership = DecoderInputOwnership(decoderLock)
        val owner = ownership.claim()
        val references = DecoderRandomAccessHold()
        val checked = CountDownLatch(1)
        val resume = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        assertTrue(admission.noteIncompleteLoss(0))
        try {
            val retired = executor.submit {
                admission.drain(
                    0,
                    isCurrent = {
                        checked.countDown()
                        check(resume.await(2, TimeUnit.SECONDS))
                        true // The driver read its epoch before retirement.
                    },
                    onDiscontinuity = {
                        ownership.withCurrent(owner, 0, Unit) { references.noteBrokenReferences() }
                    },
                    onAccessUnit = { error("Loss-only delivery has no picture") },
                )
            }
            assertTrue(checked.await(2, TimeUnit.SECONDS))
            ownership.advance(owner, 1)
            admission.reset(1)
            ownership.withCurrent(owner, 1, Unit) { references.onIrapAccepted() }
            resume.countDown()
            retired.get(2, TimeUnit.SECONDS)
            assertFalse(references.awaitingIdr, "A retired loss cannot invalidate current references")
        } finally {
            resume.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun retiredOwnerCannotAdvanceOrMutateReplacementAndResetRequiresANewOwner() {
        val ownership = DecoderInputOwnership(Any())
        val retired = ownership.claim()
        ownership.advance(retired, 4)
        val replacement = ownership.claim()
        ownership.advance(retired, 99)
        assertFalse(ownership.withCurrent(retired, 4, false) { true })
        assertTrue(ownership.withCurrent(replacement, 0, false) { true })
        ownership.advance(replacement, 2)
        ownership.advance(replacement, 1)
        assertFalse(ownership.withCurrent(replacement, 1, false) { true })
        assertTrue(ownership.withCurrent(replacement, 2, false) { true })
        ownership.invalidate()
        assertFalse(ownership.withCurrent(replacement, 2, false) { true })
        assertTrue(ownership.withCurrent(ownership.claim(), 0, false) { true })
    }
}
