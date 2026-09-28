package com.opencapture.openpocketcine.pairing

import com.opencapture.monitorui.MonitorConnectProgress
import com.opencapture.monitorui.MonitorConnectStep
import com.opencapture.openpocketcine.core.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SavedCameraSetupPresentationTest {
    private val camera = SavedCamera(
        "a", "OsmoPocket4P-1", "Osmo Pocket 4 Pro", "OsmoPocket4P-1", 1L,
        wifiSSID = "Studio", lastSetup = CameraConnectionSetup.WIFI,
    )

    @Test
    fun chipsMarkTheSessionSetupWhileConnectingAndThePreferredOneOtherwise() {
        val idle = SavedCameraSetupPresentation.chips(camera, null)
        assertEquals(listOf("Camera Wi-Fi", "Wi-Fi · Studio"), idle.map { it.title })
        assertEquals("wifi", idle.single { it.active }.id)
        assertFalse(idle.first().canForget)
        val connecting = SavedCameraSetupPresentation.chips(camera, CameraConnectionSetup.CAMERA_WIFI)
        assertEquals("cameraWiFi", connecting.single { it.active }.id)
        assertTrue(SavedCameraSetupPresentation.canAddSetup(camera, appearsInMultiview = true))
        assertFalse(SavedCameraSetupPresentation.canAddSetup(camera, appearsInMultiview = false))
    }

    @Test
    fun stepsFollowTheStationProgress() {
        val moving = SavedCameraSetupPresentation.steps(
            ConnectionPhase.JOINING_WIFI, CameraConnectionSetup.WIFI, camera, "Joining Wi-Fi · attempt 1 of 3", "Joining",
        )
        assertEquals("Moving the camera to Studio · Joining Wi-Fi · attempt 1 of 3", MonitorConnectProgress.caption(moving))
        val finding = SavedCameraSetupPresentation.steps(
            ConnectionPhase.JOINING_WIFI, CameraConnectionSetup.WIFI, camera, "Finding the camera on Studio", "Joining",
        )
        assertEquals(MonitorConnectStep.State.ACTIVE, finding[2].state)
        assertEquals(0.625f, MonitorConnectProgress.fraction(finding))
    }

    @Test
    fun failureOffersEditRetryAndCameraWiFiOnlyForMovingSetups() {
        val station = SavedCameraSetupPresentation.failure("the camera did not respond", CameraConnectionSetup.WIFI, camera, false)
        assertEquals("Couldn’t connect over Studio", station.title)
        assertEquals("The camera did not respond.", station.message)
        assertEquals(listOf("edit", "retry"), station.actions.map { it.id })
        assertEquals("cameraWiFi", station.link?.id)
        val ap = SavedCameraSetupPresentation.failure("x", CameraConnectionSetup.CAMERA_WIFI, camera, false)
        assertEquals(listOf("retry"), ap.actions.map { it.id })
        assertNull(ap.link)
        val hotspot = SavedCameraSetupPresentation.failure("x", CameraConnectionSetup.PHONE_HOTSPOT, camera, false)
        assertTrue(hotspot.message.contains("hotspot"))
    }
}
