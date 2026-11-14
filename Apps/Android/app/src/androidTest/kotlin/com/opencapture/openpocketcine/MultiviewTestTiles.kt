package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.multiview.MultiviewSession

/**
 * Clears a standalone test tile (one built without a stage) as the stage's Remove would: its
 * editor and link close and its member and local state go back to an empty slot. A tile inside a
 * `MultiviewSession` is cleared through `MultiviewSession.remove` instead.
 */
internal fun MultiviewSession.Tile.reset() {
    closeControls()
    close()
    camera = null
    identity = null
    controlHost = null
    cameraAddress = ""
    failureMessage = null
    recovering = false
    networkVerified = false
    experimentalNetwork = false
    recordingAvailable = false
    recordingBusy = false
    recordingNote = null
    publishing = false
    lutEnabled = true
    status = "Add camera"
    clearLocal()
}
