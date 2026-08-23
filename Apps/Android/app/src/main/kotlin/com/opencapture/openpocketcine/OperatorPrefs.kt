package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.openpocketcine.feed.FeedUpscaleSwitch
import com.opencapture.openpocketcine.feed.FeedUpscaler
import org.json.JSONObject

enum class PocketDispMode(val title: String, val settingsTitle: String, val settingsCaption: String) {
    LIVE(
        "Live",
        "DISP 1 · Live",
        "The full monitor. Set what it shows in Edit view.",
    ),
    CLEAN(
        "Clean",
        "DISP 2 · Clean",
        "A stripped-back image. Same elements as DISP 1 — status, tool and capture bars start off. Pin which view assists stay on.",
    ),
}

enum class PocketDispSection(val key: String, val title: String) {
    STATUS_BAR("statusBar", "Status Bar"),
    TOOL_BAR("toolBar", "Tool Bar"),
    CAMERA_VALUES("cameraValues", "Camera Values"),
    LOCK_BUTTON("lockButton", "Lock Button"),
    BATTERIES("batteries", "Batteries"),
    RAIL_RECORD("railRecord", "Record"),
    RAIL_MEDIA("railMedia", "Media"),
    RAIL_SETTINGS("railSettings", "Settings"),
    ZOOM_CHIP("zoomChip", "Zoom Chip"),
    GIMBAL_STICK("gimbalStick", "Gimbal Stick"),
    FOCUS_BOX("focusBox", "Face Box"),
    REC_READOUT("recReadout", "REC"),
    TIMECODE("timecode", "Timecode"),
    FORMAT("format", "Format"),
    COLOR("color", "Color"),
    STORAGE("storage", "Storage"),
    FPS("fps", "FPS"),
}

