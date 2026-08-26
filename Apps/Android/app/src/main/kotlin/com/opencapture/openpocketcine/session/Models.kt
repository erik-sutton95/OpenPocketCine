package com.opencapture.openpocketcine.session

import org.json.JSONArray
import org.json.JSONObject

data class CameraModel(
    val name: String,
    val datalinkPort: Int = 9004,
    val tcpPoke: Boolean = true,
    val wpa3: Boolean = false,
    val verified: Boolean = false,
    val isDrone: Boolean = false,
    val pairingToken: String = "osmo",
    /** `"pocket"` / `"nano"` / `"other"`. Missing JSON defaults to Pocket. */
    val family: String = "pocket",
    /** `0x09/0xa8` receiver. Pocket `0x08`; Nano `0x41`. */
    val liveViewEnableReceiver: Int = 0x08,
    val usesNanoLiveViewGate: Boolean = false,
    val supportsTapFocus: Boolean = true,
    val supportsFocusMode: Boolean = true,
    val usesCapturedLiveEnable: Boolean = true,
) {
    companion object {
        val default = CameraModel(name = "DJI Osmo camera")

        fun fromJson(raw: String?): CameraModel {
            if (raw.isNullOrBlank()) return default
            return runCatching {
                val obj = JSONObject(raw)
                CameraModel(
                    name = obj.optString("name", default.name),
                    datalinkPort = obj.optInt("datalinkPort", 9004),
                    tcpPoke = obj.optBoolean("tcpPoke", true),
                    wpa3 = obj.optBoolean("wpa3", false),
                    verified = obj.optBoolean("verified", false),
                    isDrone = obj.optBoolean("isDrone", false),
                    pairingToken = obj.optString("pairingToken", "osmo"),
                    family = obj.optString("family", "pocket").ifBlank { "pocket" },
                    liveViewEnableReceiver = obj.optInt("liveViewEnableReceiver", 0x08),
                    usesNanoLiveViewGate = obj.optBoolean("usesNanoLiveViewGate", false),
                    supportsTapFocus = obj.optBoolean("supportsTapFocus", true),
                    supportsFocusMode = obj.optBoolean("supportsFocusMode", true),
                    usesCapturedLiveEnable = obj.optBoolean("usesCapturedLiveEnable", true),
                )
            }.getOrElse { default }
        }
    }
}

data class FoundCamera(
    val id: String,
    val address: String,
    val name: String,
    val model: CameraModel,
    val modelId: Int?,
)

data class DumlFrame(
    val sender: Int,
    val receiver: Int,
    val seq: Int,
    val flags: Int,
    val cmdSet: Int,
    val cmdId: Int,
    val payload: ByteArray,
) {
    val key: Int get() = ((cmdSet and 0xFF) shl 8) or (cmdId and 0xFF)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DumlFrame) return false
        return sender == other.sender &&
            receiver == other.receiver &&
            seq == other.seq &&
            flags == other.flags &&
            cmdSet == other.cmdSet &&
            cmdId == other.cmdId &&
            payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int =
        sender * 31 + receiver + seq + flags + cmdSet + cmdId + payload.contentHashCode()
}

