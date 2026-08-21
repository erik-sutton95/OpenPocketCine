package com.opencapture.openpocketcine.assists

/**
 * OpenZCine cinema live-monitor set. Pocket omits LEVEL, DE-SQ, MAG, EV, PLAY.
 *
 * Toolbar: LUT PEAK FALSE | ZEBRA WAVE PARADE | HISTO VECTOR LIGHTS |
 * GUIDES GRID CROSS | MIRROR | AUDIO.
 */
enum class LiveAssistTool {
    LUT,
    PEAK,
    FALSE,
    ZEBRA,
    WAVE,
    PARADE,
    HISTO,
    VECTOR,
    LIGHTS,
    AUDIO,
    GUIDES,
    GRID,
    CROSS,
    MIRROR,
    ;

    val chipLabel: String
        get() = name

    val label: String
        get() = name

    val title: String
        get() =
            when (this) {
                LUT -> "LUT"
                PEAK -> "Peaking"
                FALSE -> "False Color"
                ZEBRA -> "Zebra"
                WAVE -> "Waveform"
                PARADE -> "RGB Parade"
                HISTO -> "Histogram"
                VECTOR -> "Vectorscope"
                LIGHTS -> "Traffic Lights"
                AUDIO -> "Audio Levels"
                GUIDES -> "Guides"
                GRID -> "Grid"
                CROSS -> "Crosshair"
                MIRROR -> "Mirror"
            }

    /** AUDIO / MIRROR are tap-only — no channel picker, no H/V flip. */
    val hasConfiguration: Boolean
        get() =
            when (this) {
                AUDIO, MIRROR -> false
                else -> true
            }

    companion object {
        /** Groups of three, then MIRROR. AUDIO is appended as its own trailing section. */
        val toolbarCases: List<LiveAssistTool> =
            listOf(LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, GUIDES, GRID, CROSS, MIRROR)

        /** Playback drops nothing Pocket already omits; AUDIO rides last like live. */
        val playbackToolbarCases: List<LiveAssistTool> = toolbarCases + AUDIO

        val settingsCases: List<LiveAssistTool> = toolbarCases + AUDIO

        val cleanPinCases: List<LiveAssistTool> = settingsCases

        fun fromPersisted(raw: String): LiveAssistTool? =
            entries.firstOrNull { it.name == raw || it.chipLabel == raw }
    }
}

enum class GuideFamily(val label: String) {
    FILM("Film"),
    SOCIAL("Social"),
    ;

    companion object {
        fun fromPersisted(raw: String): GuideFamily =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: FILM
    }
}

enum class GuideAspect(val label: String) {
    CINEMA_276("2.76:1"),
    CINEMA("2.39:1"),
    CINEMA_235("2.35:1"),
    TWO_K("2.00:1"),
    WIDE("1.85:1"),
    HD("16:9"),
    EURO("1.66:1"),
    IMAX("1.43:1"),
    ACADEMY("4:3"),
    VERTICAL("9:16"),
    SOCIAL("4:5"),
    SQUARE("1:1"),
    PORTRAIT("2:3"),
    FEED("1.91:1"),
    ;

    val ratio: Float
        get() {
            val parts = label.split(':')
            val a = parts.getOrNull(0)?.toFloatOrNull() ?: return 1f
            val b = parts.getOrNull(1)?.toFloatOrNull() ?: return 1f
            return if (b > 0f) a / b else 1f
        }

    companion object {
        val film: List<GuideAspect> =
            listOf(CINEMA_276, CINEMA, CINEMA_235, TWO_K, WIDE, HD, EURO, IMAX, ACADEMY)
        val social: List<GuideAspect> = listOf(VERTICAL, SOCIAL, SQUARE, PORTRAIT, HD, FEED)

        fun ratios(family: GuideFamily): List<GuideAspect> =
            when (family) {
                GuideFamily.FILM -> film
                GuideFamily.SOCIAL -> social
            }

        fun fromPersisted(raw: String): GuideAspect =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: CINEMA
    }
}

enum class PeakingColor(val label: String) {
    WHITE("White"),
    BLUE("Blue"),
    RED("Red"),
    GREEN("Green"),
    ;

    /** Overlay RGB OpenZCine paints on focused edges. */
    val rgb: Triple<Double, Double, Double>
        get() =
            when (this) {
                WHITE -> Triple(246.0 / 255, 241.0 / 255, 226.0 / 255)
                BLUE -> Triple(64.0 / 255, 142.0 / 255, 255.0 / 255)
                RED -> Triple(255.0 / 255, 72.0 / 255, 64.0 / 255)
                GREEN -> Triple(74.0 / 255, 220.0 / 255, 132.0 / 255)
            }

