package com.opencapture.openpocketcine.pairing

import android.content.Context
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

/**
 * How a saved body is reached (iOS `CameraConnectionSetup`, #406). Every record has camera
 * Wi-Fi. Wi-Fi (a router) and Hotspot (this phone's) are OpenZCine-style extra setups that
 * move the camera off its own access point onto that network. [raw] matches iOS.
 */
enum class CameraConnectionSetup(val raw: String, val title: String) {
    CAMERA_WIFI("cameraWiFi", "Camera Wi-Fi"),
    WIFI("wifi", "Wi-Fi"),
    PHONE_HOTSPOT("phoneHotspot", "Hotspot");

    /** The camera leaves its access point (station role) for this setup. */
    val movesCamera: Boolean get() = this != CAMERA_WIFI

    companion object {
        fun fromRaw(raw: String?): CameraConnectionSetup? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * One Pocket body; its setups are chips on the saved-camera row.
 * SharedPreferences file `openpocketcine.saved-cameras`, key `records-json`.
 */
data class SavedCamera(
    val id: String,
    val advertisedName: String,
    val modelName: String,
    val lastSSID: String?,
    val lastConnectedAt: Long,
    val customName: String? = null,
    /** Network names for the Wi-Fi and Hotspot setups; null means not added. Passwords stay in [com.opencapture.openpocketcine.multiview.MultiviewNetworkStore]. */
    val wifiSSID: String? = null,
    val hotspotSSID: String? = null,
    /**
     * Last setup a connect started with. A setup that moves the camera also means it may
     * still be in station role, so the next camera Wi-Fi connect restores its access point.
     */
    val lastSetup: CameraConnectionSetup? = null,
) {
    val displayName: String
        get() {
            val custom = customName?.trim().orEmpty()
            if (custom.isNotEmpty()) return custom
            return advertisedName.ifEmpty { modelName }
        }

    fun ssid(setup: CameraConnectionSetup): String? = when (setup) {
        CameraConnectionSetup.CAMERA_WIFI -> lastSSID
        CameraConnectionSetup.WIFI -> wifiSSID
        CameraConnectionSetup.PHONE_HOTSPOT -> hotspotSSID
    }

    val setups: List<CameraConnectionSetup>
        get() = CameraConnectionSetup.entries.filter {
            it == CameraConnectionSetup.CAMERA_WIFI || ssid(it) != null
        }

    /** The row's main Connect: the last setup used, when it still exists. */
    val preferredSetup: CameraConnectionSetup
        get() = lastSetup?.takeIf { it in setups } ?: CameraConnectionSetup.CAMERA_WIFI
}

object SavedCameras {
    fun upserting(camera: SavedCamera, into: List<SavedCamera>): List<SavedCamera> {
        var merged = camera
        into.firstOrNull { it.id == camera.id }?.let { existing ->
            if (merged.customName == null) merged = merged.copy(customName = existing.customName)
            if (merged.lastSSID == null) merged = merged.copy(lastSSID = existing.lastSSID)
            if (merged.advertisedName.isEmpty()) {
                merged = merged.copy(advertisedName = existing.advertisedName)
            }
            if (merged.wifiSSID == null) merged = merged.copy(wifiSSID = existing.wifiSSID)
            if (merged.hotspotSSID == null) merged = merged.copy(hotspotSSID = existing.hotspotSSID)
            if (merged.lastSetup == null) merged = merged.copy(lastSetup = existing.lastSetup)
        }
        return canonicalized(listOf(merged) + into.filter { it.id != camera.id })
    }

    fun removing(id: String, from: List<SavedCamera>): List<SavedCamera> =
        canonicalized(from.filter { it.id != id })

    fun renaming(id: String, name: String?, inRecords: List<SavedCamera>): List<SavedCamera> {
        val trimmed = name?.trim()
        val custom = trimmed?.takeIf { it.isNotEmpty() }
        return canonicalized(
            inRecords.map { record ->
                if (record.id == id) record.copy(customName = custom) else record
            }
        )
    }

    /**
     * Add, change or forget (null/blank) a Wi-Fi or Hotspot setup. `lastSetup` is kept: a
     * camera left in station role still needs its access point restored.
     */
    fun setting(
        setup: CameraConnectionSetup, ssid: String?, id: String, inRecords: List<SavedCamera>,
    ): List<SavedCamera> {
        val value = ssid?.trim()?.takeIf { it.isNotEmpty() }
        return canonicalized(
            inRecords.map { record ->
                if (record.id != id) return@map record
                when (setup) {
                    CameraConnectionSetup.CAMERA_WIFI -> record
                    CameraConnectionSetup.WIFI -> record.copy(wifiSSID = value)
                    CameraConnectionSetup.PHONE_HOTSPOT -> record.copy(hotspotSSID = value)
                }
            }
        )
    }

    /**
     * Stamp the setup a connect starts with. One that moves the camera is stamped before
     * it can change the station role (a lost setter reply can still mean the role
     * changed). Camera Wi-Fi is stamped only once live, so a failed restore is retried on
     * the next connect.
     */
    fun stamping(setup: CameraConnectionSetup, id: String, inRecords: List<SavedCamera>): List<SavedCamera> =
        inRecords.map { if (it.id == id) it.copy(lastSetup = setup) else it }

    fun canonicalized(records: List<SavedCamera>): List<SavedCamera> {
        val seen = linkedSetOf<String>()
        val unique = mutableListOf<SavedCamera>()
        for (record in records) {
            if (seen.add(record.id)) unique.add(record)
        }
        return unique.sortedByDescending { it.lastConnectedAt }
    }

    fun launchShowsWizard(records: List<SavedCamera>): Boolean = canonicalized(records).isEmpty()
}

class SharedPreferencesSavedCameraStore(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): List<SavedCamera> {
        val raw = prefs.getString(RECORDS_KEY, null) ?: return emptyList()
        return runCatching { decode(raw) }.getOrElse { emptyList() }.let(SavedCameras::canonicalized)
    }

    fun save(records: List<SavedCamera>) {
        val canonical = SavedCameras.canonicalized(records)
        prefs.edit { putString(RECORDS_KEY, encode(canonical)) }
    }

    companion object {
        const val PREFERENCES_NAME = "openpocketcine.saved-cameras"
        const val RECORDS_KEY = "records-json"

        fun encode(records: List<SavedCamera>): String {
            val array = JSONArray()
            for (record in records) {
                array.put(
                    JSONObject().apply {
                        put("id", record.id)
                        put("advertisedName", record.advertisedName)
                        put("modelName", record.modelName)
                        if (record.lastSSID != null) put("lastSSID", record.lastSSID)
                        put("lastConnectedAt", record.lastConnectedAt)
                        if (record.customName != null) put("customName", record.customName)
                        if (record.wifiSSID != null) put("wifiSSID", record.wifiSSID)
                        if (record.hotspotSSID != null) put("hotspotSSID", record.hotspotSSID)
                        if (record.lastSetup != null) put("lastSetup", record.lastSetup.raw)
                    }
                )
            }
            return array.toString()
        }

        fun decode(raw: String): List<SavedCamera> {
            val array = JSONArray(raw)
            val out = mutableListOf<SavedCamera>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val id = obj.optString("id")
                if (id.isEmpty()) continue
                out.add(
                    SavedCamera(
                        id = id,
                        advertisedName = obj.optString("advertisedName"),
                        modelName = obj.optString("modelName"),
                        lastSSID = obj.optString("lastSSID").takeIf { it.isNotEmpty() && obj.has("lastSSID") },
                        lastConnectedAt = obj.optLong("lastConnectedAt", 0L),
                        customName = obj.optString("customName").takeIf { it.isNotEmpty() && obj.has("customName") },
                        wifiSSID = obj.optString("wifiSSID").takeIf { it.isNotEmpty() && obj.has("wifiSSID") },
                        hotspotSSID = obj.optString("hotspotSSID").takeIf { it.isNotEmpty() && obj.has("hotspotSSID") },
                        lastSetup = CameraConnectionSetup.fromRaw(obj.optString("lastSetup")),
                    )
                )
            }
            return out
        }
    }
}