data class PocketDispChrome(
    val statusBar: Boolean = true,
    val toolBar: Boolean = true,
    val cameraValues: Boolean = true,
    val lockButton: Boolean = true,
    val batteries: Boolean = true,
    val recReadout: Boolean = true,
    val timecode: Boolean = true,
    val format: Boolean = true,
    val color: Boolean = true,
    val storage: Boolean = true,
    val fps: Boolean = true,
    val railRecord: Boolean = true,
    val railMedia: Boolean = true,
    val railSettings: Boolean = true,
    val zoomChip: Boolean = true,
    val gimbalStick: Boolean = true,
    val focusBox: Boolean = true,
) {
    fun isVisible(section: PocketDispSection): Boolean =
        when (section) {
            PocketDispSection.STATUS_BAR -> statusBar
            PocketDispSection.TOOL_BAR -> toolBar
            PocketDispSection.CAMERA_VALUES -> cameraValues
            PocketDispSection.LOCK_BUTTON -> lockButton
            PocketDispSection.BATTERIES -> batteries
            PocketDispSection.RAIL_RECORD -> railRecord
            PocketDispSection.RAIL_MEDIA -> railMedia
            PocketDispSection.RAIL_SETTINGS -> railSettings
            PocketDispSection.ZOOM_CHIP -> zoomChip
            PocketDispSection.GIMBAL_STICK -> gimbalStick
            PocketDispSection.FOCUS_BOX -> focusBox
            PocketDispSection.REC_READOUT -> recReadout
            PocketDispSection.TIMECODE -> timecode
            PocketDispSection.FORMAT -> format
            PocketDispSection.COLOR -> color
            PocketDispSection.STORAGE -> storage
            PocketDispSection.FPS -> fps
        }

    fun toggling(section: PocketDispSection): PocketDispChrome =
        when (section) {
            PocketDispSection.STATUS_BAR -> copy(statusBar = !statusBar)
            PocketDispSection.TOOL_BAR -> copy(toolBar = !toolBar)
            PocketDispSection.CAMERA_VALUES -> copy(cameraValues = !cameraValues)
            PocketDispSection.LOCK_BUTTON -> copy(lockButton = !lockButton)
            PocketDispSection.BATTERIES -> copy(batteries = !batteries)
            PocketDispSection.RAIL_RECORD -> copy(railRecord = !railRecord)
            PocketDispSection.RAIL_MEDIA -> copy(railMedia = !railMedia)
            PocketDispSection.RAIL_SETTINGS -> copy(railSettings = !railSettings)
            PocketDispSection.ZOOM_CHIP -> copy(zoomChip = !zoomChip)
            PocketDispSection.GIMBAL_STICK -> copy(gimbalStick = !gimbalStick)
            PocketDispSection.FOCUS_BOX -> copy(focusBox = !focusBox)
            PocketDispSection.REC_READOUT -> copy(recReadout = !recReadout)
            PocketDispSection.TIMECODE -> copy(timecode = !timecode)
            PocketDispSection.FORMAT -> copy(format = !format)
            PocketDispSection.COLOR -> copy(color = !color)
            PocketDispSection.STORAGE -> copy(storage = !storage)
            PocketDispSection.FPS -> copy(fps = !fps)
        }

    fun toJson(): String =
        JSONObject()
            .put("statusBar", statusBar)
            .put("toolBar", toolBar)
            .put("cameraValues", cameraValues)
            .put("lockButton", lockButton)
            .put("batteries", batteries)
            .put("recReadout", recReadout)
            .put("timecode", timecode)
            .put("format", format)
            .put("color", color)
            .put("storage", storage)
            .put("fps", fps)
            .put("railRecord", railRecord)
            .put("railMedia", railMedia)
            .put("railSettings", railSettings)
            .put("zoomChip", zoomChip)
            .put("gimbalStick", gimbalStick)
            .put("focusBox", focusBox)
            .toString()

    companion object {
        val liveDefaults = PocketDispChrome()
        val cleanDefaults =
            PocketDispChrome(
                statusBar = false,
                toolBar = false,
                cameraValues = false,
                lockButton = false,
                batteries = true,
                recReadout = true,
                timecode = true,
                format = true,
                color = true,
                storage = true,
                fps = true,
                railRecord = true,
                railMedia = true,
                railSettings = true,
                zoomChip = true,
                gimbalStick = true,
                focusBox = true,
            )

        fun fromJson(raw: String?, fallback: PocketDispChrome): PocketDispChrome {
            if (raw.isNullOrBlank()) return fallback
            return runCatching {
                val obj = JSONObject(raw)
                PocketDispChrome(
                    statusBar = obj.optBoolean("statusBar", fallback.statusBar),
                    toolBar = obj.optBoolean("toolBar", fallback.toolBar),
                    cameraValues = obj.optBoolean("cameraValues", fallback.cameraValues),
                    lockButton = obj.optBoolean("lockButton", fallback.lockButton),
                    batteries = obj.optBoolean("batteries", fallback.batteries),
                    recReadout = obj.optBoolean("recReadout", fallback.recReadout),
                    timecode = obj.optBoolean("timecode", fallback.timecode),
                    format = obj.optBoolean("format", fallback.format),
                    color = obj.optBoolean("color", fallback.color),
                    storage = obj.optBoolean("storage", fallback.storage),
                    fps = obj.optBoolean("fps", fallback.fps),
                    railRecord = obj.optBoolean("railRecord", fallback.railRecord),
                    railMedia = obj.optBoolean("railMedia", fallback.railMedia),
                    railSettings = obj.optBoolean("railSettings", fallback.railSettings),
                    zoomChip = obj.optBoolean("zoomChip", fallback.zoomChip),
                    gimbalStick = obj.optBoolean("gimbalStick", fallback.gimbalStick),
                    focusBox = obj.optBoolean("focusBox", fallback.focusBox),
                )
            }.getOrElse { fallback }
        }
    }
}

enum class PortraitFeedAspect(val raw: String) {
    FIT_16X9("fit16x9"),
    FILL("fill"),
    ;

    companion object {
        fun fromRaw(raw: String?): PortraitFeedAspect =
            entries.firstOrNull { it.raw == raw } ?: FIT_16X9
    }
}

