package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.bridge.SwiftCore
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

/**
 * Slow-motion conform preview: play a high-frame-rate clip at the rate it will
 * be conformed to in the edit. Preview only — never rewrites the file.
 *
 * Probe prefers the shared Swift [ConformPreview] over JNI when the core is
 * loaded; the local algorithm matches `OpenPocketViewCore` for JVM tests.
 */
object ConformPreview {
    val targetRates: List<Double> = listOf(23.976, 24.0, 25.0, 29.97, 30.0)
    const val rateTolerance: Double = 0.01
    const val conformFloor: Double = 0.99
    const val audioLabel: String = "Audio muted during conform preview"

    val cinemaRates: List<Double> =
        listOf(
            23.976, 24.0, 25.0, 29.97, 30.0, 47.952, 48.0, 50.0, 59.94, 60.0,
            100.0, 119.88, 120.0, 240.0,
        )

    data class Source(
        val captureRate: Double? = null,
        val isVariableFrameRate: Boolean = false,
        val isAlreadyConformed: Boolean = false,
    )

    sealed class Availability {
        data class Available(val rates: List<Double>) : Availability()
        data object UnknownRate : Availability()
        data object VariableRate : Availability()
        data object AlreadyConformed : Availability()
        data object NotHighFrameRate : Availability()

        val targets: List<Double>
            get() = (this as? Available)?.rates.orEmpty()

        val isAvailable: Boolean
            get() = targets.isNotEmpty()

        val unavailableReason: String?
            get() =
                when (this) {
                    is Available -> null
                    UnknownRate -> "Frame rate unavailable for this clip"
                    VariableRate -> "Variable frame rate — conform preview unavailable"
                    AlreadyConformed -> "Already conformed in camera"
                    NotHighFrameRate -> "Not a high-frame-rate clip"
                }
    }

    fun availability(source: Source): Availability {
        val rate = source.captureRate
        if (rate == null || !rate.isFinite() || rate <= 0.0) return Availability.UnknownRate
        if (source.isVariableFrameRate) return Availability.VariableRate
        if (source.isAlreadyConformed) return Availability.AlreadyConformed
        val targets = targetRates.filter { it < rate * conformFloor }
        return if (targets.isEmpty()) Availability.NotHighFrameRate else Availability.Available(targets)
    }

    fun probe(
        nominalFrameRate: Double? = null,
        minFrameDurationSeconds: Double? = null,
        listedRate: Double? = null,
    ): Source {
        if (SwiftCore.isAvailable) {
            nativeProbe(nominalFrameRate, minFrameDurationSeconds, listedRate)?.let { return it }
        }
        return probeLocal(nominalFrameRate, minFrameDurationSeconds, listedRate)
    }

    fun probeLocal(
        nominalFrameRate: Double? = null,
        minFrameDurationSeconds: Double? = null,
        listedRate: Double? = null,
    ): Source {
        val assetRates = ArrayList<Double>(2)
        usableRate(nominalFrameRate)?.let { assetRates.add(it) }
        if (minFrameDurationSeconds != null && minFrameDurationSeconds.isFinite() && minFrameDurationSeconds > 0) {
            usableRate(1.0 / minFrameDurationSeconds)?.let { assetRates.add(it) }
        }
        val snappedAsset = uniqueSnapped(assetRates)
        val capture = snappedAsset.maxOrNull()
        if (capture != null) {
            val varies =
                snappedAsset.any { candidate ->
                    !isIntegerMultiple(capture, candidate) &&
                        abs(capture - candidate) / max(capture, 1.0) > 0.08
                }
            return Source(captureRate = capture, isVariableFrameRate = varies)
        }
        val raw = assetRates.maxOrNull()
        if (raw != null) return Source(captureRate = raw)
        val listed = snap(listedRate) ?: usableRate(listedRate)
        if (listed != null) return Source(captureRate = listed)
        return Source()
    }

    fun snap(rate: Double?): Double? {
        val usable = usableRate(rate) ?: return null
        val nearest = cinemaRates.minByOrNull { abs(it - usable) } ?: return null
        val tolerance = max(0.51, nearest * 0.03)
        return if (abs(nearest - usable) <= tolerance) nearest else null
    }

    fun speed(captureRate: Double, targetRate: Double): Double {
        if (!captureRate.isFinite() || captureRate <= 0 || !targetRate.isFinite() || targetRate <= 0) {
            return 1.0
        }
        return targetRate / captureRate
    }

    fun conformedDuration(sourceSeconds: Double, speed: Double): Double {
        if (!sourceSeconds.isFinite() || sourceSeconds < 0 || !speed.isFinite() || speed <= 0) {
            return 0.0
        }
        return sourceSeconds / speed
    }

