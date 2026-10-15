package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.core.ObservedValue
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.StorageStatus
import com.opencapture.opencine.core.StorageVolume
import com.opencapture.opencine.media.StorageReadout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewTileReadoutsTest {
    @Test fun unknownTelemetryNeverLooksLikeStandbyOrFullStorage() {
        val readouts = readouts(CameraStatus(), observed = null, available = false)
        assertEquals("—", readouts.timecode)
        assertEquals("—", readouts.battery)
        assertEquals("—", readouts.storage)
        assertEquals("REC —", readouts.recording)
        assertFalse(readouts.isRecording)
        assertTrue(multiviewExposureReadouts(CameraStatus()).all { it.second == "—" })
    }

    @Test fun reportedZeroBatteryAndFullCardRemainKnownValues() {
        val readouts = readouts(CameraStatus(batteryPercent = 0, sdTotalMb = 1024, sdFreeMb = 0), false, true)
        assertEquals("0%", readouts.battery)
        assertEquals("0 B", readouts.storage)
        assertEquals("STBY", readouts.recording)
    }

    @Test fun sharedStorageCaseReadsSixtyGigabytes() {
        // A5-11: 60e9 free of 128e9 bytes on the aggregate store, as the DJI wire carries them (MiB).
        val readouts = readouts(CameraStatus(storageFreeMb = 57_220, storageTotalMb = 122_070), false, true)
        assertEquals("60 GB", readouts.storage)
    }

    @Test fun typedStorageOverridesLegacyMegabytesWithoutInventingUnknown() {
        val legacy = CameraStatus(storageFreeMb = 2048, storageTotalMb = 4096)
        fun storage(bytes: Long): StorageStatus = ObservedValue(listOf(StorageVolume("active",
            freeBytes = ObservedValue(bytes, ObservationOrigin.CAMERA_REPORTED, null),
            totalBytes = ObservedValue(2000L, ObservationOrigin.CAMERA_REPORTED, null))),
            ObservationOrigin.CAMERA_REPORTED, null)
        assertEquals("1 KB", readouts(legacy, false, true, storage(1001)).storage)
        assertEquals("0 B", readouts(legacy, false, true, storage(0)).storage)
        val unknown: StorageStatus = ObservedValue.unknown
        assertEquals(StorageReadout.UNAVAILABLE, readouts(legacy, false, true, unknown).storage)
    }

    @Test fun eachCameraKeepsItsOwnTimecodeAndRecordingConfirmation() {
        val one = readouts(CameraStatus(timecode = "01:02:03:04", recordElapsedSec = 84), true, true)
        val two = readouts(CameraStatus(timecode = "10:20:30:12"), false, true)
        assertEquals("01:02:03", one.timecode)
        assertEquals("REC 1:24", one.recording)
        assertEquals("10:20:30", two.timecode)
        assertEquals("STBY", two.recording)
        val stale = readouts(CameraStatus(recordElapsedSec = 84), true, false)
        assertEquals("REC —", stale.recording)
    }

    @Test fun displayClockDoesNotChangeProtocolTimecode() {
        val status = CameraStatus(timecode = "01:02:03:24")
        assertEquals("01:02:03", status.timecodeClock)
        assertEquals("01:02:03:24", status.timecode)
        assertEquals("01:02:03", CameraStatus(timecode = "01:02:03").timecodeClock)
        assertEquals(null, CameraStatus(timecode = "").timecodeClock)
    }

    @Test fun compactReadoutsRetainIdentityAndUnknownFields() {
        val readouts = readouts(CameraStatus(batteryPercent = 73, storageTotalMb = 16384, storageFreeMb = 8192), false, true)
        assertEquals("B", readouts.letter)
        assertEquals("Side angle", readouts.name)
        assertEquals("Osmo Pocket 4", readouts.model)
        assertEquals("73%", readouts.battery)
        assertEquals("8.59 GB", readouts.storage) // 8192 MiB = 8.59e9 bytes
    }

    private fun readouts(settings: CameraStatus, observed: Boolean?, available: Boolean, storage: StorageStatus? = null) = multiviewTileReadouts(
        1, "Side angle", "Osmo Pocket 4", settings, settings.timecode, observed, available,
        recordingBusy = false, recovering = false, hasPicture = true, failure = null, storage = storage,
    )
}