enum class OperatorSettingsTab(val title: String, val subtitle: String, val pill: String, val rail: String) {
    LINK("Link", "Connection state and link behavior.", "LIVE", "Connection"),
    SHARING("Sharing", "Coming soon.", "SHARE", "Coming soon"),
    ASSIST("View Assist", "Behavior for live-view tools.", "ASSIST", "Scopes & overlays"),
    CONTROLS("Controls", "Touch behavior and safety.", "TOUCH", "Dials and safety"),
    DISPLAY("Display", "Live view buttons and chrome.", "VISIBILITY", "Live view"),
    STORAGE("Storage", "Local cache and integrations.", "DATA", "Cache & accounts"),
    SYSTEM("System", "App-level behavior.", "APP", "App behavior"),
}

enum class LiveOperatorPanel {
    SETTINGS,
    MEDIA,
}

object OperatorPrefs {
    private const val PREFS = "openpocketcine.operator"
    private const val AWAKE = "OpenPocketCine.KeepScreenAwake"
    private const val AWAKE_LEGACY = "keep-screen-awake"
    private const val RECORD_CONFIRM = "OpenPocketCine.RecordConfirmation"
    private const val HAPTICS = "OpenPocketCine.HapticsEnabled"
    private const val GIMBAL = "OpenPocketCine.GimbalStickSensitivity"
    private const val DISP_LIVE = "OpenPocketCine.DispChrome.Live"
    private const val DISP_CLEAN = "OpenPocketCine.DispChrome.Clean"
    private const val CLEAN_PINS = "OpenPocketCine.CleanViewPins.v1"
    private const val PORTRAIT_ASPECT = "OpenPocketCine.PortraitFeedAspect"
    private const val NATIVE_ISO_HOP = "OpenPocketCine.NativeISOHop"
    private const val FACE_PRIORITY = "OpenPocketCine.FacePriorityExposure"
    private const val SHUTTER_ANGLE = "OpenPocketCine.ShutterUsesAngle"
    private const val SHUTTER_DEGREES = "OpenPocketCine.ShutterAngleDegrees"
    private const val LUT_SELECTION = "OpenPocketCine.LUTSelection"
    private const val ASSIST_V1 = "OpenPocketCine.Assist.v1"
    private const val PLAYBACK_ASSISTS = "OpenPocketCine.PlaybackAssists.v1"
    private const val FEED_UPSCALER = "OpenPocketCine.feedUpscaler"

    const val DEFAULT_GIMBAL_SENSITIVITY = 4
    val DEFAULT_CLEAN_PINS = setOf("LUT", "PEAK", "MIRROR")

    /** Absent or empty pin set → stock LUT / PEAK / MIRROR, matching iOS load. */
    fun resolvedCleanPins(raw: Set<String>?): Set<String> =
        if (raw.isNullOrEmpty()) DEFAULT_CLEAN_PINS else raw

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun keepScreenAwake(context: Context): Boolean {
        val stored = prefs(context)
        return when {
            stored.contains(AWAKE) -> stored.getBoolean(AWAKE, true)
            stored.contains(AWAKE_LEGACY) -> stored.getBoolean(AWAKE_LEGACY, true)
            else -> true
        }
    }

    fun setKeepScreenAwake(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(AWAKE, value).apply()
    }

    fun recordConfirmationEnabled(context: Context): Boolean =
        prefs(context).getBoolean(RECORD_CONFIRM, true)

