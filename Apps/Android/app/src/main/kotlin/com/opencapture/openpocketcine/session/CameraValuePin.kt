package com.opencapture.openpocketcine.session

/** A pending choice is confirmed only by its field in the current camera report. */
data class CameraValuePin<T>(val expected: T, val deadlineElapsed: Long) {
    companion object {
        /** Every control gives the body this long to answer before the HUD drops back to live. */
        const val SETTLE_MS = 2_000L

        /**
         * Returns the held value, or releases the pin on confirmation/expiry.
         *
         * [confirms] decides when the body has answered the ask. Exact equality suits the
         * enum-shaped controls; zoom hands in [CamFov.matches], because its live factor is derived
         * from a lens position and lands a hair off the number that was asked for.
         */
        fun <T> reconcile(
            pin: CameraValuePin<T>?,
            reported: T?,
            now: Long,
            confirms: (T, T) -> Boolean = { a, b -> a == b },
        ): Pair<T?, CameraValuePin<T>?> {
            if (pin == null) return null to null
            val answered = reported != null && confirms(reported, pin.expected)
            if (now >= pin.deadlineElapsed || answered) return null to null
            return pin.expected to pin
        }
    }
}
