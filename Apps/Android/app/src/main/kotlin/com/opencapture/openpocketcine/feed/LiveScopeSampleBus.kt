package com.opencapture.openpocketcine.feed

import android.util.Log
import androidx.compose.runtime.getValue
import java.util.Locale
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Latest scope tap published off the GLES thread (main-thread). Compose
 * observes [bundle]; WAVE / PARADE / HISTO / VECTOR / LIGHTS read it.
 */
object LiveScopeSampleBus {
    var bundle by mutableStateOf(ScopeAssistBundle.EMPTY)
        private set

    var generation by mutableIntStateOf(0)
        private set

    fun publish(next: ScopeAssistBundle) {
        bundle = next
        generation += 1
    }

    fun reset() {
        bundle = ScopeAssistBundle.EMPTY
        generation = 0
        ScopeTapHzLog.reset()
    }
}

/** 2 s delivered-Hz breadcrumb vs [PocketScopeSampler.minIntervalNs]. */
internal object ScopeTapHzLog {
    private const val WINDOW_NS = 2_000_000_000L
    private var windowStartNs = 0L
    private var taps = 0

    fun note(tag: String, scopes: Int, intervalNs: Long) {
        val now = System.nanoTime()
        if (windowStartNs == 0L) windowStartNs = now
        taps += 1
        val elapsed = now - windowStartNs
        if (elapsed < WINDOW_NS) return
        val hz = taps * 1_000_000_000.0 / elapsed
        val budget = 1_000_000_000.0 / intervalNs.coerceAtLeast(1)
        Log.i(
            tag,
            "scope tap: ${"%.1f".format(Locale.US, hz)}Hz budget=${"%.0f".format(Locale.US, budget)}Hz scopes=$scopes",
        )
        taps = 0
        windowStartNs = now
    }

    fun reset() {
        windowStartNs = 0L
        taps = 0
    }
}

/** Which scopes the GLES present path should tap, and the VECTOR look. */
internal data class ScopeTapPolicy(
    val waveform: Boolean = false,
    val parade: Boolean = false,
    val histogram: Boolean = false,
    val vectorscope: Boolean = false,
    val trafficLights: Boolean = false,
    val trafficThreshold: Double = 0.0,
    val colorMode: Int = com.opencapture.openpocketcine.session.CameraCommands.COLOR_NORMAL,
    val iso: Int = ScopeExposureCeiling.REFERENCE_EI,
    val vectorLut: FeedEffectsCube? = null,
) {
    val activeScopeCount: Int
        get() = listOf(waveform, parade, histogram, vectorscope, trafficLights).count { it }

    val needsTap: Boolean
        get() = activeScopeCount > 0

    val includePoints: Boolean
        get() = waveform || parade

    val includeVectorPoints: Boolean
        get() = vectorscope

    companion object {
        val IDLE = ScopeTapPolicy()
    }
}
