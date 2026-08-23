package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.opencapture.openpocketcine.assists.LiveAssistTool

internal val LocalGpuLive = staticCompositionLocalOf<LiveVulkanSession?> { null }

internal object GpuOverlayBus {
    var wave by mutableStateOf<GpuRect?>(null)
    var parade by mutableStateOf<GpuRect?>(null)
    var histo by mutableStateOf<GpuRect?>(null)
    var vector by mutableStateOf<GpuRect?>(null)
    /** LiveAssistLayer top-leading in root pixels — slot math during drag. */
    var layerRoot by mutableStateOf(androidx.compose.ui.geometry.Offset.Zero)
    var platesGeneration by mutableIntStateOf(0)
        private set

    var onSlotsMoved: (() -> Unit)? = null

    private val plates = LinkedHashMap<String, FloatArray>()

    fun usesGpuSlot(tool: LiveAssistTool): Boolean = false

    fun reportSlot(tool: LiveAssistTool, rect: GpuRect?) {
        val changed =
            when (tool) {
                LiveAssistTool.WAVE -> if (wave == rect) false else { wave = rect; true }
                LiveAssistTool.PARADE -> if (parade == rect) false else { parade = rect; true }
                LiveAssistTool.HISTO -> if (histo == rect) false else { histo = rect; true }
                LiveAssistTool.VECTOR -> if (vector == rect) false else { vector = rect; true }
                else -> false
            }
        if (changed) onSlotsMoved?.invoke()
    }

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
