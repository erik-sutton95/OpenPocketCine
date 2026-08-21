package com.opencapture.openpocketcine.pairing

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.SecretKey

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
        preferences.edit()
            .putString("$cameraId.ssid", ssid)
            .putString("$cameraId.password", sealed)
            .putString(ssidEntry(ssid), sealed)
            .apply()
    }

    fun remove(cameraId: String) {
        val ssid = preferences.getString("$cameraId.ssid", null)
        val editor = preferences.edit().remove("$cameraId.ssid").remove("$cameraId.password")
        if (!ssid.isNullOrEmpty()) editor.remove(ssidEntry(ssid))
        editor.apply()
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

    private fun encrypt(passphrase: String): String? =
        runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, keystoreEntry())
            val sealed = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP) +
                SEPARATOR +
                Base64.encodeToString(sealed, Base64.NO_WRAP)
        }.getOrNull()

    private fun decrypt(stored: String): String? {
        val parts = stored.split(SEPARATOR, limit = 2)
        if (parts.size != 2) return null
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, keystoreEntry(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
        }.getOrNull()
    }

    private fun ssidEntry(ssid: String): String = "ssid:" + ssid.trim()

    private fun keystoreEntry(): SecretKey {
        val keystore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keystore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                    ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val PREFS = "openpocketcine.camera-wifi"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "openpocketcine.camera-wifi"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val SEPARATOR = ":"
    }
}
