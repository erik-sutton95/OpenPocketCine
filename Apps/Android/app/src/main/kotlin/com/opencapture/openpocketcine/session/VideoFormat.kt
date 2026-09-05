package com.opencapture.openpocketcine.session

/** Recording aspect. Encoded in the `0x02/0x18` res byte — not a second SET. */
enum class VideoAspect(val label: String) {
    SIXTEEN_NINE("16:9"),
    FOUR_THREE("4:3"),
    ONE_ONE("1:1"),
    NINE_SIXTEEN("9:16"),
}

/** `0x02/0x18` `@0`. Any byte the body sends; labels from the media catalog. */
data class VideoResolution(val rawValue: Int) {
    val aspect: VideoAspect?
        get() =
            when (rawValue) {
                0x0A, 0x10, 0x2D -> VideoAspect.SIXTEEN_NINE
                0x0C, 0x5F, 0x67 -> VideoAspect.FOUR_THREE
                0x69, 0x6A, 0x6B, 0x7D -> VideoAspect.ONE_ONE
                0x42, 0x43, 0x6C -> VideoAspect.NINE_SIXTEEN
                else -> null
            }

    val sizeTitle: String
        get() =
            when (rawValue) {
                0x0A, 0x0C, 0x42, 0x69 -> "1080"
                0x2D, 0x43, 0x5F -> "2.7K"
                0x10, 0x67, 0x7D -> "4K"
                0x6A -> "2160"
                0x6B, 0x6C -> "3K"
                else -> "%02X".format(rawValue)
            }

    private val sizeLabel: String
        get() =
            when (rawValue) {
                0x0A, 0x0C, 0x42, 0x69 -> "1080p"
                0x2D, 0x43, 0x5F -> "2.7K"
                0x10, 0x67, 0x7D -> "4K"
                0x6A -> "2160p"
                0x6B, 0x6C -> "3K"
                else -> "0x%02X".format(rawValue)
            }

    val label: String
        get() {
            val aspect = aspect ?: return sizeLabel
            return if (aspect == VideoAspect.SIXTEEN_NINE) sizeLabel else "$sizeLabel ${aspect.label}"
        }

    val tabTitle: String get() = sizeTitle

    companion object {
        val P1080 = VideoResolution(0x0A)
        val P1080_4X3 = VideoResolution(0x0C)
        val P4K = VideoResolution(0x10)
        val P2_7K = VideoResolution(0x2D)
        val P1080_9X16 = VideoResolution(0x42)
        val P2_7K_9X16 = VideoResolution(0x43)
        val P2_7K_4X3 = VideoResolution(0x5F)
        val P4K_4X3 = VideoResolution(0x67)
        val P1080_1X1 = VideoResolution(0x69)
        val P2160_1X1 = VideoResolution(0x6A)
        val P3K_1X1 = VideoResolution(0x6B)
        val P3K_9X16 = VideoResolution(0x6C)
        val P4K_1X1 = VideoResolution(0x7D)

        fun fromRaw(raw: Int): VideoResolution? =
            if (raw in 0..255) VideoResolution(raw) else null

        fun fromTabIndex(index: Int): VideoResolution = labeledVideo.getOrElse(index) { P1080 }

        val labeledVideo: List<VideoResolution>
            get() = listOf(P1080, P4K)

        val tabTitles: List<String> get() = labeledVideo.map { it.tabTitle }
    }
}

/** `0x02/0x18` `@1`. Any index the body sends; fps from the Osmosis table. */
data class VideoFrameRate(val rawValue: Int) {
    val fps: Int get() = fps(rawValue) ?: 0
    val label: String get() = if (fps > 0) "$fps" else "%02X".format(rawValue)
    val drumLabel: String get() = if (fps > 0) "${fps}p" else "%02Xp".format(rawValue)

    companion object {
        val FPS24 = VideoFrameRate(0x01)
        val FPS25 = VideoFrameRate(0x02)
        val FPS30 = VideoFrameRate(0x03)
        val FPS48 = VideoFrameRate(0x04)
        val FPS50 = VideoFrameRate(0x05)
        val FPS60 = VideoFrameRate(0x06)
        val FPS120 = VideoFrameRate(0x07)
        val FPS240 = VideoFrameRate(0x08)
        val FPS100 = VideoFrameRate(0x0A)
        val FPS96 = VideoFrameRate(0x0B)
        val FPS15 = VideoFrameRate(0x1D)

        fun fromRaw(raw: Int): VideoFrameRate? =
            if (raw in 0..255) VideoFrameRate(raw) else null

        fun fps(index: Int): Int? =
            when (index) {
                1 -> 24
                2 -> 25
                3 -> 30
                4 -> 48
                5 -> 50
                6 -> 60
                7 -> 120
                8 -> 240
                10 -> 100
                11 -> 96
                29 -> 15
                else -> null
            }

        fun fromFps(fps: Int): VideoFrameRate? =
            listOf(FPS24, FPS25, FPS30, FPS48, FPS50, FPS60, FPS120, FPS240, FPS100, FPS96, FPS15)
                .firstOrNull { it.fps == fps }

        fun fromDrumLabel(label: String): VideoFrameRate? =
            listOf(FPS24, FPS25, FPS30, FPS48, FPS50, FPS60, FPS120, FPS240, FPS100, FPS96, FPS15)
                .firstOrNull { it.drumLabel == label }

        val drumLabels: List<String> get() = labeledVideo.map { it.drumLabel }

        val labeledVideo: List<VideoFrameRate>
            get() = listOf(FPS24, FPS25, FPS30, FPS48, FPS50, FPS60)
    }
}