    companion object {
        fun fromPersisted(raw: String): PeakingColor =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: RED
    }
}

enum class PeakingSense(val label: String) {
    LOW("Low"),
    MED("Med"),
    HIGH("High"),
    ;

    val ratioThreshold: Double
        get() =
            when (this) {
                LOW -> 2.30
                MED -> 2.10
                HIGH -> 1.90
            }

    val noiseGate: Double
        get() =
            when (this) {
                LOW -> 0.00522
                MED -> 0.00174
                HIGH -> 0.00058
            }

    companion object {
        fun fromPersisted(raw: String): PeakingSense =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: MED
    }
}

enum class FalseColorScale(val persisted: String, val menuLabel: String) {
    STOPS("ZC Stops", "PStops"),
    IRE("IRE", "IRE"),
    LIMITS("Limits", "Limits"),
    ;

    companion object {
        fun fromPersisted(raw: String): FalseColorScale =
            entries.firstOrNull {
                it.persisted == raw || it.menuLabel == raw || it.name == raw || raw == "Stops"
            } ?: STOPS

        fun fromMenuLabel(label: String): FalseColorScale =
            when (label) {
                "IRE" -> IRE
                "Limits" -> LIMITS
                else -> STOPS
            }
    }
}

enum class ZebraUnit(val persisted: String, val editorLabel: String) {
    NATIVE("Native", "0-255"),
    IRE("IRE", "IRE"),
    ;

    companion object {
        fun fromPersisted(raw: String): ZebraUnit =
            entries.firstOrNull { it.persisted == raw || it.editorLabel == raw || it.name == raw }
                ?: IRE

        fun fromEditorLabel(label: String): ZebraUnit = if (label == "0-255") NATIVE else IRE
    }
}

enum class ZebraPaint(val label: String) {
    WHITE("White"),
    AMBER("Amber"),
    RED("Red"),
    CYAN("Cyan"),
    GREEN("Green"),
    ;

    /** Overlay RGB iOS `ZebraPaint.rgb` paints on the feed. */
    val rgb: Triple<Double, Double, Double>
        get() =
            when (this) {
                WHITE -> Triple(1.0, 1.0, 1.0)
                AMBER -> Triple(1.0, 0.72, 0.2)
                RED -> Triple(1.0, 0.15, 0.15)
                CYAN -> Triple(0.0, 0.85, 0.9)
                GREEN -> Triple(0.2, 0.9, 0.35)
            }

    companion object {
        fun fromPersisted(raw: String): ZebraPaint =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: WHITE
    }
}

enum class WaveformMode(val label: String) {
    LUMA("Luma"),
    RGB("RGB"),
    ;

    companion object {
        fun fromPersisted(raw: String): WaveformMode =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: RGB
    }
}

enum class ParadeMode(val label: String) {
    RGB("RGB"),
    YRGB("YRGB"),
    ;

    val laneCount: Int
        get() = if (this == YRGB) 4 else 3

    val laneLabels: List<String>
        get() = if (this == YRGB) listOf("Y", "R", "G", "B") else listOf("R", "G", "B")

    companion object {
        fun fromPersisted(raw: String): ParadeMode =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: RGB
    }
}

enum class VectorscopeZoom(val label: String, val gain: Double) {
    X1("1x", 1.0),
    X2("2x", 2.0),
    X4("4x", 4.0),
    ;

    companion object {
        fun fromPersisted(raw: String): VectorscopeZoom =
            entries.firstOrNull { it.label == raw || it.name == raw } ?: X1
    }
}

/** OpenZCine `AssistConfiguration.CrushClipCompensation` — shared HISTO + LIGHTS. */
enum class CrushClipCompensation(val raw: Int, val label: String, val compactLabel: String) {
    ZERO(0, "0", "0"),
    QUARTER(2, "0.25", "¼"),
    HALF(5, "0.5", "½"),
    THREE_QUARTER(7, "0.75", "¾"),
    ONE(10, "1.0", "1"),
    ;

    val stops: Double
        get() =
            when (this) {
                ZERO -> 0.0
                QUARTER -> 0.25
                HALF -> 0.5
                THREE_QUARTER -> 0.75
                ONE -> 1.0
            }

    val pixelFractionThreshold: Double
        get() = stops / 10.0

    companion object {
        fun fromRaw(value: Int): CrushClipCompensation =
            entries.firstOrNull { it.raw == value } ?: if (value > 10) ONE else ZERO
    }
}

object LiveZebra {
    const val HIGHLIGHT_IRE = 100.0
    const val MIDTONE_IRE = 55.0
    const val MIDTONE_HALF_WIDTH_IRE = 5.0
}