    fun setRecordConfirmationEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(RECORD_CONFIRM, value).apply()
    }

    fun hapticsEnabled(context: Context): Boolean =
        prefs(context).getBoolean(HAPTICS, true)

    fun setHapticsEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(HAPTICS, value).apply()
    }

    fun gimbalStickSensitivity(context: Context): Int =
        prefs(context).getInt(GIMBAL, DEFAULT_GIMBAL_SENSITIVITY).coerceIn(1, 5)

    fun setGimbalStickSensitivity(context: Context, value: Int) {
        prefs(context).edit().putInt(GIMBAL, value.coerceIn(1, 5)).apply()
    }

    fun dispLive(context: Context): PocketDispChrome =
        PocketDispChrome.fromJson(prefs(context).getString(DISP_LIVE, null), PocketDispChrome.liveDefaults)

    fun setDispLive(context: Context, value: PocketDispChrome) {
        prefs(context).edit().putString(DISP_LIVE, value.toJson()).apply()
    }

    fun dispClean(context: Context): PocketDispChrome =
        PocketDispChrome.fromJson(prefs(context).getString(DISP_CLEAN, null), PocketDispChrome.cleanDefaults)

    fun setDispClean(context: Context, value: PocketDispChrome) {
        prefs(context).edit().putString(DISP_CLEAN, value.toJson()).apply()
    }

    fun cleanViewPinnedTools(context: Context): Set<String> {
        val raw = prefs(context).getStringSet(CLEAN_PINS, null)
        return resolvedCleanPins(raw)
    }

    fun setCleanViewPinnedTools(context: Context, value: Set<String>) {
        prefs(context).edit().putStringSet(CLEAN_PINS, HashSet(resolvedCleanPins(value))).apply()
    }

    fun feedUpscaler(context: Context): FeedUpscaler {
        val value = FeedUpscaler.fromStored(prefs(context).getString(FEED_UPSCALER, null))
        FeedUpscaleSwitch.rendererReads = value
        return value
    }

    fun setFeedUpscaler(context: Context, value: FeedUpscaler) {
        FeedUpscaleSwitch.rendererReads = value
        prefs(context).edit().putString(FEED_UPSCALER, value.label).apply()
    }

    fun portraitFeedAspect(context: Context): PortraitFeedAspect =
        PortraitFeedAspect.fromRaw(prefs(context).getString(PORTRAIT_ASPECT, null))

    fun setPortraitFeedAspect(context: Context, value: PortraitFeedAspect) {
        prefs(context).edit().putString(PORTRAIT_ASPECT, value.raw).apply()
    }

    fun nativeISOHopEnabled(context: Context): Boolean =
        prefs(context).getBoolean(NATIVE_ISO_HOP, true)

    fun setNativeISOHopEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(NATIVE_ISO_HOP, value).apply()
    }

    fun facePriorityExposureEnabled(context: Context): Boolean =
        prefs(context).getBoolean(FACE_PRIORITY, false)

    fun setFacePriorityExposureEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(FACE_PRIORITY, value).apply()
    }

    fun shutterUsesAngle(context: Context): Boolean =
        prefs(context).getBoolean(SHUTTER_ANGLE, false)

    fun setShutterUsesAngle(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(SHUTTER_ANGLE, value).apply()
    }

    fun shutterAngleDegrees(context: Context): Double {
        val stored = prefs(context).getFloat(SHUTTER_DEGREES, 0f).toDouble()
        return if (stored > 0) ShutterAngle.nearestDegrees(stored) else ShutterAngle.DEFAULT_DEGREES
    }

    fun setShutterAngleDegrees(context: Context, value: Double) {
        val snapped = ShutterAngle.nearestDegrees(value)
        prefs(context).edit().putFloat(SHUTTER_DEGREES, snapped.toFloat()).apply()
    }

    fun lutSelection(context: Context): String =
        prefs(context).getString(LUT_SELECTION, "auto") ?: "auto"

    fun setLutSelection(context: Context, value: String) {
        prefs(context).edit().putString(LUT_SELECTION, value).apply()
    }

    fun assistEncoded(context: Context): String? =
        prefs(context).getString(ASSIST_V1, null)

    fun setAssistEncoded(context: Context, value: String) {
        prefs(context).edit().putString(ASSIST_V1, value).apply()
    }

    fun playbackVisibleAssistTools(context: Context): Set<String> =
        prefs(context).getStringSet(PLAYBACK_ASSISTS, null)?.toSet() ?: emptySet()

    fun setPlaybackVisibleAssistTools(context: Context, value: Set<String>) {
        prefs(context).edit().putStringSet(PLAYBACK_ASSISTS, value).apply()
    }
}
