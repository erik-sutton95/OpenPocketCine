package com.opencapture.openpocketcine.session

/** `0x02/0x18` `@0`. Only 1080p / 4K were in the labeled take. */
enum class VideoResolution(val rawValue: Int, val label: String, val tabTitle: String) {
    P1080(0x0A, "1080p", "1080"),
    P4K(0x10, "4K", "4K"),
    ;

    companion object {
        fun fromRaw(raw: Int): VideoResolution? = entries.firstOrNull { it.rawValue == raw }

        /** iOS `resolutionForTab`: tab 1 is 4K, anything else 1080. */
        fun fromTabIndex(index: Int): VideoResolution = if (index == 1) P4K else P1080

        val tabTitles: List<String> get() = entries.map { it.tabTitle }
    }
}

/** `0x02/0x18` `@1` fps index. SET only the six labeled values. */
enum class VideoFrameRate(val rawValue: Int, val fps: Int) {
    FPS24(0x01, 24),
    FPS25(0x02, 25),
    FPS30(0x03, 30),
    FPS48(0x04, 48),
    FPS50(0x05, 50),
    FPS60(0x06, 60),
    ;

    val label: String get() = "$fps"
    val drumLabel: String get() = "${fps}p"

    companion object {
        fun fromRaw(raw: Int): VideoFrameRate? = entries.firstOrNull { it.rawValue == raw }

        fun fromFps(fps: Int): VideoFrameRate? = entries.firstOrNull { it.fps == fps }

        fun fromDrumLabel(label: String): VideoFrameRate? =
            entries.firstOrNull { it.drumLabel == label }

        val drumLabels: List<String> get() = entries.map { it.drumLabel }

        /** Labeled Video-mode SET. SlowMo 100/120/240 is display-only. */
        val labeledVideo: List<VideoFrameRate> get() = entries
    }
}

/** One 5-byte SET: `[res][fps_idx] 00 00 00`. No GET — `cam_video_param_v2` `@0–1`. */
data class VideoFormat(val resolution: VideoResolution, val frameRate: VideoFrameRate) {
    val setPayload: ByteArray
        get() = CameraCommands.resolutionFps(resolution.rawValue, frameRate.rawValue)

    /** Top-deck chip, OpenZCine `resolutionFrameRate` shape (`4K · 25p`). */
    val chipLabel: String get() = "${resolution.label} · ${frameRate.fps}p"

