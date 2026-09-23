package com.opencapture.openpocketcine.multiview

import android.content.Context
import androidx.core.content.edit
import com.opencapture.openpocketcine.pairing.KeystoreSeal
import org.json.JSONArray
import org.json.JSONObject

/**
 * Saved shared networks. iOS `MultiviewNetworkStore`: names in private prefs,
 * passwords sealed with a device-only Keystore key. Never log a password.
 */
class MultiviewNetworkStore(context: Context) {
    data class Network(val ssid: String, val password: String, val hotspot: Boolean)

    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val seal = KeystoreSeal(ALIAS)

    fun savedNetworks(): List<Network> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        val list = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        return (0 until list.length()).mapNotNull { index ->
            val item = list.optJSONObject(index) ?: return@mapNotNull null
            val ssid = item.optString("ssid")
            val password = item.optString("password").takeIf { it.isNotEmpty() }?.let(seal::open) ?: ""
            if (ssid.isEmpty()) null else Network(ssid, password, item.optBoolean("hotspot"))
        }
    }

    fun load(ssid: String, hotspot: Boolean): Network? =
        savedNetworks().firstOrNull { it.ssid == ssid && it.hotspot == hotspot }

    fun save(ssid: String, password: String, hotspot: Boolean) {
        val sealed = if (password.isEmpty()) "" else seal.seal(password) ?: return
        val others = savedNetworks().filterNot { it.ssid == ssid && it.hotspot == hotspot }
        val list = JSONArray()
        for (network in others) {
            list.put(entry(network.ssid, network.password.let { if (it.isEmpty()) "" else seal.seal(it) ?: "" }, network.hotspot))
        }
        list.put(entry(ssid, sealed, hotspot))
        prefs.edit { putString(KEY, list.toString()) }
    }

    private fun entry(ssid: String, sealed: String, hotspot: Boolean) =
        JSONObject().put("ssid", ssid).put("password", sealed).put("hotspot", hotspot)

    private companion object {
        const val PREFS = "openpocketcine.multiview-network"
        const val ALIAS = "openpocketcine.multiview-network"
        const val KEY = "saved-networks"
    }
}

/** Device-only stage metadata and camera-Wi-Fi cleanup ledger. Credentials stay in [MultiviewNetworkStore]. */
object MultiviewStageStore {
    data class Camera(
        val slot: Int,
        val id: String,
        val name: String,
        val modelId: Int?,
        /** BLE MAC; Android reconnects by address where iOS uses the peripheral UUID. */
        val bleAddress: String,
        val identity: ByteArray?,
        val address: String,
        val experimental: Boolean,
        val lutEnabled: Boolean,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Camera && slot == other.slot && id == other.id && name == other.name &&
                modelId == other.modelId && bleAddress == other.bleAddress &&
                identity.contentEqualsNullable(other.identity) && address == other.address &&
                experimental == other.experimental && lutEnabled == other.lutEnabled

        override fun hashCode(): Int = id.hashCode()
    }

    data class Stage(
        val version: Int = 1,
        val ssid: String,
        val hotspot: Boolean,
        val layout: String,
        val focusedIndex: Int,
        val cameras: List<Camera>,
        val pendingReset: List<Camera>? = null,
        val returnedToCameraWiFi: Boolean? = null,
        val fill: Boolean? = null,
    ) {
        val validated: Stage?
            get() {
                val cleanup = pendingReset.orEmpty()
                val valid = version == 1 &&
                    (ssid.isNotEmpty() || (cameras.isEmpty() && cleanup.isNotEmpty())) &&
                    cameras.size <= 4 && focusedIndex in 0..3 &&
                    cameras.map { it.slot }.toSet().size == cameras.size &&
                    cameras.map { it.id }.toSet().size == cameras.size &&
                    cleanup.map { it.id }.toSet().size == cleanup.size &&
                    cleanup.all { it.name.isNotEmpty() } &&
                    cameras.all { it.slot in 0..3 && it.name.isNotEmpty() }
                return if (valid) this else null
            }
    }

    fun cleanupTargets(pending: List<Camera>, including: List<Camera>): List<Camera> {
        val result = pending.toMutableList()
        for (camera in including) {
            val index = result.indexOfFirst { it.id == camera.id }
            if (index >= 0) result[index] = camera else result += camera
        }
        return result
    }

    fun load(context: Context): Stage? =
        prefs(context).getString(KEY, null)?.let(::decode)

    fun save(context: Context, stage: Stage?): Boolean {
        if (stage == null) {
            prefs(context).edit { remove(KEY) }
            return true
        }
        if (stage.validated == null) return false
        prefs(context).edit(commit = true) { putString(KEY, encode(stage)) }
        return true
    }

    fun encode(stage: Stage): String =
        JSONObject()
            .put("version", stage.version)
            .put("ssid", stage.ssid)
            .put("hotspot", stage.hotspot)
            .put("layout", stage.layout)
            .put("focusedIndex", stage.focusedIndex)
            .put("cameras", JSONArray(stage.cameras.map(::encodeCamera)))
            .apply {
                stage.pendingReset?.let { put("pendingReset", JSONArray(it.map(::encodeCamera))) }
                stage.returnedToCameraWiFi?.let { put("returnedToCameraWiFi", it) }
                stage.fill?.let { put("fill", it) }
            }
            .toString()

    fun decode(raw: String): Stage? =
        runCatching {
            val json = JSONObject(raw)
            Stage(
                version = json.getInt("version"),
                ssid = json.getString("ssid"),
                hotspot = json.getBoolean("hotspot"),
                layout = json.getString("layout"),
                focusedIndex = json.getInt("focusedIndex"),
                cameras = cameras(json.getJSONArray("cameras")),
                pendingReset = json.optJSONArray("pendingReset")?.let(::cameras),
                returnedToCameraWiFi = if (json.has("returnedToCameraWiFi")) json.getBoolean("returnedToCameraWiFi") else null,
                fill = if (json.has("fill")) json.getBoolean("fill") else null,
            ).validated
        }.getOrNull()

    private fun cameras(array: JSONArray): List<Camera> =
        (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            Camera(
                slot = item.getInt("slot"),
                id = item.getString("id"),
                name = item.getString("name"),
                modelId = if (item.has("modelId")) item.getInt("modelId") else null,
                bleAddress = item.optString("bleAddress"),
                identity = item.optString("identity").takeIf { it.isNotEmpty() }?.let(::unhex),
                address = item.optString("address"),
                experimental = item.optBoolean("experimental"),
                lutEnabled = item.optBoolean("lutEnabled"),
            )
        }

    private fun encodeCamera(camera: Camera): JSONObject =
        JSONObject()
            .put("slot", camera.slot)
            .put("id", camera.id)
            .put("name", camera.name)
            .put("bleAddress", camera.bleAddress)
            .put("address", camera.address)
            .put("experimental", camera.experimental)
            .put("lutEnabled", camera.lutEnabled)
            .apply {
                camera.modelId?.let { put("modelId", it) }
                camera.identity?.let { put("identity", hex(it)) }
            }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private const val PREFS = "openpocketcine.multiview-stage"
    private const val KEY = "stage"
}

internal fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }

internal fun unhex(value: String): ByteArray? {
    if (value.length % 2 != 0) return null
    return runCatching { ByteArray(value.length / 2) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() } }.getOrNull()
}

private fun ByteArray?.contentEqualsNullable(other: ByteArray?): Boolean =
    if (this == null) other == null else other != null && contentEquals(other)