    fun rateLabel(rate: Double): String {
        if (!rate.isFinite() || rate <= 0) return "—"
        val whole = round(rate)
        return if (abs(rate - whole) < rateTolerance) {
            whole.toInt().toString()
        } else {
            String.format(Locale.US, "%.2f", rate)
        }
    }

    fun label(captureRate: Double, targetRate: Double): String {
        val percent = speed(captureRate, targetRate) * 100
        return "${rateLabel(captureRate)} → ${rateLabel(targetRate)} fps · ${percentLabel(percent)}%"
    }

    fun targetLabel(captureRate: Double, targetRate: Double): String {
        val percent = speed(captureRate, targetRate) * 100
        return "${rateLabel(targetRate)} fps · ${percentLabel(percent)}%"
    }

    fun menuHeader(captureRate: Double): String = "Conform ${rateLabel(captureRate)} fps to"

    private fun percentLabel(percent: Double): String =
        if (abs(percent - round(percent)) < 0.05) {
            round(percent).toInt().toString()
        } else {
            String.format(Locale.US, "%.1f", percent)
        }

    private fun usableRate(rate: Double?): Double? {
        if (rate == null || !rate.isFinite() || rate <= 1.0 || rate > 250.0) return null
        return rate
    }

    private fun uniqueSnapped(rates: List<Double>): List<Double> {
        val seen = HashSet<Double>()
        val out = ArrayList<Double>()
        for (rate in rates) {
            val snapped = snap(rate) ?: continue
            if (seen.add(snapped)) out.add(snapped)
        }
        return out
    }

    private fun isIntegerMultiple(a: Double, b: Double): Boolean {
        val hi = max(a, b)
        val lo = min(a, b)
        if (lo <= 0) return false
        val ratio = hi / lo
        val nearest = round(ratio)
        return nearest >= 1 && abs(ratio - nearest) < 0.06
    }

    private fun nativeProbe(
        nominalFrameRate: Double?,
        minFrameDurationSeconds: Double?,
        listedRate: Double?,
    ): Source? {
        val request =
            JSONObject().apply {
                if (nominalFrameRate != null) put("nominalFrameRate", nominalFrameRate)
                if (minFrameDurationSeconds != null) put("minFrameDurationSeconds", minFrameDurationSeconds)
                if (listedRate != null) put("listedRate", listedRate)
            }
        val raw = runCatching { SwiftCore.conformPreviewJSON(request.toString()) }.getOrNull()
        if (raw.isNullOrBlank() || raw == "{}") return null
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        val rate =
            if (obj.has("captureRate") && !obj.isNull("captureRate")) {
                obj.optDouble("captureRate").takeIf { it.isFinite() && it > 0 }
            } else {
                null
            }
        return Source(
            captureRate = rate,
            isVariableFrameRate = obj.optBoolean("isVariableFrameRate", false),
            isAlreadyConformed = obj.optBoolean("isAlreadyConformed", false),
        )
    }
}

/** Decision for a tap on the letterboxed playback frame. */
enum class PlaybackFrameTap {
    RESTART_PLAYBACK,
    TOGGLE_TRANSPORT,
    IGNORE,
    ;

    companion object {
        fun action(@Suppress("UNUSED_PARAMETER") chromeVisible: Boolean, reachedEnd: Boolean): PlaybackFrameTap =
            if (reachedEnd) RESTART_PLAYBACK else TOGGLE_TRANSPORT
    }
}

/** Letterbox the video raster in a container — OpenZCine `aspectFitRect`. */
object PlaybackVideoLayout {
    data class Size(val width: Float, val height: Float)

    data class Rect(val x: Float, val y: Float, val width: Float, val height: Float) {
        val minX: Float
            get() = x
        val minY: Float
            get() = y
        val maxX: Float
            get() = x + width
        val maxY: Float
            get() = y + height
        val midX: Float
            get() = x + width / 2f
        val midY: Float
            get() = y + height / 2f
    }

    fun aspectFitRect(videoSize: Size, container: Rect): Rect {
        if (videoSize.width <= 0f || videoSize.height <= 0f || container.width <= 0f || container.height <= 0f) {
            return container
        }
        val scale = min(container.width / videoSize.width, container.height / videoSize.height)
        val width = videoSize.width * scale
        val height = videoSize.height * scale
        return Rect(
            x = container.midX - width / 2f,
            y = container.midY - height / 2f,
            width = width,
            height = height,
        )
    }

    fun sizeFromResolution(listed: String?): Size? {
        if (listed.isNullOrBlank()) return null
        val parts = listed.split('x', 'X', '×', '*')
        if (parts.size != 2) return null
        val width = parts[0].toFloatOrNull() ?: return null
        val height = parts[1].toFloatOrNull() ?: return null
        if (width <= 1f || height <= 1f) return null
        return Size(width, height)
    }
}
