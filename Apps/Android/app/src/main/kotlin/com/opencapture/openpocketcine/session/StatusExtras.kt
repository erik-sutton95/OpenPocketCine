package com.opencapture.openpocketcine.session

/**
 * Overlay fields the JNI status JSON does not yet carry, parsed from the same
 * subscribe pushes / GET replies the camera already sends.
 *
 * `cam_expo_param` uses the labeled Mimo offsets: shutter `@2–3` (`denom|0x8000`),
 * ISO index `@5`, expo mode `@7`, ISO number `@16`.
 */
object StatusExtras {
    fun apply(frame: DumlFrame, status: CameraStatus): CameraStatus {
        return when {
            frame.cmdSet == 0x00 && frame.cmdId == 0x99 -> applySubscribe(frame.payload, status)
            frame.cmdSet == 0x02 && frame.cmdId == CameraCommands.CMD_PARAM -> applyParamReply(frame.payload, status)
            frame.cmdSet == 0x02 && frame.cmdId == CameraCommands.CMD_AUDIO_DSP_GET ->
                applyAudioDsp(frame.payload, status).first
            else -> status
        }
    }

    fun applySubscribe(payload: ByteArray, status: CameraStatus): CameraStatus {
        val item = parseSubscribe(payload) ?: return status
        return when (item.name) {
            "cam_expo_param" -> applyExpo(item.value, status)
            "cam_video_param_v2" -> applyVideo(item.value, status)
            "cam_image_effect" -> applyImageEffect(item.value, status)
            "cam_lens_state" -> applyLens(item.value, status)
            "cam_fov" -> applyFov(item.value, status)
            "camcap_shutter" -> applyShutterCap(item.value, status)
            "camcap_iso" -> applyIsoCap(item.value, status)
            else -> status
        }
    }

    fun applyExpo(value: ByteArray, status: CameraStatus): CameraStatus {
        if (value.size < 18) return status
        var next = status
        if (value.size > 7) {
            val mode = value[7].toInt() and 0xFF
            if (mode == CameraCommands.EXPO_AUTO || mode == CameraCommands.EXPO_MANUAL) {
                next = next.copy(expoMode = mode)
            }
        }
        if (value.size > 5) {
            next = next.copy(isoIndex = value[5].toInt() and 0xFF)
        }
        val shutterRaw = u16(value, 2)
        if (shutterRaw and 0x8000 != 0) {
            val denom = shutterRaw and 0x7FFF
            if (denom in 1..16_000) next = next.copy(shutterDenom = denom)
        }
        val iso = u16(value, 16)
        if (iso in 50..102_400) next = next.copy(iso = iso)
        return next
    }

    fun applyVideo(value: ByteArray, status: CameraStatus): CameraStatus {
        if (value.size < 2) return status
        val res = value[0].toInt() and 0xFF
        val fpsIdx = value[1].toInt() and 0xFF
        val fps = CameraCommands.fpsFromIndex(fpsIdx) ?: status.fps
        return status.copy(resolutionCode = res, fpsIndex = fpsIdx, fps = fps)
    }

    fun applyImageEffect(value: ByteArray, status: CameraStatus): CameraStatus {
        if (value.size < 5) return status
        var next = status.copy(colorMode = value[2].toInt() and 0xFF)
        if (value.size >= 9) {
            next =
                next.copy(
                    wbMode = value[4].toInt() and 0xFF,
                    wbKelvin = u16(value, 5) * 100,
                    wbTint = i16(value, 7),
                )
        }
        return next
    }

    fun applyShutterCap(value: ByteArray, status: CameraStatus): CameraStatus {
        val denoms = CameraCommands.parseShutterDenoms(value)
        return if (denoms.isEmpty()) status else status.copy(availableShutterDenoms = denoms)
    }

    fun applyIsoCap(value: ByteArray, status: CameraStatus): CameraStatus {
        val indices = CameraCommands.parseIsoIndices(value)
        return if (indices.isEmpty()) status else status.copy(availableIsoIndices = indices)
    }

    fun applyFov(value: ByteArray, status: CameraStatus): CameraStatus {
        if (value.size < 4) return status
        val raw =
            (value[0].toInt() and 0xFF) or
                ((value[1].toInt() and 0xFF) shl 8) or
                ((value[2].toInt() and 0xFF) shl 16) or
                ((value[3].toInt() and 0xFF) shl 24)
        return status.copy(zoomFactorRaw = raw)
    }

