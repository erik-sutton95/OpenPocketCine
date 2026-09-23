package com.opencapture.openpocketcine.pairing

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES/GCM with a non-exportable Android Keystore key: the device-only
 * counterpart of an iOS `...ThisDeviceOnly` Keychain item. Never log inputs.
 */
internal class KeystoreSeal(private val alias: String) {
    fun seal(secret: String): String? =
        runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP) +
                SEPARATOR +
                Base64.encodeToString(sealed, Base64.NO_WRAP)
        }.getOrNull()

    fun open(stored: String): String? {
        val parts = stored.split(SEPARATOR, limit = 2)
        if (parts.size != 2) return null
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
        }.getOrNull()
    }

    private fun key(): SecretKey {
        val keystore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keystore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    companion object {
        const val SEPARATOR = ":"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
