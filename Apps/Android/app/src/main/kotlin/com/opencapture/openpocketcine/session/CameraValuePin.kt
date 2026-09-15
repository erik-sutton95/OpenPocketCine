package com.opencapture.openpocketcine.session

/** A pending choice is confirmed only by its field in the current camera report. */
data class CameraValuePin<T>(val expected: T, val deadlineElapsed: Long) {
    companion object {
        fun <T> reconcile(pin: CameraValuePin<T>?, reported: T?, now: Long): Pair<T?, CameraValuePin<T>?> {
            if (pin == null || now >= pin.deadlineElapsed || reported == pin.expected) return null to null
            return pin.expected to pin
        }
    }
}
