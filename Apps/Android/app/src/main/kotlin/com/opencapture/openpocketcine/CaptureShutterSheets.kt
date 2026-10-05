package com.opencapture.openpocketcine

import com.opencapture.opencine.vocabulary.CaptureShutterPolicy

// Sheet navigation for stills: the capture policy lives in OpenCine's DJI module, the sheets here.

fun CaptureShutterPolicy.portraitSetupSheet(shootingMode: Int): LiveSheet =
    if (portraitSetupOpensMode(shootingMode)) LiveSheet.MODE else LiveSheet.FORMAT

fun CaptureShutterPolicy.opening(sheet: LiveSheet, shootingMode: Int): LiveSheet =
    if (!isStillCapture(shootingMode)) sheet
    else when (sheet) {
        LiveSheet.FORMAT, LiveSheet.COLOR -> LiveSheet.MODE
        else -> sheet
    }

fun CaptureShutterPolicy.retainedSheet(sheet: LiveSheet?, shootingMode: Int): LiveSheet? {
    if (sheet == null || !isStillCapture(shootingMode)) return sheet
    return when (sheet) {
        LiveSheet.FORMAT, LiveSheet.COLOR -> LiveSheet.MODE
        LiveSheet.AUDIO -> null
        else -> sheet
    }
}
