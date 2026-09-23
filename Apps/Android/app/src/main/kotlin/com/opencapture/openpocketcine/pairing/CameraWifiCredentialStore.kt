package com.opencapture.openpocketcine.pairing

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * Encrypted-at-rest camera Wi-Fi keys — Android counterpart of iOS
 * `CameraWifiKeychain`. Pattern from OpenZCine `CameraWifiCredentialStore`:
 * AES/GCM with a non-exportable Android Keystore key. Jetpack Security's
 * `EncryptedSharedPreferences` is abandoned; Keystore is the supported route.
 *
 * Passwords are never written into saved-camera JSON and must never be logged.
 */
class CameraWifiCredentialStore(context: Context) {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val seal = KeystoreSeal(ALIAS)

    fun load(cameraId: String): Pair<String, String>? {
        val ssid = preferences.getString("$cameraId.ssid", null) ?: return null
        val sealed = preferences.getString("$cameraId.password", null) ?: return null
        if (ssid.isEmpty() || sealed.isEmpty()) return null
        val password = decryptOrMigrate(cameraId, sealed) ?: return null
        if (password.isEmpty()) return null
        return ssid to password
    }

    fun passphrase(ssid: String): String? {
        val stored = preferences.getString(ssidEntry(ssid), null) ?: return null
        return decrypt(stored)
    }

    fun save(cameraId: String, ssid: String, password: String) {
        val sealed = encrypt(password) ?: return
        preferences.edit {
            putString("$cameraId.ssid", ssid)
            putString("$cameraId.password", sealed)
            putString(ssidEntry(ssid), sealed)
        }
    }

    fun remove(cameraId: String) {
        val ssid = preferences.getString("$cameraId.ssid", null)
        // `this.` is load-bearing: the store has its own remove(String), and a bare
        // call here would read as recursion to anyone skimming the block.
        preferences.edit {
            this.remove("$cameraId.ssid")
            this.remove("$cameraId.password")
            if (!ssid.isNullOrEmpty()) this.remove(ssidEntry(ssid))
        }
    }

    private fun decryptOrMigrate(cameraId: String, stored: String): String? {
        decrypt(stored)?.let { return it }
        // Legacy plaintext from the first Android session cache.
        if (SEPARATOR !in stored) {
            save(cameraId, preferences.getString("$cameraId.ssid", "") ?: return null, stored)
            return stored
        }
        return null
    }

    private fun encrypt(passphrase: String): String? = seal.seal(passphrase)

    private fun decrypt(stored: String): String? = seal.open(stored)

    private fun ssidEntry(ssid: String): String = "ssid:" + ssid.trim()

    private companion object {
        const val PREFS = "openpocketcine.camera-wifi"
        const val ALIAS = "openpocketcine.camera-wifi"
        const val SEPARATOR = KeystoreSeal.SEPARATOR
    }
}
