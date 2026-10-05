package com.opencapture.openpocketcine.lut

import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.media.MediaHTTP
import com.opencapture.opencine.media.QuickTimeKeys
import java.io.File

/**
 * iOS `ClipColorProfile`. Shot color is QuickTime Keys
 * `com.dji.camera.ColorGammaSxS` (`nclx` is Rec.709 even for D-Log2); OpenCine
 * `QuickTimeKeys` reads the file.
 */
internal object ClipColorProfile {
    const val GAMMA_KEY = "com.dji.camera.ColorGammaSxS"

    fun colorModeFromGamma(gamma: String): Int =
        when (gamma.trim()) {
            "Rec.709" -> CameraCommands.COLOR_NORMAL
            "Rec.2100 HLG" -> CameraCommands.COLOR_HDR
            "D-Log" -> CameraCommands.COLOR_DLOG
            "D-Log2" -> CameraCommands.COLOR_DLOG2
            "D-Log M", "D-LogM", "DLogM" -> CameraCommands.COLOR_DLOG_M
            else -> -1
        }

    fun colorModeFromMp4(bytes: ByteArray): Int {
        val gamma = gammaFromMp4(bytes) ?: return -1
        return colorModeFromGamma(gamma)
    }

    /** LRF / XRF / LRV Keys are Rec.709 even on D-Log2; never use them for Auto. */
    fun shotColorFromFile(file: File, path: String): Int {
        if (MediaHTTP.isProxyPath(path)) return -1
        return colorModeFromFile(file)
    }

    fun colorModeFromFile(file: File): Int =
        try {
            val window = QuickTimeKeys.tail(file) ?: return -1
            colorModeFromMp4(window)
        } catch (_: Exception) {
            -1
        }

    fun gammaFromMp4(bytes: ByteArray): String? = QuickTimeKeys.keys(bytes, GAMMA_KEY)[GAMMA_KEY]
}
