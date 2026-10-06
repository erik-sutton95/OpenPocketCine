package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.staticCompositionLocalOf

internal val LocalGpuLive = staticCompositionLocalOf<LiveVulkanSession?> { null }

/** The app Vulkan session hears when assist slots move. */
internal object GpuOverlayBus {
    var onSlotsMoved: (() -> Unit)? = null
}
