package com.opencapture.openpocketcine.pairing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SavedCameraRecordsTest {
    @Test
    fun upsertKeepsCustomNameAndNewestFirst() {
        val first =
            SavedCamera("a", "OsmoPocket4P-1", "Osmo Pocket 4 Pro", "OPENPOCKETCINE", 1_000L, customName = "A-cam")
        val second = SavedCamera("b", "OsmoPocket3-2", "Osmo Pocket 3", null, 2_000L)
        val reconnect = SavedCamera("a", "OsmoPocket4P-1", "Osmo Pocket 4 Pro", "SSID2", 3_000L)
        val result = SavedCameras.upserting(reconnect, listOf(first, second))
        assertEquals(listOf("a", "b"), result.map { it.id })
        assertEquals("A-cam", result.first().customName)
        assertEquals("SSID2", result.first().lastSSID)
    }

    @Test
    fun emptyStoreLaunchesWizard() {
        assertTrue(SavedCameras.launchShowsWizard(emptyList()))
        assertTrue(!SavedCameras.launchShowsWizard(listOf(SavedCamera("a", "n", "m", null, 1))))
    }

    @Test
    fun roundTripJson() {
        val records =
            listOf(SavedCamera("id-1", "OsmoPocket4P-AAAA", "Osmo Pocket 4 Pro", "DJI-xxx", 42L, "Rig"))
        val decoded = SharedPreferencesSavedCameraStore.decode(SharedPreferencesSavedCameraStore.encode(records))
        assertEquals(records, decoded)
    }

    @Test
    fun renamedSoftAPUsesLiveAdvertisedSSIDNotCache() {
        val id = "pocket-1"
        val renamed =
            CameraWifiResolution.resolve(
                cameraId = id,
                savedSSID = "OsmoPocket4P-AAAA",
                memoryCameraId = id,
                memorySsid = "OsmoPocket4P-AAAA",
                memoryPassword = "pocket-pass",
                keychainSsid = "OsmoPocket4P-AAAA",
                keychainPassword = "pocket-pass",
                advertisedName = "VanCam",
            )
        assertEquals("VanCam", renamed.ssid)
        assertEquals("pocket-pass", renamed.password)
        assertTrue(renamed.skipBle)
        assertEquals("memory", renamed.source)

        val generic =
            CameraWifiResolution.resolve(
                cameraId = id,
                savedSSID = "OsmoPocket4P-AAAA",
                memoryCameraId = id,
                memorySsid = "OsmoPocket4P-AAAA",
                memoryPassword = "pocket-pass",
                keychainSsid = "OsmoPocket4P-AAAA",
                keychainPassword = "pocket-pass",
                advertisedName = "DJI camera",
            )
        assertEquals("OsmoPocket4P-AAAA", generic.ssid)
        assertTrue(generic.skipBle)
    }

    @Test
    fun bleRenameReplacesScanRowName() {
        assertTrue(
            FoundCameraIdentity.shouldReplace(
                existingName = "OsmoPocket4P-AAAA",
                existingModelId = 0x22,
                incomingName = "VanCam",
                incomingModelId = 0x22,
            )
        )
        assertTrue(
            !FoundCameraIdentity.shouldReplace(
                existingName = "VanCam",
                existingModelId = 0x22,
                incomingName = "DJI camera",
                incomingModelId = 0x22,
            )
        )
    }
}
