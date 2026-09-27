package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.EvComp

/**
 * Auto-expo face priority. Matches core `FacePriorityExposure`.
 * The body takes EV thirds (`setEv`); disabling restores the saved EV.
 */
object FacePriorityExposure {
    fun restoreEV(saved: EvComp?): EvComp = saved ?: EvComp.ZERO

    /** Write on disable, or null when already there / not Auto. */
    fun restoreWrite(saved: EvComp?, expoIsAuto: Boolean, current: EvComp?): EvComp? {
        if (!expoIsAuto) return null
        val restore = restoreEV(saved)
        return restore.takeIf { it != current }
    }
}
