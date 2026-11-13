package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.appkit.MultiviewStageJournal
import com.opencapture.opencine.dji.SharedWiFi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MultiviewStageStoreTest {
    private fun camera(slot: Int, id: String, lut: Boolean = false) =
        MultiviewStageJournal.Camera(
            slot = slot, id = id, name = "OsmoPocket3-$id", modelId = 0x20, deviceAddress = "AA:BB:CC:DD:EE:0$slot",
            identity = byteArrayOf(0, 5, 0x41), address = "192.168.1.3$slot", experimental = false, lutEnabled = lut,
        )

    @Test fun stageRoundTripsWithCleanupLedger() {
        val stage = MultiviewStageJournal.Stage(
            ssid = "Test", hotspot = true, layout = MultiviewLayout.GRID.raw, focusedIndex = 2,
            cameras = listOf(camera(0, "a", lut = true)), pendingReset = listOf(camera(0, "b")),
            returnedToCameraWiFi = false, fill = true,
        )
        assertEquals(stage, MultiviewStageStore.decode(MultiviewStageStore.encode(stage)))
    }

    @Test fun cleanupOnlyStageNeedsNoNetworkButCamerasDo() {
        val cleanup = MultiviewStageJournal.Stage(
            ssid = "", hotspot = false, layout = "Center stage", focusedIndex = 0,
            cameras = emptyList(), pendingReset = listOf(camera(0, "a")),
        )
        assertEquals(cleanup, cleanup.validated(MultiviewQualificationPolicy.tileCount))
        assertNull(cleanup.copy(cameras = listOf(camera(0, "c"))).validated(MultiviewQualificationPolicy.tileCount))
        assertNull(cleanup.copy(ssid = "Test", focusedIndex = 4).validated(MultiviewQualificationPolicy.tileCount))
        assertNull(
            cleanup.copy(ssid = "Test", cameras = listOf(camera(1, "x"), camera(1, "y"))).validated(MultiviewQualificationPolicy.tileCount),
        )
    }

    @Test fun decodeAppliesThisAppsValidation() {
        val ok = MultiviewStageJournal.Stage(
            ssid = "Test", hotspot = false, layout = "Center stage", focusedIndex = 0, cameras = listOf(camera(0, "a")),
        )
        assertEquals(ok, MultiviewStageStore.decode(MultiviewStageStore.encode(ok)))
        assertNull(MultiviewStageStore.decode(MultiviewStageStore.encode(ok.copy(focusedIndex = 4))))
        val five = (0..4).map { camera(it % 4, "c$it") }
        assertNull(MultiviewStageStore.decode(MultiviewStageStore.encode(ok.copy(cameras = five))))
        assertNull(MultiviewStageStore.decode("not json"))
    }

    @Test fun legacyStoredJsonStillLoads() {
        val raw = """{"version":1,"ssid":"Net","hotspot":true,"layout":"Grid","focusedIndex":1,
            "cameras":[{"slot":0,"id":"a","name":"OsmoPocket3-a","bleAddress":"AA:BB:CC:DD:EE:00",
            "address":"192.168.1.30","experimental":false,"lutEnabled":true,"modelId":32,"identity":"000541"}],
            "pendingReset":[],"returnedToCameraWiFi":false,"fill":true}"""
        val stage = MultiviewStageStore.decode(raw)!!
        val camera = stage.cameras.single()
        assertEquals("AA:BB:CC:DD:EE:00", camera.deviceAddress)
        assertEquals(32, camera.modelId)
        assertTrue(byteArrayOf(0, 5, 0x41).contentEquals(camera.identity))
        assertEquals(true, stage.fill)
    }

    @Test fun cleanupTargetsReplaceByIdentityAndAppendNewCameras() {
        val merged = MultiviewStageJournal.cleanupTargets(
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
