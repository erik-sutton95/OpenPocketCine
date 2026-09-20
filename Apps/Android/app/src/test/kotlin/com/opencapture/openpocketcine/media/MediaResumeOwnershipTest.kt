package com.opencapture.openpocketcine.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class MediaResumeOwnershipTest {
    @Test
    fun acceptedEnableDoesNotBecomeA350MillisecondPliLoop() {
        var enableSent = false
        var enables = 0
        repeat(10) {
            val action = MediaLiveResume.action(it + 1, false, true, false, enableSent)
            if (action == MediaLiveResume.Action.ENABLE_LIVE_VIEW) {
                enables += 1
                enableSent = true
            }
        }
        assertEquals(1, enables)
    }

    @Test
    fun expiredExitAndPictureBudgetsNeverIssueAnotherEnable() {
        assertNotEquals(MediaLiveResume.Action.ENABLE_LIVE_VIEW,
            MediaLiveResume.action(9, true, false, false))
        assertNotEquals(MediaLiveResume.Action.ENABLE_LIVE_VIEW,
            MediaLiveResume.action(2, false, true, false, enableSent = true, deadlineExpired = true))
    }

    @Test
    fun productionRunnerSendsOnceThenExhaustsThePictureBudget() = runBlocking {
        var now = 0L
        var enables = 0
        val result = MediaLiveResumeRunner.run(16_000, { now }, { true }, { false }, { false },
            exitPlayback = { now += 450; true }, enableLiveView = { enables += 1; true },
            sleep = { now += it })
        assertEquals(MediaLiveResumeRunner.Result.EXHAUSTED, result)
        assertEquals(1, enables)
    }

    @Test
    fun productionRunnerRestoresPictureWithoutAnotherEnable() = runBlocking {
        var now = 0L
        var enables = 0
        val result = MediaLiveResumeRunner.run(16_000, { now }, { true }, { false }, { now >= 3_000 },
            exitPlayback = { now += 450; true }, enableLiveView = { enables += 1; true },
            sleep = { now += it })
        assertEquals(MediaLiveResumeRunner.Result.RESTORED, result)
        assertEquals(1, enables)
    }

    @Test
    fun productionRunnerDoesNotEnableAfterPlaybackExitBudgetOrSupersession() = runBlocking {
        for (superseded in listOf(false, true)) {
            var now = 0L
            var current = true
            var exits = 0
            var enables = 0
            val result = MediaLiveResumeRunner.run(16_000, { now }, { current }, { true }, { false },
                exitPlayback = {
                    exits += 1
                    now += 450
                    if (superseded) current = false
                    false
                }, enableLiveView = { enables += 1; true }, sleep = { now += it })
            assertEquals(if (superseded) MediaLiveResumeRunner.Result.SUPERSEDED
                else MediaLiveResumeRunner.Result.EXHAUSTED, result)
            assertEquals(if (superseded) 1 else MediaLiveResume.MAX_EXIT_ATTEMPTS, exits)
            assertEquals(0, enables)
        }
    }

    @Test
    fun busyEnableGateCanRetryButAcceptedEnableCannot() = runBlocking {
        var now = 0L
        var tries = 0
        var sent = 0
        val result = MediaLiveResumeRunner.run(16_000, { now }, { true }, { false }, { now >= 3_000 },
            exitPlayback = { now += 450; true }, enableLiveView = {
                tries += 1
                (tries >= 3).also { if (it) sent += 1 }
            }, sleep = { now += it })
        assertEquals(MediaLiveResumeRunner.Result.RESTORED, result)
        assertEquals(3, tries)
        assertEquals(1, sent)
    }
    @Test
    fun mediaReturnWaitsThroughMissingLinkAndStartsItsPictureBudgetAfterNegotiation() = runBlocking {
        var now = 0L
        var linkReady = false
        var repairBusy = true
        var enables = 0
        val ownsSlot = MediaLiveResumeRunner.awaitRepairSlot(
            isCurrent = { true }, repairBusy = { repairBusy }, sleep = {
                now += it
                if (now >= 20_000) { linkReady = true; repairBusy = false }
            })
        assertEquals(true, ownsSlot)
        assertEquals(true, linkReady)
        val result = MediaLiveResumeRunner.run(16_000, { now }, { linkReady }, { false }, { false },
            exitPlayback = { true }, enableLiveView = { enables += 1; true }, sleep = { now += it })
        assertEquals(MediaLiveResumeRunner.Result.EXHAUSTED, result)
        assertTrue(now in 36_000L until 36_100L)
        assertEquals(1, enables)
    }

    @Test
    fun lostMediaOwnerWhileWaitingNeverClaimsThePictureBudget() = runBlocking {
        var current = true
        val ownsSlot = MediaLiveResumeRunner.awaitRepairSlot(
            isCurrent = { current }, repairBusy = { true }, sleep = { current = false })
        assertEquals(false, ownsSlot)
    }

    @Test
    fun retainedRepaintCannotCompleteMediaReturnWithoutFreshSource() = runBlocking {
        var now = 1_000L
        var enables = 0
        val startedAt = now
        val result = MediaLiveResumeRunner.run(16_000, { now }, { true }, { false },
            pictureFresh = {
                com.opencapture.openpocketcine.session.RecoveryPictureProof.isFresh(
                    startedAt, now, presentedAt = now, accessUnitAt = startedAt - 1)
            }, exitPlayback = { true }, enableLiveView = { enables += 1; true }, sleep = { now += it })
        assertEquals(MediaLiveResumeRunner.Result.EXHAUSTED, result)
        assertEquals(1, enables)
    }

}
