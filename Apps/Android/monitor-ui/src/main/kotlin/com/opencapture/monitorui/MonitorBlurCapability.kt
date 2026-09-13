package com.opencapture.monitorui

/** Sustained sampled backdrop budget, independent of legacy Kyant/lens capabilities. */
object MonitorBlurCapability {
    const val MIN_RAM_BYTES: Long = 4L * 1024L * 1024L * 1024L

    fun isSupported(sdkInt: Int, hardwareAccelerated: Boolean = true,
        isLowRamDevice: Boolean = false, totalRamBytes: Long = Long.MAX_VALUE): Boolean =
        sdkInt >= 31 && hardwareAccelerated && !isLowRamDevice &&
            (totalRamBytes <= 0 || totalRamBytes >= MIN_RAM_BYTES)
}