    companion object {
        fun parse(resRaw: Int, fpsRaw: Int): VideoFormat? {
            val res = VideoResolution.fromRaw(resRaw) ?: return null
            val fps = VideoFrameRate.fromRaw(fpsRaw) ?: return null
            return VideoFormat(res, fps)
        }

        fun parseVideoParamV2(value: ByteArray): VideoFormat? {
            if (value.size < 2) return null
            return parse(value[0].toInt() and 0xFF, value[1].toInt() and 0xFF)
        }

        /** Other labeled resolution, same fps. iOS `VideoFormat.firstPictureEncoderKick`. */
        fun firstPictureEncoderKick(original: VideoFormat): VideoFormat =
            VideoFormat(
                if (original.resolution == VideoResolution.P4K) VideoResolution.P1080
                else VideoResolution.P4K,
                original.frameRate,
            )

        /** Reported P3 boot is 4K 25/30. Unknown falls back to 4K 30, not 1080 24. */
        fun firstPictureOriginal(status: CameraStatus): VideoFormat {
            parse(status.resolutionCode, status.fpsIndex)?.let { return it }
            val res = VideoResolution.fromRaw(status.resolutionCode) ?: VideoResolution.P4K
            val rate = VideoFrameRate.fromFps(status.fps) ?: VideoFrameRate.FPS30
            return VideoFormat(res, rate)
        }

        /** iOS `LiveTopChrome.recFormatLabel`. */
        fun chipLabel(status: CameraStatus): String {
            parse(status.resolutionCode, status.fpsIndex)?.let { return it.chipLabel }
            val fpsText = if (status.fps > 0) "${status.fps}p" else "—"
            val res = VideoResolution.fromRaw(status.resolutionCode)
            return if (res != null) "${res.label} · $fpsText" else "— · $fpsText"
        }

        /** iOS `CapturePickerPanel.currentVideoFormat`. */
        fun current(status: CameraStatus): VideoFormat {
            parse(status.resolutionCode, status.fpsIndex)?.let { return it }
            val res = VideoResolution.fromRaw(status.resolutionCode) ?: VideoResolution.P1080
            val rate = VideoFrameRate.fromFps(status.fps) ?: VideoFrameRate.FPS24
            return VideoFormat(res, rate)
        }

        /** iOS `CamCapVideoFormat.resolutions`. Empty camcap → 1080 / 4K tabs. */
        fun resolutions(available: List<VideoFormat>, current: VideoResolution?): List<VideoResolution> {
            if (available.isEmpty()) return VideoResolution.entries
            val out = ArrayList<VideoResolution>()
            val seen = HashSet<VideoResolution>()
            for (format in available) {
                if (seen.add(format.resolution)) out.add(format.resolution)
            }
            if (current != null && current !in seen) out.add(0, current)
            return out
        }

        /** iOS `CamCapVideoFormat.frameRates`. Empty Video camcap → 24–60. */
        fun frameRates(
            available: List<VideoFormat>,
            resolution: VideoResolution,
            current: VideoFrameRate?,
        ): List<VideoFrameRate> {
            val rates = available.filter { it.resolution == resolution }.map { it.frameRate }
            if (rates.isEmpty()) {
                if (current != null && current !in VideoFrameRate.labeledVideo) return listOf(current)
                return VideoFrameRate.labeledVideo
            }
            return rates
        }

        /** Tab change: skip the SET when res+fps already match. */
        fun nextForTab(status: CameraStatus, tab: Int, drum: String): VideoFormat? {
            val rate = VideoFrameRate.fromDrumLabel(drum) ?: current(status).frameRate
            val next = VideoFormat(VideoResolution.fromTabIndex(tab), rate)
            return next.takeIf { it != current(status) }
        }

        /** Drum row: unlabeled labels (`120p`) do not SET. */
        fun nextForDrum(status: CameraStatus, tab: Int, drum: String): VideoFormat? {
            val rate = VideoFrameRate.fromDrumLabel(drum) ?: return null
            return VideoFormat(VideoResolution.fromTabIndex(tab), rate)
        }

        fun absorbStale(
            incoming: CameraStatus,
            pin: FormatPin?,
            nowElapsedRealtime: Long,
        ): Pair<CameraStatus, FormatPin?> {
            if (pin == null) return incoming to null
            if (nowElapsedRealtime >= pin.deadlineElapsedRealtime) return incoming to null
            val incomingFormat = parse(incoming.resolutionCode, incoming.fpsIndex)
            if (incomingFormat == pin.expected ||
                (incoming.resolutionCode == pin.expected.resolution.rawValue &&
                    incoming.fps == pin.expected.frameRate.fps)
            ) {
                return incoming to null
            }
            return incoming.copy(
                resolutionCode = pin.expected.resolution.rawValue,
                fpsIndex = pin.expected.frameRate.rawValue,
                fps = pin.expected.frameRate.fps,
            ) to pin
        }
    }
}

data class FormatPin(val expected: VideoFormat, val deadlineElapsedRealtime: Long)

/** iOS `CameraSession.colorPin` — hold the SET color until subscribe matches. */
data class ColorPin(val expected: Int, val deadlineElapsedRealtime: Long) {
    companion object {
        fun absorbStale(
            incoming: CameraStatus,
            pin: ColorPin?,
            nowElapsedRealtime: Long,
        ): Pair<CameraStatus, ColorPin?> {
            if (pin == null) return incoming to null
            if (nowElapsedRealtime >= pin.deadlineElapsedRealtime) return incoming to null
            if (incoming.colorMode == pin.expected) return incoming to null
            return incoming.copy(colorMode = pin.expected) to pin
        }
    }
}

