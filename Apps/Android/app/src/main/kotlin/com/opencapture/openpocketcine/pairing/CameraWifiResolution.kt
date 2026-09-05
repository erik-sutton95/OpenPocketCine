package com.opencapture.openpocketcine.pairing

/** Cached SoftAP creds vs a live BLE name. Lockstep with Swift `CameraWifiResolution`. */
object CameraWifiResolution {
    data class Result(
        val ssid: String?,
        val password: String?,
        val source: String,
        val skipBle: Boolean,
    )

    fun liveAdvertisedSSID(name: String?): String? {
        val trimmed = name?.trim().orEmpty()
        if (trimmed.isEmpty() || FoundCameraIdentity.isGenericName(trimmed)) return null
        return trimmed
    }

    fun resolve(
        cameraId: String,
        savedSSID: String?,
        memoryCameraId: String?,
        memorySsid: String?,
        memoryPassword: String?,
        keychainSsid: String?,
        keychainPassword: String?,
        advertisedName: String? = null,
    ): Result {
        val memoryMatches = memoryCameraId == cameraId
        val memSsid = if (memoryMatches) memorySsid else null
        val memPass = if (memoryMatches) memoryPassword else null
        val cachedSsid =
            listOf(memSsid, keychainSsid, savedSSID)
                .mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
                .firstOrNull()
        val password =
            listOf(memPass, keychainPassword)
                .mapNotNull { it?.takeIf(String::isNotEmpty) }
                .firstOrNull()
        val live = liveAdvertisedSSID(advertisedName)
        val ssid =
            if (live != null && cachedSsid != null && live != cachedSsid) live else cachedSsid
        val memoryHit = memoryMatches && !memSsid.isNullOrEmpty() && !memPass.isNullOrEmpty()
        val keychainHit = !keychainSsid.isNullOrEmpty() && !keychainPassword.isNullOrEmpty()
        val source =
            when {
                memoryHit -> "memory"
                keychainHit -> "keychain"
                else -> "none"
            }
        val skipBle =
            !password.isNullOrEmpty() && !ssid.isNullOrEmpty() && (memoryHit || keychainHit)
        return Result(ssid = ssid, password = password, source = source, skipBle = skipBle)
    }
}