data class CameraStatus(
    val batteryPercent: Int = -1,
    val batteryMilliVolts: Int = 0,
    val batteryMilliAmps: Int = 0,
    val docked: Boolean = false,
    val charging: Boolean = false,
    val storageTotalMb: Int = 0,
    val storageFreeMb: Int = 0,
    val sdTotalMb: Int = 0,
    val sdFreeMb: Int = 0,
    val internalTotalMb: Int = -1,
    val internalFreeMb: Int = -1,
    val inPlayback: Boolean = false,
    val firmware: String? = null,
    val isRecording: Boolean = false,
    val shootingMode: Int = -1,
    val recordElapsedSec: Int = 0,
    val recordRemainingSec: Int = 0,
    val timecode: String? = null,
    val iso: Int = -1,
    val shutterDenom: Int = -1,
    val fps: Int = 0,
    /** `cam_expo_param` `@7` — `01` auto / `04` manual. `-1` unknown. */
    val expoMode: Int = -1,
    /** `cam_expo_param` `@5` ISO index (`00` Auto, `03`=100 … `0B`=25600). `-1` unknown. */
    val isoIndex: Int = -1,
    /** `cam_image_effect` `@2` — `3F` Normal, `3C` HDR, `17` D-Log, `41` D-Log2. `-1` unknown. */
    val colorMode: Int = -1,
    /** `cam_video_param_v2` `@0` — `0A` 1080p / `10` 4K. `-1` unknown. */
    val resolutionCode: Int = -1,
    /** `cam_video_param_v2` `@1` fps index. `-1` unknown. */
    val fpsIndex: Int = -1,
    /** `cam_image_effect` `@4` — `00` Auto / `06` Custom. `-1` unknown. */
    val wbMode: Int = -1,
    val wbKelvin: Int = -1,
    val wbTint: Int = 0,
    /** `01` Single / `02` Continuous from `cam_lens_state` `@0` `B1`/`B2`. `-1` unknown. */
    val focusMode: Int = -1,
    /** `0x8E` pid `0x0020` — `01` Mono / `02` Stereo / `03` Spatial. `-1` unknown. */
    val audioChannel: Int = -1,
    /** Wind NR from audio DSP blob `@2` (`1A` on / `18` off). `-1` unknown. */
    val windNr: Int = -1,
    /** Directional from the same `@2` (`0` All / `1` Front / `2` Front+back). `-1` unknown. */
    val directionalAudio: Int = -1,
    /** Vocal Boost `0x8E` pid `0x004C` — `00` off / `01` on. `-1` unknown. */
    val vocalBoost: Int = -1,
    /** Last `0xA0` GET blob as lowercase hex. Empty means we have not GETted yet. */
    val audioDspBlob: String = "",
    /** Shared audio-DSP `@2`. `-1` unknown. */
    val audioDspAt2: Int = -1,
    /** `cam_fov` u32-LE `@0`. 0 = unknown. 12287 is operator 1×, not 12×. */
    val zoomFactorRaw: Int = 0,
    /** Legal 1/N denoms from `camcap_shutter`, camera order. */
    val availableShutterDenoms: List<Int> = emptyList(),
    /** Legal ISO indices from `camcap_iso`. */
    val availableIsoIndices: List<Int> = emptyList(),
    /** `cam_expo_param` `@6` EV raw (`0x10` = 0.0). `-1` unknown. */
    val evComp: Int = -1,
    /** `0x8E` pid `0x000F` Auto ISO ceiling. `-1` unknown. */
    val isoLimit: Int = -1,
    /** Legal `0x02/0x42` values from `camcap_color_mode`. */
    val availableColorModes: List<Int> = emptyList(),
    /** AF point from `cam_lens_state`. 0.5, 0.5 until a tap. */
    val focusX: Double = 0.5,
    val focusY: Double = 0.5,
    val hasCameraFocusPoint: Boolean = false,
    /** `0x8E` pid `0x003B` AF-C track. `-1` unknown. */
    val focusTrack: Int = -1,
    /** `cam_lens_state` u16-LE `@14`. `-1` unknown. */
    val zoomLens: Int = -1,
    /** Hybrid zoom (1.0×…12×). Null until lens/`cam_fov` lands. */
    val zoomFactor: Double? = null,
    /** Last `0x8E` pid `0x0039` blob `@5` non-zero. Null unknown. */
    val glamourEnabled: Boolean? = null,
    /** `0x8E` pid `0x0038` (`00`/`01`). Control Center Selfie Flip. */
    val selfieFlip: Boolean? = null,
    /** `0x04/0x27` `@2` bit `0x40`. `0` front / `1` selfie / `-1` unknown. */
    val gimbalFace: Int = CameraCommands.GIMBAL_FACE_UNKNOWN,
    /** Live VU from `cam_audio_status_v2`, dBFS. Floor is −60. */
    val audioMetersLeft: Double = -60.0,
    val audioMetersRight: Double = -60.0,
    val audioPeakLeft: Double = -60.0,
    val audioPeakRight: Double = -60.0,
) {
    val shootingModeLabel: String
        get() =
            when (shootingMode) {
                0x00 -> "SlowMo"
                0x01 -> "Video"
                0x02 -> "TimeLapse"
                0x05, 0x17 -> "Photo"
                0x0A -> "HyperLapse"
                0x28 -> "SuperNight"
                -1 -> if (inPlayback) "Playback" else "Capture"
                else -> "0x%02X".format(shootingMode)
            }

    val expoLabel: String
        get() =
            when (expoMode) {
                CameraCommands.EXPO_AUTO -> "Auto"
                CameraCommands.EXPO_MANUAL -> "Manual"
                else -> "—"
            }

    val isoLabel: String
        get() =
            when {
                isoIndex == 0 -> "Auto"
                iso > 0 -> "$iso"
                else -> "—"
            }

    val shutterLabel: String
        get() = if (shutterDenom > 0) "1/$shutterDenom" else "—"

    val colorLabel: String
        get() = CameraCommands.colorLabel(colorMode)

    val resolutionLabel: String
        get() = CameraCommands.resolutionLabel(resolutionCode)

    val recFormatLabel: String
        get() = VideoFormat.chipLabel(this)

    val videoFormat: VideoFormat?
        get() = VideoFormat.parse(resolutionCode, fpsIndex)

    val wbLabel: String
        get() =
            when {
                wbMode == CameraCommands.WB_AUTO -> "Auto"
                wbKelvin > 0 -> "${wbKelvin}K"
                else -> "—"
            }

    val focusLabel: String
        get() = FocusOption.resolve(focusMode, focusTrack)?.chip ?: "—"

    val audioLabel: String
        get() = CameraCommands.audioChannelLabel(audioChannel) ?: "—"

    val hasHudFields: Boolean
        get() =
            expoMode >= 0 ||
                isoIndex >= 0 ||
                colorMode >= 0 ||
                resolutionCode >= 0 ||
                wbMode >= 0 ||
                focusMode >= 0 ||
                audioChannel >= 0 ||
                audioDspBlob.isNotEmpty() ||
                zoomFactorRaw > 0 ||
                evComp >= 0 ||
                isoLimit >= 0 ||
                availableColorModes.isNotEmpty() ||
                hasCameraFocusPoint ||
                focusTrack >= 0 ||
                zoomLens >= 0 ||
                zoomFactor != null ||
                glamourEnabled != null ||
                selfieFlip != null

    val storageLabel: String
        get() {
            val total = if (sdTotalMb > 0) sdTotalMb else storageTotalMb
            val free = if (sdTotalMb > 0) sdFreeMb else storageFreeMb
            if (total <= 0) return "—"
            val gb = free / 1024
            val pct = ((free.toLong() * 100L) / total).toInt().coerceIn(0, 100)
            return "$gb GB · $pct%"
        }

    fun applyingAudioByte2(raw: Int): CameraStatus {
        val wind = CameraCommands.windFrom(raw)
        val dir = CameraCommands.directionalFrom(raw)
        return copy(
            audioDspAt2 = raw,
            windNr = if (wind >= 0) wind else windNr,
            directionalAudio = if (dir >= 0) dir else directionalAudio,
        )
    }

    fun applyingAudioBlob(blob: ByteArray): CameraStatus {
        if (blob.size < 3) return this
        return copy(audioDspBlob = CameraCommands.audioDspHex(blob))
            .applyingAudioByte2(blob[2].toInt() and 0xFF)
    }

    fun withAudioDspAt2(): CameraStatus {
        val at2 =
            when {
                audioDspAt2 >= 0 -> audioDspAt2
                audioDspBlob.length >= 6 -> audioDspBlob.substring(4, 6).toIntOrNull(16) ?: -1
                else -> -1
            }
        return if (at2 >= 0) applyingAudioByte2(at2) else copy(audioDspAt2 = at2)
    }

    fun preservingExtras(prev: CameraStatus): CameraStatus =
        copy(
            expoMode = prev.expoMode,
            isoIndex = prev.isoIndex,
            colorMode = prev.colorMode,
            resolutionCode = prev.resolutionCode,
            fpsIndex = prev.fpsIndex,
            wbMode = prev.wbMode,
            wbKelvin = prev.wbKelvin,
            wbTint = prev.wbTint,
            focusMode = prev.focusMode,
            audioChannel = prev.audioChannel,
            windNr = prev.windNr,
            directionalAudio = prev.directionalAudio,
            vocalBoost = prev.vocalBoost,
            audioDspBlob = prev.audioDspBlob,
            audioDspAt2 = prev.audioDspAt2,
            zoomFactorRaw = prev.zoomFactorRaw,
            availableShutterDenoms = prev.availableShutterDenoms,
            availableIsoIndices = prev.availableIsoIndices,
            evComp = prev.evComp,
            isoLimit = prev.isoLimit,
            availableColorModes = prev.availableColorModes,
            focusX = prev.focusX,
            focusY = prev.focusY,
            hasCameraFocusPoint = prev.hasCameraFocusPoint,
            focusTrack = prev.focusTrack,
            zoomLens = prev.zoomLens,
            zoomFactor = prev.zoomFactor,
            glamourEnabled = prev.glamourEnabled,
            selfieFlip = prev.selfieFlip,
            gimbalFace = prev.gimbalFace,
            audioMetersLeft = prev.audioMetersLeft,
            audioMetersRight = prev.audioMetersRight,
            audioPeakLeft = prev.audioPeakLeft,
            audioPeakRight = prev.audioPeakRight,
        )

    fun toJson(): String =
        JSONObject()
            .put("batteryPercent", batteryPercent)
            .put("batteryMilliVolts", batteryMilliVolts)
            .put("batteryMilliAmps", batteryMilliAmps)
            .put("docked", docked)
            .put("charging", charging)
            .put("storageTotalMb", storageTotalMb)
            .put("storageFreeMb", storageFreeMb)
            .put("sdTotalMb", sdTotalMb)
            .put("sdFreeMb", sdFreeMb)
            .put("internalTotalMb", internalTotalMb)
            .put("internalFreeMb", internalFreeMb)
            .put("inPlayback", inPlayback)
            .put("firmware", firmware ?: JSONObject.NULL)
            .put("isRecording", isRecording)
            .put("shootingMode", shootingMode)
            .put("recordElapsedSec", recordElapsedSec)
            .put("recordRemainingSec", recordRemainingSec)
            .put("timecode", timecode ?: JSONObject.NULL)
            .put("iso", iso)
            .put("shutterDenom", shutterDenom)
            .put("fps", fps)
            .put("expoMode", expoMode)
            .put("isoIndex", isoIndex)
            .put("colorMode", colorMode)
            .put("videoResolution", resolutionCode)
            .put("fpsIndex", fpsIndex)
            .put("whiteBalanceMode", wbMode)
            .put("whiteBalanceKelvin", wbKelvin)
            .put("whiteBalanceTint", wbTint)
            .put("focusMode", focusMode)
            .put("audioChannel", audioChannel)
            .put("vocalBoost", vocalBoost)
            .put("audioDspAt2", audioDspAt2)
            .put("audioDspBlob", audioDspBlob.ifEmpty { JSONObject.NULL })
            .put("zoomFactorRaw", zoomFactorRaw)
            .put("availableShutterDenoms", JSONArray(availableShutterDenoms))
            .put("availableIsoIndices", JSONArray(availableIsoIndices))
            .put("evComp", evComp)
            .put("isoLimit", isoLimit)
            .put("availableColorModes", JSONArray(availableColorModes))
            .put("focusX", focusX)
            .put("focusY", focusY)
            .put("hasCameraFocusPoint", hasCameraFocusPoint)
            .put("focusTrack", focusTrack)
            .put("zoomLens", zoomLens)
            .put("zoomFactor", zoomFactor ?: JSONObject.NULL)
            .put("glamourEnabled", glamourEnabled ?: JSONObject.NULL)
            .put("selfieFlip", selfieFlip ?: JSONObject.NULL)
            .put("gimbalFace", gimbalFace)
            .put("windNR", windNRJson())
            .put("directionalAudio", directionalAudioJson())
            .put("audioMetersLeft", audioMetersLeft)
            .put("audioMetersRight", audioMetersRight)
            .put("audioPeakLeft", audioPeakLeft)
            .put("audioPeakRight", audioPeakRight)
            .toString()

    /** Core `WindNoiseReduction` raw (`1A`/`18`); Kotlin HUD keeps `windNr` as 0/1. */
    private fun windNRJson(): Int =
        when (windNr) {
            0 -> CameraCommands.WIND_OFF
            1 -> CameraCommands.WIND_ON
            else -> windNr
        }

    /** Core `DirectionalAudio` raw (`DA`/`3A`/`BA`); HUD keeps 0/1/2. */
    private fun directionalAudioJson(): Int =
        when (directionalAudio) {
            0 -> CameraCommands.DIR_ALL
            1 -> CameraCommands.DIR_FRONT
            2 -> CameraCommands.DIR_FRONT_BACK
            else -> directionalAudio
        }

    companion object {
        fun fromJson(raw: String?): CameraStatus {
            if (raw.isNullOrBlank()) return CameraStatus()
            return runCatching {
                val obj = JSONObject(raw)
                CameraStatus(
                    batteryPercent = obj.optInt("batteryPercent", -1),
                    batteryMilliVolts = obj.optInt("batteryMilliVolts", 0),
                    batteryMilliAmps = obj.optInt("batteryMilliAmps", 0),
                    docked = obj.optBoolean("docked", false),
                    charging = obj.optBoolean("charging", false),
                    storageTotalMb = obj.optInt("storageTotalMb", 0),
                    storageFreeMb = obj.optInt("storageFreeMb", 0),
                    sdTotalMb = obj.optInt("sdTotalMb", 0),
                    sdFreeMb = obj.optInt("sdFreeMb", 0),
                    internalTotalMb = obj.optInt("internalTotalMb", -1),
                    internalFreeMb = obj.optInt("internalFreeMb", -1),
                    inPlayback = obj.optBoolean("inPlayback", false),
                    firmware = obj.optString("firmware").takeIf { it.isNotEmpty() && obj.has("firmware") && !obj.isNull("firmware") },
                    isRecording = obj.optBoolean("isRecording", false),
                    shootingMode = obj.optInt("shootingMode", -1),
                    recordElapsedSec = obj.optInt("recordElapsedSec", 0),
                    recordRemainingSec = obj.optInt("recordRemainingSec", 0),
                    timecode = obj.optString("timecode").takeIf { it.isNotEmpty() && obj.has("timecode") && !obj.isNull("timecode") },
                    iso = obj.optInt("iso", -1),
                    shutterDenom = obj.optInt("shutterDenom", -1),
                    fps = obj.optInt("fps", 0),
                    expoMode = obj.optInt("expoMode", -1),
                    isoIndex = obj.optInt("isoIndex", -1),
                    colorMode = obj.optInt("colorMode", -1),
                    resolutionCode = obj.optInt("videoResolution", obj.optInt("resolutionCode", -1)),
                    fpsIndex = obj.optInt("fpsIndex", -1),
                    wbMode = obj.optInt("whiteBalanceMode", obj.optInt("wbMode", -1)),
                    wbKelvin = obj.optInt("whiteBalanceKelvin", obj.optInt("wbKelvin", -1)),
                    wbTint = obj.optInt("whiteBalanceTint", obj.optInt("wbTint", 0)),
                    focusMode = obj.optInt("focusMode", -1),
                    audioChannel = obj.optInt("audioChannel", -1),
                    vocalBoost = obj.optInt("vocalBoost", -1),
                    audioDspBlob =
                        obj.optString("audioDspBlob").takeIf {
                            it.isNotEmpty() && obj.has("audioDspBlob") && !obj.isNull("audioDspBlob")
                        } ?: "",
                    audioDspAt2 = obj.optInt("audioDspAt2", -1),
                    zoomFactorRaw = obj.optInt("zoomFactorRaw", 0),
                    availableShutterDenoms = intList(obj.optJSONArray("availableShutterDenoms")),
                    availableIsoIndices = intList(obj.optJSONArray("availableIsoIndices")),
                    evComp = obj.optInt("evComp", -1),
                    isoLimit = obj.optInt("isoLimit", -1),
                    availableColorModes = intList(obj.optJSONArray("availableColorModes")),
                    focusX = obj.optDouble("focusX", 0.5),
                    focusY = obj.optDouble("focusY", 0.5),
                    hasCameraFocusPoint = obj.optBoolean("hasCameraFocusPoint", false),
                    focusTrack = obj.optInt("focusTrack", -1),
                    zoomLens = obj.optInt("zoomLens", -1),
                    zoomFactor = optionalDouble(obj, "zoomFactor"),
                    glamourEnabled = optionalBoolean(obj, "glamourEnabled"),
                    selfieFlip = optionalBoolean(obj, "selfieFlip"),
                    gimbalFace = obj.optInt("gimbalFace", CameraCommands.GIMBAL_FACE_UNKNOWN),
                    windNr = mapWindNr(obj),
                    directionalAudio = mapDirectionalAudio(obj),
                    audioMetersLeft = obj.optDouble("audioMetersLeft", -60.0),
                    audioMetersRight = obj.optDouble("audioMetersRight", -60.0),
                    audioPeakLeft = obj.optDouble("audioPeakLeft", -60.0),
                    audioPeakRight = obj.optDouble("audioPeakRight", -60.0),
                ).withAudioDspAt2()
            }.getOrElse { CameraStatus() }
        }

        private fun intList(arr: JSONArray?): List<Int> {
            if (arr == null) return emptyList()
            return buildList(arr.length()) {
                for (i in 0 until arr.length()) add(arr.optInt(i))
            }
        }

        private fun optionalDouble(obj: JSONObject, key: String): Double? {
            if (!obj.has(key) || obj.isNull(key)) return null
            val value = obj.optDouble(key)
            return if (value.isNaN()) null else value
        }

        private fun optionalBoolean(obj: JSONObject, key: String): Boolean? {
            if (!obj.has(key) || obj.isNull(key)) return null
            return obj.optBoolean(key)
        }

        private fun mapWindNr(obj: JSONObject): Int {
            val raw =
                when {
                    obj.has("windNR") && !obj.isNull("windNR") -> obj.optInt("windNR", -1)
                    obj.has("windNr") && !obj.isNull("windNr") -> obj.optInt("windNr", -1)
                    else -> -1
                }
            return when (raw) {
                CameraCommands.WIND_ON, 1 -> 1
                CameraCommands.WIND_OFF, 0 -> 0
                else -> if (raw < 0) -1 else raw
            }
        }

        private fun mapDirectionalAudio(obj: JSONObject): Int {
            val raw = obj.optInt("directionalAudio", -1)
            return when (raw) {
                CameraCommands.DIR_ALL, 0 -> 0
                CameraCommands.DIR_FRONT, 1 -> 1
                CameraCommands.DIR_FRONT_BACK, 2 -> 2
                else -> if (raw < 0) -1 else raw
            }
        }
    }
}