    fun applyLens(value: ByteArray, status: CameraStatus): CameraStatus {
        if (value.isEmpty()) return status
        val mode =
            when (value[0].toInt() and 0xFF) {
                0xB1 -> CameraCommands.FOCUS_SINGLE
                0xB2 -> CameraCommands.FOCUS_CONTINUOUS
                else -> return status
            }
        return status.copy(focusMode = mode)
    }

    fun applyParamReply(payload: ByteArray, status: CameraStatus): CameraStatus {
        FocusTrackMode.parseReply(payload)?.let { return status.copy(focusTrack = it.raw) }
        if (payload.size < 7) return status
        val pid = (payload[3].toInt() and 0xFF) or ((payload[4].toInt() and 0xFF) shl 8)
        val value = payload[6].toInt() and 0xFF
        return when (pid) {
            CameraCommands.PID_AUDIO_CHANNEL -> status.copy(audioChannel = value)
            CameraCommands.PID_VOCAL_BOOST -> status.copy(vocalBoost = value)
            else -> status
        }
    }

    fun applyAudioDsp(payload: ByteArray, status: CameraStatus): Pair<CameraStatus, ByteArray?> {
        if (payload.isEmpty() || payload[0] != 0.toByte() || payload.size < 27) {
            return status to null
        }
        val blob = payload.copyOfRange(1, 27)
        return applyAudioBlob(blob, status) to blob
    }

    fun applyAudioBlob(blob: ByteArray, status: CameraStatus): CameraStatus {
        if (blob.size < 3) return status
        val at2 = blob[2].toInt() and 0xFF
        val wind =
            when (at2) {
                CameraCommands.WIND_ON -> 1
                CameraCommands.WIND_OFF -> 0
                else -> status.windNr
            }
        val directional =
            when (at2) {
                CameraCommands.DIR_ALL -> 0
                CameraCommands.DIR_FRONT -> 1
                CameraCommands.DIR_FRONT_BACK -> 2
                else -> status.directionalAudio
            }
        return status
            .copy(
                audioDspBlob = blob.joinToString("") { "%02x".format(it.toInt() and 0xFF) },
                audioDspAt2 = at2,
                windNr = wind,
                directionalAudio = directional,
            )
            .withAudioDspAt2()
    }

    fun parseSubscribe(payload: ByteArray): SubscribeItem? {
        if (payload.size < 24 || payload[0] != 0x02.toByte() || payload[1] != 0x06.toByte()) return null
        val nameLen = (payload[13].toInt() and 0xFF) or ((payload[14].toInt() and 0xFF) shl 8)
        if (nameLen <= 0 || nameLen >= 80 || 15 + nameLen + 8 > payload.size) return null
        val name = payload.decodeToString(15, 15 + nameLen)
        if (name.isEmpty()) return null
        val valueLenAt = 15 + nameLen + 6
        if (valueLenAt + 2 > payload.size) return null
        val valueLen = (payload[valueLenAt].toInt() and 0xFF) or ((payload[valueLenAt + 1].toInt() and 0xFF) shl 8)
        val valueAt = valueLenAt + 2
        if (valueAt + valueLen > payload.size) return null
        return SubscribeItem(name, payload.copyOfRange(valueAt, valueAt + valueLen))
    }

    fun packSubscribe(name: String, value: ByteArray, idx: Int = 0): ByteArray {
        val nb = name.encodeToByteArray()
        val inner = 2 + nb.size + 6 + 2 + value.size
        val out = ArrayList<Byte>(15 + nb.size + 8 + value.size)
        out.addAll(listOf(0x02, 0x06, 0x00, 0x00).map { it.toByte() })
        out.add((idx and 0xFF).toByte())
        out.add(((idx shr 8) and 0xFF).toByte())
        out.add(((idx shr 16) and 0xFF).toByte())
        out.add(((idx shr 24) and 0xFF).toByte())
        out.addAll(listOf(0, 0, 0).map { it.toByte() })
        out.add((inner and 0xFF).toByte())
        out.add(((inner shr 8) and 0xFF).toByte())
        out.add((nb.size and 0xFF).toByte())
        out.add(((nb.size shr 8) and 0xFF).toByte())
        out.addAll(nb.toList())
        repeat(6) { out.add(0) }
        out.add((value.size and 0xFF).toByte())
        out.add(((value.size shr 8) and 0xFF).toByte())
        out.addAll(value.toList())
        return out.toByteArray()
    }

    data class SubscribeItem(val name: String, val value: ByteArray)

    private fun u16(p: ByteArray, i: Int): Int =
        (p[i].toInt() and 0xFF) or ((p[i + 1].toInt() and 0xFF) shl 8)

    private fun i16(p: ByteArray, i: Int): Int {
        val u = u16(p, i)
        return if (u >= 0x8000) u - 0x10000 else u
    }
}
