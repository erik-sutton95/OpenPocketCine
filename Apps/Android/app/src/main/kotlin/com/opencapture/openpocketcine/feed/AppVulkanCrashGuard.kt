package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.runtime.VulkanCrashGuard
import com.opencapture.openpocketcine.BuildConfig

/** The process-wide Vulkan crash-loop guard with this app's preferences file and version code. */
internal val appVulkanCrashGuard = VulkanCrashGuard("openpocketcine.vulkan_guard", BuildConfig.VERSION_CODE)
