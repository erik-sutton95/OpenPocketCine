package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class KnownReferenceLossTest {
    @Test
    fun canceledRepairWaitingForCodecLockCannotMutateANewInputLifetime() {
        for (referenceLossOnly in listOf(true, false)) {
            for (retirement in 0..2) {
                val lock = Any()
                val decoder = HevcDecoder(lock = lock)
                val owner = decoder.claimInputOwner()
                decoder.randomAccess.onIrapAccepted()
                decoder.noteReferenceDiscontinuity()
                val input = decoder.captureInputOwnership()
                val entered = CountDownLatch(1)
                val result = AtomicReference<Boolean?>()
                val worker = Thread {
                    entered.countDown()
                    result.set(decoder.rebuildPresentationIfNeeded(referenceLossOnly, input))
                }
                var generation = -1
                try {
                    synchronized(lock) {
                        worker.start()
                        assertTrue(entered.await(2, TimeUnit.SECONDS))
                        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
                        while (worker.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.sleep(1)
                        assertEquals(Thread.State.BLOCKED, worker.state, "Old repair is waiting inside codec admission")
                        // Cancellation alone cannot interrupt Java monitor entry.
                        worker.interrupt()
                        when (retirement) {
                            0 -> decoder.advanceInputEpoch(owner, input.epoch + 1)
                            1 -> decoder.claimInputOwner()
                            else -> decoder.reset()
                        }
                        decoder.randomAccess.onIrapAccepted()
                        decoder.noteReferenceDiscontinuity()
                        generation = decoder.randomAccess.generation
                    }
                    worker.join(2_000)
                    assertFalse(worker.isAlive, "Guarded mutation must finish after the codec lock releases")
                    assertEquals(false, result.get())
                    assertEquals(generation, decoder.randomAccess.generation, "Retired repair cannot replace the new codec")
                    assertTrue(decoder.referenceRecoveryNeeded, "Current loss belongs to the new owner")
                    assertTrue(decoder.rebuildPresentationIfNeeded(referenceLossOnly, decoder.captureInputOwnership()))
                } finally {
                    worker.interrupt()
                    worker.join(2_000)
                    decoder.reset()
                }
            }
        }
    }

    @Test
    fun freshIrapBetweenWatchdogDecisionAndRepairDoesNotRebuildTheCodec() {
        val decoder = HevcDecoder()
        decoder.randomAccess.onIrapAccepted()
        val admission = CompressedAccessUnitAdmission()
        admission.noteIncompleteLoss()
        admission.offer(byteArrayOf(0, 0, 0, 1, 0x65, 1))
        val state = LiveViewEnablePolicy.State()
        val before = state.capture()
        var requests = 0
        admission.drain(0, { true }, {
            decoder.noteReferenceDiscontinuity()
            // Exact interleaving: watchdog runs after loss but before the
            // fresh suffix's IRAP. Its scheduled owner has not executed yet.
            assertEquals(LiveViewEnablePolicy.Action.REBUILD_DECODER,
                LiveViewEnablePolicy.tick(state, snapshot().copy(referenceRecoveryNeeded = decoder.referenceRecoveryNeeded)))
            requests += 1
        }, { decoder.randomAccess.onIrapAccepted() })
        assertEquals(1, requests)
        val generation = decoder.randomAccess.generation
        assertFalse(decoder.rebuildPresentationIfNeeded(referenceLossOnly = true, input = decoder.captureInputOwnership()))
        assertEquals(generation, decoder.randomAccess.generation)
        assertTrue(decoder.hasDecodableReferences)
        state.restore(before)
        assertEquals(LiveViewEnablePolicy.Stage.IDLE, state.stage)
        // A later real loss still gets the same one bounded owner; ordinary
        // silence repairs remain eligible even without a discontinuity flag.
        decoder.noteReferenceDiscontinuity()
        assertTrue(decoder.rebuildPresentationIfNeeded(referenceLossOnly = true, input = decoder.captureInputOwnership()))
        assertTrue(decoder.referenceRecoveryNeeded)
        decoder.randomAccess.onIrapAccepted()
        assertTrue(decoder.rebuildPresentationIfNeeded(referenceLossOnly = false, input = decoder.captureInputOwnership()))
    }

    @Test
    fun incompleteAccessUnitAfterGoodReferencesRequestsOneEarlyRepair() {
        val admission = CompressedAccessUnitAdmission()
        val hold = DecoderRandomAccessHold()
        hold.onNewDecoder()
        hold.onIrapAccepted()
        assertTrue(admission.noteIncompleteLoss())
        admission.drain(0, { true }, { hold.noteBrokenReferences() }, { error("Loss has no AU") })
        assertTrue(hold.referenceRecoveryNeeded)
        val state = LiveViewEnablePolicy.State()
        assertEquals(LiveViewEnablePolicy.Action.REBUILD_DECODER,
            LiveViewEnablePolicy.tick(state, snapshot().copy(referenceRecoveryNeeded = hold.referenceRecoveryNeeded)))
        for (elapsed in listOf(100L, 1_000, 2_000, 8_000, 15_999)) {
            assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snapshot(elapsed)))
            assertEquals(100_000, state.lastActionAt)
        }
        assertEquals(LiveViewEnablePolicy.Action.FULL_REJOIN, LiveViewEnablePolicy.tick(state, snapshot(16_000)))
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snapshot(17_000)))
    }

    @Test
    fun acceptedIrapBeforeOutputCannotReleaseTheEarlyRepairBudget() {
        val state = LiveViewEnablePolicy.State()
        assertEquals(LiveViewEnablePolicy.Action.REBUILD_DECODER, LiveViewEnablePolicy.tick(state, snapshot()))
        for (elapsed in listOf(100L, 500, 1_000)) {
            assertEquals(LiveViewEnablePolicy.Action.NONE,
                LiveViewEnablePolicy.tick(state, snapshot(elapsed).copy(referenceRecoveryNeeded = false)))
            assertEquals(LiveViewEnablePolicy.Stage.REBUILD_DECODER, state.stage)
        }
        val output = snapshot(1_100).copy(lastDecoderOutputAt = 101_090)
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, output))
        assertEquals(LiveViewEnablePolicy.Stage.REBUILD_DECODER, state.stage)
        assertEquals(LiveViewEnablePolicy.Action.NONE,
            LiveViewEnablePolicy.tick(state, output.copy(referenceRecoveryNeeded = false)))
        assertEquals(LiveViewEnablePolicy.Stage.IDLE, state.stage)
    }

    @Test
    fun coldDecoderIntentionalHoldAndResetDoNotInventReferenceLoss() {
        val hold = DecoderRandomAccessHold()
        hold.onNewDecoder()
        hold.noteBrokenReferences()
        assertFalse(hold.referenceRecoveryNeeded, "There were no good references to lose at startup")
        hold.onIrapAccepted()
        hold.beginHold()
        assertFalse(hold.referenceRecoveryNeeded)
        hold.onNewDecoder()
        assertFalse(hold.referenceRecoveryNeeded, "Intentional replacement is already owned")
        hold.onIrapAccepted()
        hold.noteBrokenReferences()
        assertTrue(hold.referenceRecoveryNeeded)
        hold.onNewDecoder()
        assertTrue(hold.referenceRecoveryNeeded, "Repair must retain its loss until a current IRAP")
        hold.onIrapAccepted()
        assertFalse(hold.referenceRecoveryNeeded)
        hold.noteBrokenReferences()
        hold.reset()
        assertFalse(hold.referenceRecoveryNeeded)
    }

    @Test
    fun retiredInputCannotArmOrClearTheCurrentReferenceLoss() {
        val ownership = DecoderInputOwnership(Any())
        val owner = ownership.claim()
        val hold = DecoderRandomAccessHold()
        hold.onIrapAccepted()
        ownership.advance(owner, 1)
        ownership.withCurrent(owner, 0, Unit) { hold.noteBrokenReferences() }
        assertFalse(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 1, Unit) { hold.noteBrokenReferences() }
        assertTrue(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 0, Unit) { hold.onIrapAccepted() }
        assertTrue(hold.referenceRecoveryNeeded)
        ownership.withCurrent(owner, 1, Unit) { hold.onIrapAccepted() }
        assertFalse(hold.referenceRecoveryNeeded)
    }

    @Test
    fun readinessControlsStartupAndCooldownKeepTheirExistingAuthority() {
        val s = snapshot()
        val guarded = listOf(
            s.copy(repairReady = false), s.copy(pathReady = false),
            s.copy(zoomPinchActive = true), s.copy(gimbalStickHeld = true),
            s.copy(lastCameraSetAt = s.now - 100), s.copy(lastFocusTrackAt = s.now - 100),
            s.copy(lastZoomAt = s.now - 100), s.copy(lastGimbalThrowAt = s.now - 100),
            s.copy(lastEnableAt = s.now - 1_000), s.copy(live = false),
            s.copy(sawPicture = false), s.copy(decoderOutputExpected = false), s.copy(hasFormat = false),
        )
        for (snap in guarded) {
            val state = LiveViewEnablePolicy.State()
            assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snap))
            assertEquals(LiveViewEnablePolicy.Stage.IDLE, state.stage)
        }
        for (stage in listOf(LiveViewEnablePolicy.Stage.FULL_REJOIN, LiveViewEnablePolicy.Stage.COOLDOWN)) {
            val state = LiveViewEnablePolicy.State().apply { this.stage = stage }
            repeat(3) {
                assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, s))
                assertEquals(stage, state.stage)
            }
        }
        val state = LiveViewEnablePolicy.State()
        assertEquals(LiveViewEnablePolicy.Action.NONE,
            LiveViewEnablePolicy.tick(state, s.copy(referenceRecoveryNeeded = false, lastDecoderOutputAt = s.now - 1_999)))
        assertEquals(LiveViewEnablePolicy.Action.REBUILD_DECODER,
            LiveViewEnablePolicy.tick(state, s.copy(referenceRecoveryNeeded = false, lastDecoderOutputAt = s.now - 2_000)))
    }

    private fun snapshot(elapsed: Long = 0): LiveViewEnablePolicy.Snapshot {
        val now = 100_000 + elapsed
        return LiveViewEnablePolicy.Snapshot(
            now = now, videoPackets = 100, lastVideoPacketAt = now - 10, lastAccessUnitAt = now - 10,
            lastStatusAt = now - 10, lastBleNotifyAt = now - 10, lastRebuildAt = null, lastEnableAt = 0,
            pathReady = true, hasFormat = true, decoderErrors = 0, live = true, sawPicture = true,
            lastDecoderOutputAt = 99_761, lastPresentedAt = 99_761, decoderOutputExpected = true,
            referenceRecoveryNeeded = true,
        )
    }
}
