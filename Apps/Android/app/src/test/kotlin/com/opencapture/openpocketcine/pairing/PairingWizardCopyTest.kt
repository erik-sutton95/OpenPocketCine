package com.opencapture.openpocketcine.pairing

import com.opencapture.opencine.appkit.NearbyCardCopy
import com.opencapture.opencine.appkit.PairingWizard
import com.opencapture.opencine.core.NearbyCamera
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.dji.fromJson
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.pairingWizard
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The pair page and nearby cards in the words this app's main showed (PairingExperience, NearbyCameraRow). */
class PairingWizardCopyTest {
    private fun wizard(granted: Boolean = true, needsSettings: Boolean = false, radioOn: Boolean = true) =
        pairingWizard("label", null, vpnActive = false, granted = granted, needsSettings = needsSettings, radioOn = radioOn)

    @Test
    fun theWizardKeepsThePocketPages() {
        val wizard = wizard()
        assertEquals(
            listOf(
                "Turn the camera on and keep the phone nearby. Pocket and Nano both appear. Choose the one you want.",
                "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
                "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ),
            wizard.bodies,
        )
        assertEquals(listOf("Look for an Approve / pairing prompt", "Tap it on the camera screen"), wizard.approveLines)
        assertEquals(listOf("Leave the camera on. It brings up its own Wi-Fi", "On 5.8 GHz that can take about a minute; we keep trying"), wizard.joinLines)
        assertEquals(null, wizard.blocker)
    }

    @Test
    fun discoveryBlockersTakeThePrimaryAction() {
        assertEquals("Open Settings", wizard(granted = false, needsSettings = true).blocker)
        assertTrue(wizard(granted = false).blocker!!.startsWith("Allow "))
        assertEquals("Turn Bluetooth on", wizard(radioOn = false).blocker)
    }

    @Test
    fun theLiveLabelIsThePhase() {
        assertEquals("Scanning for camera…", PairingWizard.phaseLabel(ConnectionPhase.SCANNING))
        assertEquals("Approve on the camera screen", PairingWizard.phaseLabel(ConnectionPhase.AWAITING_APPROVAL))
        assertEquals("Reading Wi-Fi credentials…", PairingWizard.phaseLabel(ConnectionPhase.READING_WIFI_CREDS))
        assertEquals("Opening datalink…", PairingWizard.phaseLabel(ConnectionPhase.OPENING_DATALINK))
    }

    @Test
    fun nearbyCardsReadAsMain() {
        val camera = NearbyCamera("n1", name = "OsmoPocket3-4D5E", model = "Osmo Pocket 3", routes = setOf(RouteKind.CAMERA_ACCESS_POINT))
        val found = FoundCamera("n1", "BB", "OsmoPocket3-4D5E", CameraModel.fromJson("""{"name":"Osmo Pocket 3","family":"pocket","verified":true}"""), 0x20)
        assertEquals(
            NearbyCardCopy("OsmoPocket3-4D5E", "Pocket · Osmo Pocket 3 · nearby", "Needs approval on the camera"),
            AppModel.nearbyCard(camera, found),
        )
        val nano = FoundCamera("n2", "CC", "DJI Camera", CameraModel(name = "Osmo Nano", family = "nano"), null)
        assertEquals(
            NearbyCardCopy("Osmo Nano", "Nano · nearby · unverified", "Needs approval on the camera"),
            AppModel.nearbyCard(NearbyCamera("n2", name = "Osmo Nano", model = "Osmo Nano", routes = setOf(RouteKind.CAMERA_ACCESS_POINT)), nano),
        )
    }
}
