package com.opencapture.openpocketcine

import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.ConnectionFailure
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.dji.CameraConnectionSetup
import com.opencapture.opencine.dji.DjiConnectPort
import com.opencapture.opencine.dji.DjiFailures
import com.opencapture.opencine.dji.MultiviewNetworkStore
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.openpocketcine.pairing.AddSetupSlot
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * Debug review only ([ReviewActivity] `opv_review_state`): a scripted DJI pipeline and
 * the two saved cameras as the shipping app stored them, so the cameras and pair pages show each
 * connection state on an emulator. Never connects, never stores a credential. States: `empty`,
 * `saved-nearby`, `connecting`, `failure`, `add-setup`, `multiview`, `pair-choose`,
 * `pair-approve`, `pair-join`, `pair-video`, `pair-failure`, `pair-bluetooth`.
 */
internal object ReviewCameras {
    private const val STUDIO = "00000000-0000-0000-0000-000000000001"
    private const val NEW = "00000000-0000-0000-0000-000000000003"

    fun seed(state: String?, legacy: SharedPreferences) {
        state ?: return
        val records = JSONArray()
        if (state != "empty") {
            records.put(
                JSONObject().put("id", STUDIO).put("advertisedName", "Studio camera").put("modelName", "Osmo Pocket 4 Pro")
                    .put("lastConnectedAt", 1_000L).put("wifiSSID", "Studio-5G").put("hotspotSSID", "Rig phone"),
            )
            records.put(
                JSONObject().put("id", "00000000-0000-0000-0000-000000000002").put("advertisedName", "Travel camera")
                    .put("modelName", "Osmo Nano").put("lastConnectedAt", 500L),
            )
        }
        legacy.edit { putString("records-json", records.toString()) }
    }

    fun port(state: String, session: DjiCameraSession): DjiConnectPort = Port(state, session.control)

    /** Starts the attempt the state shows, once the scripted sightings are listed. */
    suspend fun start(state: String?, model: AppModel) {
        val cameras = model.cameras
        when (state) {
            "connecting", "failure" -> cameras.state.value.saved.firstOrNull { it.id == STUDIO }?.let { studio ->
                val route = studio.routes.firstOrNull { it.kind == RouteKind.INFRASTRUCTURE_NETWORK }?.id
                cameras.connect(studio, if (state == "connecting") route else null)
            }
            "pair-approve", "pair-join", "pair-video", "pair-failure" -> {
                while (cameras.state.value.nearby.none { it.id == NEW }) delay(20)
                cameras.select(NEW)
                cameras.state.value.nearby.firstOrNull { it.id == NEW }?.let(cameras::connect)
            }
        }
    }

    /** The add-route slot as the cameras page presents it. */
    @Composable
    fun AddSetup(state: String?, model: AppModel) {
        var open by remember { mutableStateOf(state == "add-setup") }
        val camera = model.cameras.state.collectAsState().value.saved.firstOrNull { it.id == STUDIO }
        if (open && camera != null) AddSetupSlot(model, camera) { open = false }
    }

    private class Port(private val state: String, override val control: CameraSession) : DjiConnectPort {
        override val found = MutableStateFlow<List<FoundCamera>>(emptyList())
        override val phaseFlow = MutableStateFlow(ConnectionPhase.IDLE)
        override val setupProgress = MutableStateFlow<String?>(null)
        override val failureDetail = MutableStateFlow<ConnectionFailure?>(null)
        override val joinedSSID: String? = null

        override fun startScan() {
            if (state in setOf("empty", "connecting", "pair-bluetooth")) return
            val studio = FoundCamera(STUDIO, "AA", "Studio camera", CameraModel(name = "Osmo Pocket 4 Pro", verified = true), 0x22)
            val fresh = FoundCamera(NEW, "BB", "OsmoPocket3-4D5E", CameraModel(name = "Osmo Pocket 3", verified = true), 0x20)
            found.value = if (state.startsWith("pair-") && state != "pair-choose") listOf(fresh) else listOf(studio, fresh)
        }

        override fun stopScan() {}

        override fun useSetup(setup: CameraConnectionSetup, network: MultiviewNetworkStore.Network?, restoreAccessPoint: Boolean) {}

        override fun reconnect(id: String) {
            when (state) {
                "connecting" -> {
                    setupProgress.value = "Joining Studio-5G on this phone"
                    phaseFlow.value = ConnectionPhase.JOINING_WIFI
                }
                "failure", "pair-failure" -> {
                    failureDetail.value = DjiFailures.classify(null, ConnectionPhase.OPENING_DATALINK, "camera never answered the datalink handshake")
                    phaseFlow.value = ConnectionPhase.FAILED
                }
                "pair-approve" -> phaseFlow.value = ConnectionPhase.AWAITING_APPROVAL
                "pair-join" -> phaseFlow.value = ConnectionPhase.JOINING_WIFI
                "pair-video" -> phaseFlow.value = ConnectionPhase.OPENING_DATALINK
            }
        }

        override fun disconnect() {
            phaseFlow.value = ConnectionPhase.IDLE
        }
    }
}
