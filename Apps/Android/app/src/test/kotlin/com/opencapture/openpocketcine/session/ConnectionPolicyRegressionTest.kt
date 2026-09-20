package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals

class ConnectionPolicyRegressionTest {
    @Test
    fun freshPacketsCannotKeepFirstPictureWaitingPastItsRepairDeadline() {
        fun step(elapsed: Long, picture: Boolean = false, formatBusy: Boolean = false) =
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 100, enableSends = 2, sinceEnableMs = elapsed,
                videoAgeMs = 10, sinceRebuildMs = null,
                hasPresentedPicture = picture, recordingFormatPokeInFlight = formatBusy,
            )
        for (elapsed in listOf(0L, 2_000, 5_000, 8_000, 15_999)) {
            assertEquals(LiveViewEnablePolicy.FirstPictureStep.WAIT, step(elapsed))
        }
        assertEquals(LiveViewEnablePolicy.FirstPictureStep.REJOIN, step(16_000))
        assertEquals(LiveViewEnablePolicy.FirstPictureStep.WAIT, step(60_000, picture = true))
        assertEquals(LiveViewEnablePolicy.FirstPictureStep.WAIT, step(60_000, formatBusy = true))
    }

    @Test
    fun everyRecentControlGraceExpiresAgainstTheStalledStage() {
        for (assembly in listOf(false, true)) {
            for (control in 0..3) {
                fun controlled(age: Long): LiveViewEnablePolicy.Snapshot {
                    val snap = stalled(age, assembly)
                    return when (control) {
                        0 -> snap.copy(lastCameraSetAt = snap.now - 100)
                        1 -> snap.copy(lastFocusTrackAt = snap.now - 100)
                        2 -> snap.copy(lastZoomAt = snap.now - 100)
                        else -> snap.copy(lastGimbalThrowAt = snap.now - 100)
                    }
                }
                val state = LiveViewEnablePolicy.State()
                assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, controlled(3_000)))
                val expected = if (assembly) LiveViewEnablePolicy.Action.RESEND_ENABLE
                    else LiveViewEnablePolicy.Action.REBUILD_DECODER
                assertEquals(expected, LiveViewEnablePolicy.tick(state, controlled(7_000)),
                    "assembly=$assembly control=$control: fresh upstream packets cannot extend grace")
            }
        }
    }

    @Test
    fun activeGesturesGopGraceAndReadinessStillOwnTheirHold() {
        for (assembly in listOf(false, true)) {
            val snap = stalled(60_000, assembly).copy(lastCameraSetAt = 159_900)
            for (held in listOf(
                snap.copy(zoomPinchActive = true),
                snap.copy(gimbalStickHeld = true),
                snap.copy(repairReady = false),
                snap.copy(lastEnableAt = snap.now - 1_000),
                snap.copy(lastDecoderOutputAt = snap.now - 10),
            )) {
                assertEquals(LiveViewEnablePolicy.Action.NONE,
                    LiveViewEnablePolicy.tick(LiveViewEnablePolicy.State(), held))
            }
        }
    }

    private fun stalled(age: Long, assembly: Boolean): LiveViewEnablePolicy.Snapshot {
        val now = 100_000 + age
        return LiveViewEnablePolicy.Snapshot(
            now = now, videoPackets = 100, lastVideoPacketAt = now - 10,
            lastAccessUnitAt = if (assembly) now - age else now - 10,
            lastStatusAt = now - 10, lastBleNotifyAt = now - 10,
            lastRebuildAt = null, lastEnableAt = 0,
            pathReady = true, hasFormat = true, decoderErrors = 0, live = true, sawPicture = true,
            lastDecoderOutputAt = now - age, lastPresentedAt = now - age, decoderOutputExpected = true,
        )
    }
}
