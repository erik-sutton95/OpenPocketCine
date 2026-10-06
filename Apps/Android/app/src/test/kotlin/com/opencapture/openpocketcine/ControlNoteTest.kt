package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.MonitorControlModel
import com.opencapture.opencine.core.CommandFailure
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Pocket main's write notes came from the session's send path ("ISO 800: <camera message>" on a
 * refusal) and stayed silent on a timeout or a write the camera did not show.
 */
class ControlNoteTest {
    private fun note(stage: CommandStage) = AppModel.controlNote(stage, "ISO 800")

    @Test fun writesKeepMainsNotes() {
        assertNull(note(CommandStage.Confirmed))
        assertNull(note(CommandStage.Rejected(CommandRejection.CameraRefused)), "the session already said the camera's message")
        assertNull(note(CommandStage.TimedOut))
        assertNull(note(CommandStage.Failed(CommandFailure.NOT_APPLIED)))
        assertNull(note(CommandStage.OutcomeUnknown))
        assertNull(note(CommandStage.Failed(CommandFailure.NOT_SENT)))
        assertEquals(MonitorControlModel.CONNECT_FIRST, note(CommandStage.Rejected(CommandRejection.NotConnected)))
        assertEquals(
            "ISO 800 was not sent: the camera state changed. Try again.",
            note(CommandStage.Rejected(CommandRejection.StaleEpoch)),
        )
    }
}
