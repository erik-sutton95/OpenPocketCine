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
