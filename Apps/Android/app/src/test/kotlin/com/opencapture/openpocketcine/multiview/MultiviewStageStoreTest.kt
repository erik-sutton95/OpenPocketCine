package com.opencapture.openpocketcine.multiview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MultiviewStageStoreTest {
    private fun camera(slot: Int, id: String, lut: Boolean = false) =
        MultiviewStageStore.Camera(
            slot = slot, id = id, name = "OsmoPocket3-$id", modelId = 0x20, bleAddress = "AA:BB:CC:DD:EE:0$slot",
            identity = byteArrayOf(0, 5, 0x41), address = "192.168.1.3$slot", experimental = false, lutEnabled = lut,
        )

    @Test fun stageRoundTripsWithCleanupLedger() {
        val stage = MultiviewStageStore.Stage(
            ssid = "Test", hotspot = true, layout = MultiviewLayout.GRID.raw, focusedIndex = 2,
            cameras = listOf(camera(0, "a", lut = true)), pendingReset = listOf(camera(0, "b")),
            returnedToCameraWiFi = false, fill = true,
        )
        assertEquals(stage, MultiviewStageStore.decode(MultiviewStageStore.encode(stage)))
    }

    @Test fun cleanupOnlyStageNeedsNoNetworkButCamerasDo() {
        val cleanup = MultiviewStageStore.Stage(
            ssid = "", hotspot = false, layout = "Center stage", focusedIndex = 0,
            cameras = emptyList(), pendingReset = listOf(camera(0, "a")),
        )
        assertEquals(cleanup, cleanup.validated)
        assertNull(cleanup.copy(cameras = listOf(camera(0, "c"))).validated)
        assertNull(cleanup.copy(ssid = "Test", focusedIndex = 4).validated)
        assertNull(
            cleanup.copy(ssid = "Test", cameras = listOf(camera(1, "x"), camera(1, "y"))).validated,
        )
    }

    @Test fun cleanupTargetsReplaceByIdentityAndAppendNewCameras() {
        val merged = MultiviewStageStore.cleanupTargets(
            listOf(camera(0, "a"), camera(1, "b")),
            listOf(camera(3, "a", lut = true), camera(2, "c")),
        )
        assertEquals(listOf("a", "b", "c"), merged.map { it.id })
        assertTrue(merged.first().lutEnabled)
    }

    @Test fun unknownLayoutFallsBackToCenterStage() {
        assertEquals(MultiviewLayout.CENTER_STAGE, MultiviewLayout.from("legacy"))
        assertEquals(MultiviewLayout.GRID, MultiviewLayout.from("2 × 2 grid"))
    }

    @Test fun maskMatchesPrefixLength() {
        assertEquals("255.255.255.0", SharedWiFi.mask(24))
        assertEquals("255.255.252.0", SharedWiFi.mask(22))
        assertTrue(SharedWiFi.validAddress("192.168.236.61"))
        assertTrue(!SharedWiFi.validAddress("127.0.0.1") && !SharedWiFi.validAddress("224.0.0.1"))
    }
}
