package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.appkit.MultiviewTile
import com.opencapture.opencine.appkit.MultiviewTool
import com.opencapture.opencine.core.CameraTimecode
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.StorageStatus
import com.opencapture.opencine.core.StorageVolume
import com.opencapture.opencine.media.StorageReadout
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertNull
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewTileReadoutsTest {
    @Test fun unknownTelemetryNeverLooksLikeStandbyOrFullStorage() {
        val readouts = readouts(CameraStatus(), observed = null)
        assertEquals("—", readouts.timecode)
        assertEquals("—", readouts.battery)
        assertEquals("—", readouts.storage)
        assertEquals("\u2014", readouts.recording)
        assertFalse(readouts.isRecording)
        assertTrue(multiviewExposureReadouts(CameraStatus()).all { it.second == "—" })
    }

    @Test fun reportedZeroBatteryAndFullCardRemainKnownValues() {
        val readouts = readouts(CameraStatus(sdTotalMb = 1024, sdFreeMb = 0), false, power = percent(0.0))
        assertEquals("0%", readouts.battery)
        assertEquals("0 B", readouts.storage)
        assertEquals("STBY", readouts.recording)
    }

    @Test fun sharedStorageCaseReadsSixtyGigabytes() {
        // A5-11: 60e9 free of 128e9 bytes on the aggregate store, as the DJI wire carries them (MiB).
        val readouts = readouts(CameraStatus(storageFreeMb = 57_220, storageTotalMb = 122_070), false)
        assertEquals("60 GB", readouts.storage)
    }

    @Test fun typedStorageOverridesLegacyMegabytesWithoutInventingUnknown() {
        val legacy = CameraStatus(storageFreeMb = 2048, storageTotalMb = 4096)
        fun storage(bytes: Long): StorageStatus = ObservedValue(listOf(StorageVolume("active",
            freeBytes = ObservedValue(bytes, ObservationOrigin.CAMERA_REPORTED, null),
            totalBytes = ObservedValue(2000L, ObservationOrigin.CAMERA_REPORTED, null))),
            ObservationOrigin.CAMERA_REPORTED, null)
        assertEquals("1 KB", readouts(legacy, false, storage(1001)).storage)
        assertEquals("0 B", readouts(legacy, false, storage(0)).storage)
        val unknown: StorageStatus = ObservedValue.unknown
        assertEquals(StorageReadout.UNAVAILABLE, readouts(legacy, false, unknown).storage)
    }

    @Test fun eachCameraKeepsItsOwnTimecodeAndRecordingConfirmation() {
        val one = readouts(CameraStatus(recordElapsedSec = 84), true, timecode = "01:02:03")
        val two = readouts(CameraStatus(), false, timecode = "10:20:30")
        assertEquals("01:02:03", one.timecode)
        assertEquals("REC 01:24", one.recording)
        assertEquals("10:20:30", two.timecode)
        assertEquals("STBY", two.recording)
        val stale = readouts(CameraStatus(recordElapsedSec = 84), true)
        assertEquals("REC 01:24", stale.recording)
    }

    @Test fun tallyAndFormatMatchIOS() {
        assertEquals("REC 01:05", readouts(CameraStatus(recordElapsedSec = 65), true).recording)
        assertEquals("STBY", readouts(CameraStatus(), false).recording)
        assertEquals("\u2014", readouts(CameraStatus(), null).recording)
        assertEquals("WAIT", readouts(CameraStatus(), false, busy = true).recording)
        assertEquals("HOLD", readouts(CameraStatus(), false, recovering = true).recording)
        assertEquals("CHECK", readouts(CameraStatus(), false, failure = "lost").recording)
        assertEquals("4K 25p \u00b7 D-Log M", readouts(CameraStatus(resolutionCode = CameraCommands.RES_4K, fps = 25, colorMode = CameraCommands.COLOR_DLOG_M), false).format)
    }

    @Test fun recordNoteReachesTheTileExceptPlainConfirmations() {
        // The shared rule (OpenCine `MultiviewTile.tileNote`, keyed off RecordAll's confirmations).
        assertEquals("Camera rejected the record command", MultiviewTile.tileNote("Camera rejected the record command"))
        assertEquals("No confirmation from camera", MultiviewTile.tileNote("No confirmation from camera"))
        assertNull(MultiviewTile.tileNote("Recording"))
        assertNull(MultiviewTile.tileNote("Recording stopped"))
        assertNull(MultiviewTile.tileNote(null))
    }

    @Test fun toolbarMatchesIOSOrder() {
        assertEquals(listOf(MultiviewTool.LAYOUT, MultiviewTool.CAMERA, MultiviewTool.FIT, MultiviewTool.LUT), multiviewTools)
    }

    @Test fun compactReadoutsRetainIdentityAndUnknownFields() {
        val readouts = readouts(CameraStatus(storageTotalMb = 16384, storageFreeMb = 8192), false, power = percent(0.73))
        assertEquals("B", readouts.letter)
        assertEquals("Side angle", readouts.name)
        assertEquals("Osmo Pocket 4", readouts.model)
        assertEquals("73%", readouts.battery)
        assertEquals("8.59 GB", readouts.storage) // 8192 MiB = 8.59e9 bytes
    }

    @Test fun commonPowerOverridesRetainedLegacyBatteryWithoutInventingUnknown() {
        val status = CameraStatus(batteryPercent = 99)
        fun actual(power: com.opencapture.opencine.core.PowerStatus) = multiviewTileReadouts(
            1, "SIMULATED", "SIMULATED", status, null, false,
            false, false, true, null, power = power)
        val gauge = com.opencapture.opencine.core.PowerStatus(battery = com.opencapture.opencine.core.ObservedValue(
            0.25, com.opencapture.opencine.core.ObservationOrigin.CAMERA_REPORTED, null,
            precision = com.opencapture.opencine.core.ObservationPrecision.Quantized(0.25)))
        assertEquals("1/4", actual(gauge).battery)
        assertEquals("\u2014", actual(com.opencapture.opencine.core.PowerStatus.unknown).battery)
        assertEquals("0%", actual(com.opencapture.opencine.core.PowerStatus(battery = com.opencapture.opencine.core.ObservedValue(
            0.0, com.opencapture.opencine.core.ObservationOrigin.CAMERA_REPORTED, null))).battery)
    }

    /** iOS `MultiviewStageTests.testTimecodeRequiresCameraReportAndIsHiddenOnNano`, on the tile's adapter. */
    @Test fun tileTimecodeRequiresACameraReportAndIsHiddenOnNano() = runTest {
        for (model in listOf(CameraModel(name = "Osmo Pocket 3", verified = true),
            CameraModel(name = "Osmo Pocket 4", verified = true),
            CameraModel(name = "Osmo Nano", family = "nano", verified = true))) {
            var state = TileRecordState(model = model)
            val control = DjiCameraSessionAdapter(MultiviewTileControl(
                state = { state }, send = { true }, reply = { null }, setBusy = {},
                scope = backgroundScope, clock = { 0L }), backgroundScope)
            assertNull(control.tileTimecodeReadout())
            state = state.copy(timecode = CameraTimecode(1, 2, 3, 4))
            assertEquals(if (model.family == "nano") null else "01:02:03", control.tileTimecodeReadout(), model.name)
        }
    }

    private fun percent(value: Double) = PowerStatus(battery = ObservedValue(value, ObservationOrigin.CAMERA_REPORTED, null))

    /** [timecode] is the tile's clock as the shared status formats it (`MultiviewSession.Tile.timecodeReadout`). */
    private fun readouts(settings: CameraStatus, observed: Boolean?, storage: StorageStatus? = null,
        timecode: String? = null, power: PowerStatus = PowerStatus.unknown,
        busy: Boolean = false, recovering: Boolean = false, failure: String? = null) = multiviewTileReadouts(
        1, "Side angle", "Osmo Pocket 4", settings, timecode, observed,
        recordingBusy = busy, recovering = recovering, hasPicture = true, failure = failure, power = power, storage = storage,
    )
}
