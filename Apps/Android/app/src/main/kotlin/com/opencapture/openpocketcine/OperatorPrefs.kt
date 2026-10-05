package com.opencapture.openpocketcine

import android.content.Context
import androidx.core.content.edit
import com.opencapture.monitorui.MonitorJoystickSize
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.GamepadGimbalStick
import com.opencapture.opencine.vocabulary.ShutterAngle
import com.opencapture.openpocketcine.feed.FeedUpscaler
import com.opencapture.openpocketcine.lut.LutCatalog
import org.json.JSONObject

import com.opencapture.opencine.appkit.MonitorDisplayPreferences

typealias PocketDispMode = com.opencapture.opencine.appkit.MonitorDisplayMode
typealias PocketDispSection = com.opencapture.opencine.appkit.MonitorDisplaySection
typealias PocketDispChrome = com.opencapture.opencine.appkit.MonitorDisplayChrome

enum class PortraitFeedAspect(val raw: String) {
    FIT_16X9("fit16x9"),
    FILL("fill"),
    ;

    companion object {
        fun fromRaw(raw: String?): PortraitFeedAspect =
            entries.firstOrNull { it.raw == raw } ?: FIT_16X9
    }
}

typealias OperatorSettingsTab = com.opencapture.monitorui.settings.MonitorSettingsTab

enum class LiveOperatorPanel {
    SETTINGS,
    MEDIA,
}

object OperatorPrefs {
    private const val PREFS = "openpocketcine.operator"
    private const val AWAKE = "OpenPocketCine.KeepScreenAwake"
    private const val HDR_DISPLAY = "OpenPocketCine.HDRDisplay"
    private const val AWAKE_LEGACY = "keep-screen-awake"
    private const val RECORD_CONFIRM = "OpenPocketCine.RecordConfirmation"
    private const val HAPTICS = "OpenPocketCine.HapticsEnabled"
    private const val GIMBAL = "OpenPocketCine.GimbalStickSensitivity"
    private const val VIRTUAL_INVERT_PAN = "OpenPocketCine.VirtualJoystickInvertPan"
    private const val VIRTUAL_INVERT_TILT = "OpenPocketCine.VirtualJoystickInvertTilt"
    private const val VIRTUAL_DEADZONE_PERCENT = "OpenPocketCine.VirtualJoystickDeadzonePercent"
    private const val VIRTUAL_RESPONSE_CURVE = "OpenPocketCine.VirtualJoystickResponseCurve"
    private const val VIRTUAL_SIZE = "OpenPocketCine.VirtualJoystickSize"
    private const val GIMBAL_RAMP = "OpenPocketCine.GimbalRamp"
    private const val GIMBAL_DOUBLE_TAP = "OpenPocketCine.GimbalDoubleTap"
    private const val DISP_LIVE = "OpenPocketCine.DispChrome.Live"
    private const val DISP_CLEAN = "OpenPocketCine.DispChrome.Clean"
    private const val CLEAN_PINS = "OpenPocketCine.CleanViewPins.v1"
    private const val PORTRAIT_ASPECT = "OpenPocketCine.PortraitFeedAspect"
    private const val NATIVE_ISO_HOP = "OpenPocketCine.NativeISOHop"
    private const val FACE_PRIORITY = "OpenPocketCine.FacePriorityExposure"
    private const val SHUTTER_ANGLE = "OpenPocketCine.ShutterUsesAngle"
    private const val SHUTTER_DEGREES = "OpenPocketCine.ShutterAngleDegrees"
    private const val GIMBAL_GAMEPAD_STICK = "OpenPocketCine.GimbalGamepadStick"
    private const val LUT_SELECTION = "OpenPocketCine.LUTSelection"
    private const val LAST_MONITOR_COLOR = "OpenPocketCine.LastMonitorColorMode"
    private const val CLIP_SHOT_COLOR = "OpenPocketCine.ClipShotColor"
    private const val CACHE_FULL_RESOLUTION = "OpenPocketCine.CacheFullResolution"
    private const val ASSIST_V1 = "OpenPocketCine.Assist.v1"
    private const val ASSIST_TOOL_USAGE = "OpenPocketCine.AssistToolUsage.v1"
    private const val PLAYBACK_ASSISTS = "OpenPocketCine.PlaybackAssists.v1"
    private const val FEED_UPSCALER = "OpenPocketCine.feedUpscaler"

