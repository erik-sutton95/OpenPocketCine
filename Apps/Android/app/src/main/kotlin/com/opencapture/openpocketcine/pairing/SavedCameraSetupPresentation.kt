package com.opencapture.openpocketcine.pairing

import com.opencapture.monitorui.MonitorConnectFailure
import com.opencapture.monitorui.MonitorConnectStep
import com.opencapture.monitorui.MonitorSetupChip
import com.opencapture.openpocketcine.core.ConnectionPhase

/** Saved-camera card values for the Wi-Fi and Hotspot setups (iOS `OsmoCameraPageAdapter`, #406). */
object SavedCameraSetupPresentation {
    /** [sessionSetup] marks the active chip while connecting or failed; otherwise the preferred one. */
    fun chips(saved: SavedCamera, sessionSetup: CameraConnectionSetup?): List<MonitorSetupChip> {
        val active = sessionSetup ?: saved.preferredSetup
        return saved.setups.map {
            MonitorSetupChip(it.raw, chipTitle(it, saved), active = it == active, canForget = it.movesCamera)
        }
    }

    fun chipTitle(setup: CameraConnectionSetup, saved: SavedCamera): String =
        saved.wifiSSID?.takeIf { setup == CameraConnectionSetup.WIFI }?.let { "Wi-Fi · $it" } ?: setup.title

    /** Every Osmo body answers the captured station sequence (#406). */
    fun canAddSetup(saved: SavedCamera, appearsInMultiview: Boolean): Boolean =
        appearsInMultiview && saved.setups.size < CameraConnectionSetup.entries.size

    /** Four steps on the connecting card: Bluetooth, network, find/handshake, picture. */
    fun steps(
        phase: ConnectionPhase,
        setup: CameraConnectionSetup,
        saved: SavedCamera,
        progress: String?,
        phaseLabel: String,
    ): List<MonitorConnectStep> {
        val network = if (setup == CameraConnectionSetup.CAMERA_WIFI) "camera Wi-Fi" else saved.ssid(setup) ?: setup.title
        val finding = progress?.startsWith("Finding") == true
        val stage = when (phase) {
            ConnectionPhase.IDLE, ConnectionPhase.SCANNING, ConnectionPhase.FAILED,
            ConnectionPhase.CONNECTING_GATT, ConnectionPhase.PAIRING, ConnectionPhase.AWAITING_APPROVAL -> 0
            ConnectionPhase.READING_WIFI_CREDS, ConnectionPhase.JOINING_WIFI -> if (finding) 2 else 1
            ConnectionPhase.OPENING_DATALINK -> 2
            ConnectionPhase.LIVE -> 4
        }
        fun state(index: Int) = when {
            index < stage -> MonitorConnectStep.State.DONE
            index == stage -> MonitorConnectStep.State.ACTIVE
            else -> MonitorConnectStep.State.WAITING
        }
        val bluetooth = when (phase) {
            ConnectionPhase.AWAITING_APPROVAL -> "Approve on the camera"
            ConnectionPhase.SCANNING -> "Looking for the camera"
            else -> ""
        }
        val camera = setup == CameraConnectionSetup.CAMERA_WIFI
        return listOf(
            MonitorConnectStep("Connecting over Bluetooth", bluetooth, state(0)),
            MonitorConnectStep(
                if (camera) "Joining camera Wi-Fi" else "Moving the camera to $network",
                if (stage == 1) progress ?: phaseLabel else "", state(1),
            ),
            MonitorConnectStep(if (camera) "Opening the video link" else "Finding the camera", "", state(2)),
            MonitorConnectStep("Starting the picture", "", state(3)),
        )
    }

    /** A failed connect stays on its card with the ways out, until the next connect. */
    fun failure(
        reason: String,
        setup: CameraConnectionSetup,
        saved: SavedCamera,
        hotspotActive: Boolean,
    ): MonitorConnectFailure {
        var message = reason.trim().replaceFirstChar { it.uppercase() }.let { if (it.endsWith(".")) it else "$it." }
        if (setup == CameraConnectionSetup.PHONE_HOTSPOT && !hotspotActive) {
            // The usual cause: the hotspot was off, so the camera had nothing to join.
            message = "The camera could not find this phone’s hotspot. Turn on the Wi-Fi hotspot, then try again."
        }
        if (!setup.movesCamera) {
            return MonitorConnectFailure(
                "Couldn’t connect over Camera Wi-Fi", message,
                listOf(MonitorConnectFailure.Action(ACTION_RETRY, "Try again", primary = true)),
            )
        }
        return MonitorConnectFailure(
            "Couldn’t connect over ${saved.ssid(setup) ?: setup.title}", message,
            listOf(
                MonitorConnectFailure.Action(ACTION_EDIT, "Edit setup"),
                MonitorConnectFailure.Action(ACTION_RETRY, "Try again", primary = true),
            ),
            link = MonitorConnectFailure.Action(ACTION_CAMERA_WIFI, "Connect over Camera Wi-Fi instead"),
        )
    }

    const val ACTION_EDIT = "edit"
    const val ACTION_RETRY = "retry"
    const val ACTION_CAMERA_WIFI = "cameraWiFi"
}