/** iOS `GimbalStickMapping` — invert on TT180; extra-mirror = TT180 && Flip off. */
data class GimbalStickMapping(
    val face: Int = CameraCommands.GIMBAL_FACE_UNKNOWN,
    val wireFace: Int = CameraCommands.GIMBAL_FACE_UNKNOWN,
    val rotated180: Boolean = false,
    val holdFace: Boolean = false,
    val seenFront: Boolean = false,
    val rotateParity: Boolean = false,
    val commanded180: Boolean = false,
    val selfieFlip: Boolean = false,
    val pendingWant180: List<Boolean> = emptyList(),
    val yawTenthDeg: Int? = null,
    val poseSeeded: Boolean = false,
    val poseSeedFrontCount: Int = 0,
) {
    val pendingRotateCount: Int
        get() = pendingWant180.size

    val poseViewFlip: Boolean
        get() = commanded180 && !selfieFlip

    val invertPan: Boolean
        get() = commanded180

    fun noteRotate180(): GimbalStickMapping = noteRotate180(fromBody = false)

    fun noteRotate180(fromBody: Boolean): GimbalStickMapping =
        copy(
            holdFace = if (fromBody) holdFace else true,
            pendingWant180 = pendingWant180 + CameraCommands.fe09GoesTo180(yawTenthDeg),
        )

    fun noteBodyFace(newFace: Int): GimbalStickMapping {
        val previous = wireFace
        val wasHold = holdFace
        val next = applyFace(newFace)
        if (wasHold || previous < 0 || newFace < 0 || newFace == previous) return next
        return next.copy(
            commanded180 = newFace == CameraCommands.GIMBAL_FACE_SELFIE,
            poseSeeded = true,
            poseSeedFrontCount = 0,
        )
    }

    fun applyFace(newFace: Int): GimbalStickMapping {
        if (newFace < 0) return this
        var next = this
        if (newFace == CameraCommands.GIMBAL_FACE_FRONT) {
            next = next.copy(seenFront = true)
        }
        if (newFace == CameraCommands.GIMBAL_FACE_SELFIE && !next.seenFront) return next
        if (next.holdFace) {
            if (next.wireFace < 0) return next.copy(wireFace = newFace)
            if (newFace == next.wireFace) return next
            return next.copy(
                wireFace = newFace,
                rotateParity = !next.rotateParity,
                holdFace = false,
            )
        }
        val decoded =
            if ((newFace == CameraCommands.GIMBAL_FACE_SELFIE) != next.rotateParity) {
                CameraCommands.GIMBAL_FACE_SELFIE
            } else {
                CameraCommands.GIMBAL_FACE_FRONT
            }
        return next.copy(face = decoded, wireFace = newFace, holdFace = false)
    }

    fun applyAttitude(payload: ByteArray): GimbalStickMapping {
        val yaw = CameraCommands.yawTenthDeg(payload) ?: return this
        val rotated = kotlin.math.abs(yaw) > CameraCommands.ROTATED_180_TENTH_DEG
        var next = copy(rotated180 = rotated, yawTenthDeg = yaw)
        val want180 = next.pendingWant180.firstOrNull()
        if (want180 != null) {
            if (CameraCommands.rotationSettled(yaw, want180)) {
                next = next.copy(
                    commanded180 = want180,
                    pendingWant180 = next.pendingWant180.drop(1),
                    poseSeeded = true,
                    poseSeedFrontCount = 0,
                )
            }
        } else if (!next.poseSeeded) {
            if (rotated) {
                next = next.copy(commanded180 = true, poseSeeded = true, poseSeedFrontCount = 0)
            } else if (CameraCommands.rotationSettled(yaw, false)) {
                val votes = next.poseSeedFrontCount + 1
                next = if (votes >= CameraCommands.POSE_SEED_FRONT_VOTES) {
                    next.copy(commanded180 = false, poseSeeded = true, poseSeedFrontCount = votes)
                } else {
                    next.copy(poseSeedFrontCount = votes)
                }
            } else {
                next = next.copy(poseSeedFrontCount = 0)
            }
        }
        return next
    }
}