/** One 5-byte SET: `[res][fps_idx] 00 00 00`. No GET — `cam_video_param_v2` `@0–1`. */
data class VideoFormat(val resolution: VideoResolution, val frameRate: VideoFrameRate) {
    val setPayload: ByteArray
        get() = CameraCommands.resolutionFps(resolution.rawValue, frameRate.rawValue)

    /** Top-deck chip, OpenZCine `resolutionFrameRate` shape (`4K · 25p`). */
    val chipLabel: String get() = "${resolution.label} · ${frameRate.drumLabel}"

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
        fun firstPictureEncoderKick(
            original: VideoFormat,
            available: List<VideoFormat> = emptyList(),
        ): VideoFormat {
            val naive =
                VideoFormat(
                    if (original.resolution == VideoResolution.P4K) VideoResolution.P1080
                    else VideoResolution.P4K,
                    original.frameRate,
                )
            if (available.isEmpty()) return naive
            if (naive in available) return naive
            available
                .firstOrNull {
                    it.frameRate == original.frameRate && it.resolution != original.resolution
                }
                ?.let { return it }
            available.firstOrNull { it.resolution != original.resolution }?.let { return it }
            available.firstOrNull { it != original }?.let { return it }
            return naive
        }

        /** True when a FORMAT SET would use a reported pair, not the 4K 30 guess. */
        fun hasKnownRecordingFormat(status: CameraStatus): Boolean {
            if (parse(status.resolutionCode, status.fpsIndex) != null) return true
            if (status.availableVideoFormats.isNotEmpty()) return true
            return VideoResolution.fromRaw(status.resolutionCode) != null && status.fps > 0
        }

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
        fun resolutions(
            available: List<VideoFormat>,
            current: VideoResolution?,
            aspect: VideoAspect? = null,
        ): List<VideoResolution> {
            if (available.isEmpty()) return VideoResolution.labeledVideo
            val out = ArrayList<VideoResolution>()
            val seen = HashSet<VideoResolution>()
            for (format in available) {
                if (aspect != null && format.resolution.aspect != aspect) continue
                if (seen.add(format.resolution)) out.add(format.resolution)
            }
            if (current != null && current !in seen &&
                (aspect == null || current.aspect == aspect)
            ) {
                out.add(0, current)
            }
            return out
        }

        fun aspects(available: List<VideoFormat>, current: VideoAspect?): List<VideoAspect> {
            if (available.isEmpty()) return listOf(current ?: VideoAspect.SIXTEEN_NINE)
            val out = ArrayList<VideoAspect>()
            val seen = HashSet<VideoAspect>()
            for (format in available) {
                val aspect = format.resolution.aspect ?: continue
                if (seen.add(aspect)) out.add(aspect)
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
            val res =
                resolutions(status.availableVideoFormats, current(status).resolution)
                    .getOrNull(tab) ?: return null
            val next = VideoFormat(res, rate)
            return next.takeIf { it != current(status) }
        }

        /** Drum row: rate must be on the camcap (or Video 24–60) list. */
        fun nextForDrum(status: CameraStatus, tab: Int, drum: String): VideoFormat? {
            val rate = VideoFrameRate.fromDrumLabel(drum) ?: return null
            val current = current(status)
            val res =
                resolutions(status.availableVideoFormats, current.resolution)
                    .getOrNull(tab) ?: current.resolution
            val rates = frameRates(status.availableVideoFormats, res, current.frameRate)
            if (rate !in rates) return null
            return VideoFormat(res, rate)
        }

        /**
         * Keep the optimistic FORMAT HUD until `cam_video_param_v2` reports the SET.
         *
         * Merged status from an unrelated push still carries the SET pair — that
         * is not confirmation. [formatReported] is true only when this apply
         * changed res / fps index / fps.
         */
        fun absorbStale(
            incoming: CameraStatus,
            pin: FormatPin?,
            nowElapsedRealtime: Long,
            formatReported: Boolean = true,
        ): Pair<CameraStatus, FormatPin?> {
            if (pin == null) return incoming to null
            if (nowElapsedRealtime >= pin.deadlineElapsedRealtime) return incoming to null
            val incomingFormat = parse(incoming.resolutionCode, incoming.fpsIndex)
            val matched =
                incomingFormat == pin.expected ||
                    (incoming.resolutionCode == pin.expected.resolution.rawValue &&
                        incoming.fps == pin.expected.frameRate.fps)
            if (formatReported && matched) return incoming to null
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
    val pitchTenthDeg: Int? = null,
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
        var next =
            copy(
                rotated180 = rotated,
                yawTenthDeg = yaw,
                pitchTenthDeg = CameraCommands.pitchTenthDeg(payload) ?: pitchTenthDeg,
            )
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
