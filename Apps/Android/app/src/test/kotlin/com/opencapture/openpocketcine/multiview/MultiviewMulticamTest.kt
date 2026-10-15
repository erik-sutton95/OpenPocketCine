package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.multicam.RecordAll
import com.opencapture.opencine.multicam.RecordPlan
import com.opencapture.opencine.appkit.MultiviewRecordContext
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.MonitorEntryID
import com.opencapture.opencine.core.PictureHealth
import com.opencapture.opencine.core.StreamID
import com.opencapture.opencine.multicam.EditorLeaseRefusal
import com.opencapture.opencine.multicam.EditorLeases
import com.opencapture.opencine.multicam.Exclusion
import com.opencapture.opencine.multicam.ExclusionReason
import com.opencapture.opencine.multicam.RecordDirection
import com.opencapture.opencine.multicam.TargetOutcome
import com.opencapture.opencine.multicam.TargetPolicy
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Multi View rows of plan 11.3 that need no hardware, on the Android tile record seam
 * ([MultiviewTileControl] + [DjiCameraSessionAdapter]) driving the OpenCineMulticam engine
 * (iOS `MultiviewEngineTests`).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MultiviewMulticamTest {
    /** One tile's facts as `MultiviewSession.Tile.recordState()` reports them, plus its wire. */
    private class FakeTile(scope: CoroutineScope, clock: () -> Long, val name: String) {
        var state = TileRecordState(
            link = Any(), controlHost = true, cameraId = name, observation = false to 0L,
            recordingAvailable = true, batteryPercent = 80, storageFreeMb = 64_000, storageTotalMb = 128_000,
        )
        val sent = mutableListOf<Boolean>()
        var reply: Pair<Boolean, Long>? = null
        val port = MultiviewTileControl(
            state = { state },
            send = { start ->
                sent += start
                true
            },
            reply = { since -> reply?.takeIf { it.second >= since }?.first },
            setBusy = { state = state.copy(recordingBusy = it) },
            scope = scope,
            clock = clock,
        ).apply { confirmationWindowMs = 1_000 }
        val control = DjiCameraSessionAdapter(port, scope)
        val id = MonitorEntryID()
        val stream = StreamID()

        fun multicam() = MulticamTile(
            id, name, stream, control,
            busy = state.recordingBusy || state.connecting || state.recovering,
            picture = PictureHealth.LIVE,
        )

        /** Reconnect: same camera, replacement link (the tile's `driver` setter). */
        fun replaceLink() {
            state = state.copy(link = Any())
            control.linkDidChange()
        }
    }

    private fun TestScope.tiles(count: Int) = List(count) { FakeTile(this, { testScheduler.currentTime }, "Camera $it") }

    private fun view(tiles: List<FakeTile>) = MultiviewMulticam(tiles.map { it.multicam() })

    private fun plan(tiles: List<FakeTile>) =
        view(tiles).plan(tiles.map { it.id }, stop = tiles.any { it.state.observation?.first == true })

    @Test
    fun reconnectDuringConfirmationInvalidatesTheApprovedPlan() = runTest {
        val tiles = tiles(2)
        val approved = plan(tiles)
        assertTrue(approved.isExecutable)
        tiles[1].replaceLink()
        val now = plan(tiles)
        assertTrue(now.isExecutable)
        assertNotEquals(approved, now, "A replacement link changes the control epoch")
        assertNull(view(tiles).submit(approved))
        assertTrue(tiles.all { it.sent.isEmpty() })
    }

    @Test
    fun routineTelemetryKeepsTheConfirmationValid() = runTest {
        val tiles = tiles(3)
        val approved = plan(tiles)
        val entries = view(tiles).group.entries
        for (tile in tiles) {
            tile.state = tile.state.copy(
                batteryPercent = 61, storageFreeMb = 12_000, observation = false to testScheduler.currentTime + 500,
            )
        }
        assertEquals(approved, plan(tiles))
        assertTrue(approved.isCurrent(view(tiles).group, view(tiles).state))
        assertEquals(entries, view(tiles).group.entries, "Entry and session IDs are the tiles' own")
        // A one-tile plan (built over that tile only) is the plan the full view revalidates.
        val single = MultiviewMulticam(listOf(tiles[0].multicam())).plan(listOf(tiles[0].id), stop = false)
        assertTrue(single.isCurrent(view(tiles).group, view(tiles).state))
        // An operation-relevant change does invalidate: a camera reports recording.
        tiles[2].state = tiles[2].state.copy(observation = true to testScheduler.currentTime + 600)
        assertNotEquals(approved, plan(tiles))
    }

    @Test
    fun oneCameraThatCannotRecordRefusesStrictAndIsListedForSubset() = runTest {
        val tiles = tiles(3)
        tiles[2].state = tiles[2].state.copy(recordingAvailable = false) // its record report went stale
        val strict = plan(tiles)
        assertEquals(TargetPolicy.STRICT, strict.policy)
        assertTrue(strict.isRefused)
        val exclusion = Exclusion(tiles[2].id, ExclusionReason.Rejected(CommandRejection.RecordingStateUnknown))
        assertEquals(listOf(exclusion), strict.exclusions)
        assertEquals("Waiting for a camera's record state.", MultiviewRecordContext(strict).refusal)

        val subset = view(tiles).let { RecordPlan.make(RecordDirection.START, TargetPolicy.ELIGIBLE_SUBSET, tiles.map { it.id }, it.group, it.state) }
        assertTrue(subset.isExecutable)
        assertEquals(listOf(exclusion), subset.exclusions)
        assertEquals(tiles.take(2).map { it.control.id }, subset.targets.map { it.session })
    }

    @Test
    fun someCamerasStartOneTimesOutOneIsRefusedAndNothingIsRolledBack() = runTest {
        val tiles = tiles(4)
        val (a, b, c, d) = tiles
        val plan = plan(tiles)
        assertEquals(RecordDirection.START, plan.direction)
        val run = async { view(tiles).submit(plan) }
        advanceTimeBy(150)
        runCurrent()
        assertTrue(tiles.all { it.state.recordingBusy })
        val now = testScheduler.currentTime
        // a ACKs then reports recording; b only reports; c stays silent; d NACKs.
        a.reply = true to now
        a.state = a.state.copy(observation = true to now)
        b.state = b.state.copy(observation = true to now)
        d.reply = false to now
        val result = run.await()!!

        assertEquals(TargetOutcome.Confirmed, result.outcome(a.id, view(tiles).group))
        assertEquals(TargetOutcome.Confirmed, result.outcome(b.id, view(tiles).group))
        assertEquals(TargetOutcome.TimedOut, result.outcome(c.id, view(tiles).group))
        assertEquals(TargetOutcome.Rejected(CommandRejection.CameraRefused), result.outcome(d.id, view(tiles).group))
        assertEquals("Recording", RecordAll.note(TargetOutcome.Confirmed, RecordDirection.START))
        assertEquals("No confirmation · check camera", RecordAll.note(TargetOutcome.TimedOut, RecordDirection.START))
        assertEquals(
            "Recording command rejected · check camera",
            RecordAll.note(TargetOutcome.Rejected(CommandRejection.CameraRefused), RecordDirection.START),
        )
        assertEquals("2 of 4 confirmed · check camera tiles", RecordAll.summary(result, allMatch = false))
        advanceTimeBy(5_000)
        // Only the four starts went out: no stop for a or b because c and d failed.
        assertEquals(listOf(listOf(true), listOf(true), listOf(true), listOf(true)), tiles.map { it.sent })
        assertFalse(tiles.any { it.state.recordingBusy })
    }

    @Test
    fun switchingCameraRetiresTheEditorLease() = runTest {
        val tiles = tiles(2)
        val (a, b) = tiles
        val leases = EditorLeases()
        var now = view(tiles)
        val first = leases.open(a.id, now.group, now.state)
        assertNull(leases.refusal(first, now.group, now.state))
        // MultiviewSession.openControls: one editor at a time.
        leases.closeAll()
        val second = leases.open(b.id, now.group, now.state)
        assertEquals(EditorLeaseRefusal.RETIRED, leases.refusal(first, now.group, now.state))
        assertNull(leases.refusal(second, now.group, now.state))
        // A reconnect retires the open lease through the control epoch alone.
        b.replaceLink()
        now = view(tiles)
        assertEquals(EditorLeaseRefusal.RETIRED, leases.refusal(second, now.group, now.state))
    }
}