object DumlCodec {
    fun unpackFrames(packed: ByteArray?): List<DumlFrame> {
        if (packed == null || packed.size < 2) return emptyList()
        val count = (packed[0].toInt() and 0xFF) or ((packed[1].toInt() and 0xFF) shl 8)
        var offset = 2
        val out = ArrayList<DumlFrame>(count)
        repeat(count) {
            if (offset + 2 > packed.size) return out
            val len = (packed[offset].toInt() and 0xFF) or ((packed[offset + 1].toInt() and 0xFF) shl 8)
            offset += 2
            if (offset + len > packed.size || len < 7) return out
            val slice = packed.copyOfRange(offset, offset + len)
            offset += len
            val seq = (slice[2].toInt() and 0xFF) or ((slice[3].toInt() and 0xFF) shl 8)
            out.add(
                DumlFrame(
                    sender = slice[0].toInt() and 0xFF,
                    receiver = slice[1].toInt() and 0xFF,
                    seq = seq,
                    flags = slice[4].toInt() and 0xFF,
                    cmdSet = slice[5].toInt() and 0xFF,
                    cmdId = slice[6].toInt() and 0xFF,
                    payload = if (len > 7) slice.copyOfRange(7, len) else ByteArray(0),
                )
            )
        }
        return out
    }
}
