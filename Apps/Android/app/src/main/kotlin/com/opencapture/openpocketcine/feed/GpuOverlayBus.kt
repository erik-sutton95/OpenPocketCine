package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

internal val LocalGpuLive = staticCompositionLocalOf<LiveVulkanSession?> { null }

internal object GpuOverlayBus {
    // ponytail: Compose draws every scope, so nothing writes these GPU slot rects now; LiveViewScreen still forwards them.
    var wave by mutableStateOf<GpuRect?>(null)
    var parade by mutableStateOf<GpuRect?>(null)
    var histo by mutableStateOf<GpuRect?>(null)
    var vector by mutableStateOf<GpuRect?>(null)
    var platesGeneration by mutableIntStateOf(0)
        private set

    var onSlotsMoved: (() -> Unit)? = null

    private val plates = LinkedHashMap<String, FloatArray>()

    fun upsertPlate(id: String, packed: FloatArray) {
        plates[id] = packed
        platesGeneration += 1
    }

    fun removePlate(id: String) {
        if (plates.remove(id) != null) platesGeneration += 1
    }

    fun plateSnapshot(): FloatArray {
        val out = FloatArray(plates.size * GpuLiveLayout.PLATE_STRIDE)
        plates.values.forEachIndexed { i, src ->
            src.copyInto(out, i * GpuLiveLayout.PLATE_STRIDE)
        }
        return out
    }
}
