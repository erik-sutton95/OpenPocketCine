package com.opencapture.openpocketcine.pairing

import android.content.Context
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

/**
 * One Pocket body. Pocket has a single BLE → camera-AP path — no OpenZCine setups.
 * SharedPreferences file `openpocketcine.saved-cameras`, key `records-json`.
 */
data class SavedCamera(
    val id: String,
    val advertisedName: String,
    val modelName: String,
    val lastSSID: String?,
    val lastConnectedAt: Long,
    val customName: String? = null,
) {
    val displayName: String
        get() {
            val custom = customName?.trim().orEmpty()
            if (custom.isNotEmpty()) return custom
            return advertisedName.ifEmpty { modelName }
        }
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
                    )
                )
            }
            return out
        }
    }
}
