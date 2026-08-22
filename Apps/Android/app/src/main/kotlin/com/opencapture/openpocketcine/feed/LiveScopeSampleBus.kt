package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.getValue
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