    const val DEFAULT_GIMBAL_SENSITIVITY = 4
    val DEFAULT_CLEAN_PINS = setOf("LUT", "PEAK", "MIRROR", "DESQ")

    /** Only absent preferences receive defaults; an explicitly empty set stays empty. */
    fun resolvedCleanPins(raw: Set<String>?): Set<String> =
        raw ?: DEFAULT_CLEAN_PINS

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
        prefs(context).edit { putBoolean(AWAKE, value) }
    }

    fun hdrDisplay(context: Context): Boolean = prefs(context).getBoolean(HDR_DISPLAY, false)

    fun setHdrDisplay(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(HDR_DISPLAY, value) }
    }

    fun recordConfirmationEnabled(context: Context): Boolean =
        prefs(context).getBoolean(RECORD_CONFIRM, true)

    fun setRecordConfirmationEnabled(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(RECORD_CONFIRM, value) }
    }

    fun hapticsEnabled(context: Context): Boolean =
        prefs(context).getBoolean(HAPTICS, true)

    fun setHapticsEnabled(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(HAPTICS, value) }
    }

    fun gimbalStickSensitivity(context: Context): Int =
        prefs(context).getInt(GIMBAL, DEFAULT_GIMBAL_SENSITIVITY).coerceIn(1, 5)

    fun setGimbalStickSensitivity(context: Context, value: Int) {
        prefs(context).edit { putInt(GIMBAL, value.coerceIn(1, 5)) }
    }

    fun virtualJoystickInvertPan(context: Context): Boolean =
        prefs(context).getBoolean(VIRTUAL_INVERT_PAN, false)

    fun setVirtualJoystickInvertPan(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(VIRTUAL_INVERT_PAN, value) }
    }

    fun virtualJoystickInvertTilt(context: Context): Boolean =
        prefs(context).getBoolean(VIRTUAL_INVERT_TILT, false)

    fun setVirtualJoystickInvertTilt(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(VIRTUAL_INVERT_TILT, value) }
    }

    fun virtualJoystickDeadzonePercent(context: Context): Int {
        val stored = prefs(context)
        val raw =
            if (stored.contains(VIRTUAL_DEADZONE_PERCENT)) stored.getInt(VIRTUAL_DEADZONE_PERCENT, 8)
            else null
        return CameraCommands.VirtualJoystickMapping.resolvedDeadzonePercent(raw)
    }

    fun setVirtualJoystickDeadzonePercent(context: Context, value: Int) {
        prefs(context).edit {
            putInt(
                VIRTUAL_DEADZONE_PERCENT,
                CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(value),
            )
        }
    }

    fun virtualJoystickResponseCurve(context: Context): CameraCommands.VirtualJoystickCurve =
        CameraCommands.VirtualJoystickCurve.parse(
            prefs(context).getString(VIRTUAL_RESPONSE_CURVE, null),
        )

    fun setVirtualJoystickResponseCurve(
        context: Context,
        value: CameraCommands.VirtualJoystickCurve,
    ) {
        prefs(context).edit { putString(VIRTUAL_RESPONSE_CURVE, value.raw) }
    }

    fun virtualJoystickSize(context: Context): MonitorJoystickSize =
        MonitorJoystickSize.parse(prefs(context).getString(VIRTUAL_SIZE, null))

    fun setVirtualJoystickSize(context: Context, value: MonitorJoystickSize) {
        prefs(context).edit { putString(VIRTUAL_SIZE, value.raw) }
    }

    fun virtualJoystickMapping(context: Context): CameraCommands.VirtualJoystickMapping =
        CameraCommands.VirtualJoystickMapping(
            invertPan = virtualJoystickInvertPan(context),
            invertTilt = virtualJoystickInvertTilt(context),
            deadzone = CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(
                virtualJoystickDeadzonePercent(context),
            ),
            curve = virtualJoystickResponseCurve(context),
        )

    fun gimbalRamp(context: Context): com.opencapture.opencine.dji.GimbalRamp =
        com.opencapture.opencine.dji.GimbalRamp.fromRaw(prefs(context).getInt(GIMBAL_RAMP, 0))

    fun setGimbalRamp(context: Context, value: com.opencapture.opencine.dji.GimbalRamp) {
        prefs(context).edit { putInt(GIMBAL_RAMP, value.raw) }
    }

    /** Stick double-tap / gamepad Circle/B. Absent key is Recenter (iOS parity). */
    fun gimbalDoubleTap(context: Context): com.opencapture.opencine.dji.GimbalDoubleTap =
        com.opencapture.opencine.dji.GimbalDoubleTap.fromRaw(prefs(context).getInt(GIMBAL_DOUBLE_TAP, 0))

    fun setGimbalDoubleTap(context: Context, value: com.opencapture.opencine.dji.GimbalDoubleTap) {
        prefs(context).edit { putInt(GIMBAL_DOUBLE_TAP, value.raw) }
    }

    private fun display(context: Context) = MonitorDisplayPreferences(
        prefs(context), MonitorDisplayPreferences.Keys(DISP_LIVE, DISP_CLEAN),
    )

    fun dispLive(context: Context): PocketDispChrome = display(context).live

    fun setDispLive(context: Context, value: PocketDispChrome) {
        display(context).live = value
    }

    fun dispClean(context: Context): PocketDispChrome =
        display(context).clean

    fun setDispClean(context: Context, value: PocketDispChrome) {
        display(context).clean = value
    }

    fun cleanViewPinnedTools(context: Context): Set<String> {
        val raw = prefs(context).getStringSet(CLEAN_PINS, null)
        return resolvedCleanPins(raw)
    }

    fun setCleanViewPinnedTools(context: Context, value: Set<String>) {
        prefs(context).edit { putStringSet(CLEAN_PINS, HashSet(resolvedCleanPins(value))) }
    }

    fun feedUpscaler(context: Context): FeedUpscaler =
        FeedUpscaler.fromStored(prefs(context).getString(FEED_UPSCALER, null))

    fun setFeedUpscaler(context: Context, value: FeedUpscaler) {
        prefs(context).edit { putString(FEED_UPSCALER, value.label) }
    }

    fun portraitFeedAspect(context: Context): PortraitFeedAspect =
        PortraitFeedAspect.fromRaw(prefs(context).getString(PORTRAIT_ASPECT, null))

    fun setPortraitFeedAspect(context: Context, value: PortraitFeedAspect) {
        prefs(context).edit { putString(PORTRAIT_ASPECT, value.raw) }
    }

    fun nativeISOHopEnabled(context: Context): Boolean =
        prefs(context).getBoolean(NATIVE_ISO_HOP, true)

    fun setNativeISOHopEnabled(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(NATIVE_ISO_HOP, value) }
    }

    fun facePriorityExposureEnabled(context: Context): Boolean =
        prefs(context).getBoolean(FACE_PRIORITY, false)

    fun setFacePriorityExposureEnabled(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(FACE_PRIORITY, value) }
    }

    fun gimbalGamepadStick(context: Context): GamepadGimbalStick =
        GamepadGimbalStick.parse(prefs(context).getString(GIMBAL_GAMEPAD_STICK, null))

    fun setGimbalGamepadStick(context: Context, value: GamepadGimbalStick) {
        prefs(context).edit { putString(GIMBAL_GAMEPAD_STICK, value.raw) }
    }

    fun shutterUsesAngle(context: Context): Boolean =
        prefs(context).getBoolean(SHUTTER_ANGLE, false)

    fun setShutterUsesAngle(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(SHUTTER_ANGLE, value) }
    }

    fun shutterAngleDegrees(context: Context): Double {
        val stored = prefs(context).getFloat(SHUTTER_DEGREES, 0f).toDouble()
        return if (stored > 0) ShutterAngle.nearestDegrees(stored) else ShutterAngle.DEFAULT_DEGREES
    }

    fun setShutterAngleDegrees(context: Context, value: Double) {
        val snapped = ShutterAngle.nearestDegrees(value)
        prefs(context).edit { putFloat(SHUTTER_DEGREES, snapped.toFloat()) }
    }

    fun lutSelection(context: Context): String {
        val stored = prefs(context).getString(LUT_SELECTION, LutCatalog.DJI_AUTO) ?: LutCatalog.DJI_AUTO
        return LutCatalog.migratedToDjiCatalog(stored)
    }

    fun setLutSelection(context: Context, value: String) {
        prefs(context).edit { putString(LUT_SELECTION, value) }
    }

    fun lastMonitorColorMode(context: Context): Int =
        if (prefs(context).contains(LAST_MONITOR_COLOR)) {
            prefs(context).getInt(LAST_MONITOR_COLOR, -1)
        } else {
            -1
        }

    fun setLastMonitorColorMode(context: Context, value: Int) {
        if (value < 0) {
            prefs(context).edit { remove(LAST_MONITOR_COLOR) }
        } else {
            prefs(context).edit { putInt(LAST_MONITOR_COLOR, value) }
        }
    }

    fun clipShotColor(context: Context, path: String): Int {
        val raw = prefs(context).getString(CLIP_SHOT_COLOR, null) ?: return -1
        return try {
            JSONObject(raw).optInt(path, -1)
        } catch (_: Exception) {
            -1
        }
    }

    fun setClipShotColor(context: Context, path: String, value: Int) {
        if (value < 0) return
        val prefs = prefs(context)
        val json =
            try {
                JSONObject(prefs.getString(CLIP_SHOT_COLOR, null) ?: "{}")
            } catch (_: Exception) {
                JSONObject()
            }
        json.put(path, value)
        prefs.edit { putString(CLIP_SHOT_COLOR, json.toString()) }
    }

    fun legacyClipShotColorJson(context: Context): JSONObject? {
        val raw = prefs(context).getString(CLIP_SHOT_COLOR, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    fun clearLegacyClipShotColor(context: Context) {
        prefs(context).edit { remove(CLIP_SHOT_COLOR) }
    }

    fun cacheFullResolution(context: Context): Boolean =
        if (prefs(context).contains(CACHE_FULL_RESOLUTION)) {
            prefs(context).getBoolean(CACHE_FULL_RESOLUTION, true)
        } else {
            true
        }

    fun setCacheFullResolution(context: Context, value: Boolean) {
        prefs(context).edit { putBoolean(CACHE_FULL_RESOLUTION, value) }
    }

    fun assistEncoded(context: Context): String? =
        prefs(context).getString(ASSIST_V1, null)

    fun setAssistEncoded(context: Context, value: String) {
        prefs(context).edit { putString(ASSIST_V1, value) }
    }

    fun assistToolUsage(context: Context): com.opencapture.monitorui.MonitorToolUsageState {
        val raw = prefs(context).getString(ASSIST_TOOL_USAGE, null) ?: return com.opencapture.monitorui.MonitorToolUsageState()
        return try {
            val obj = JSONObject(raw)
            fun doubles(key: String): Map<String, Double> {
                if (!obj.has(key)) return emptyMap()
                val child = obj.getJSONObject(key)
                return child.keys().asSequence().associateWith { child.getDouble(it) }
            }
            fun ints(key: String): Map<String, Int> {
                if (!obj.has(key)) return emptyMap()
                val child = obj.getJSONObject(key)
                return child.keys().asSequence().associateWith { child.getInt(it) }
            }
            com.opencapture.monitorui.MonitorToolUsageState(
                doubles("scores"), ints("counts"), doubles("lastUsed"), obj.optDouble("clock", 0.0),
            )
        } catch (_: Exception) {
            com.opencapture.monitorui.MonitorToolUsageState()
        }
    }

    fun setAssistToolUsage(context: Context, value: com.opencapture.monitorui.MonitorToolUsageState) {
        val scores = JSONObject()
        value.scores.forEach { scores.put(it.key, it.value) }
        val counts = JSONObject()
        value.counts.forEach { counts.put(it.key, it.value) }
        val lastUsed = JSONObject()
        value.lastUsed.forEach { lastUsed.put(it.key, it.value) }
        val obj = JSONObject()
            .put("scores", scores)
            .put("counts", counts)
            .put("lastUsed", lastUsed)
            .put("clock", value.clock)
        prefs(context).edit { putString(ASSIST_TOOL_USAGE, obj.toString()) }
    }

    fun playbackVisibleAssistTools(context: Context): Set<String> =
        prefs(context).getStringSet(PLAYBACK_ASSISTS, null)?.toSet() ?: emptySet()

    fun setPlaybackVisibleAssistTools(context: Context, value: Set<String>) {
        prefs(context).edit { putStringSet(PLAYBACK_ASSISTS, value) }
    }
}
