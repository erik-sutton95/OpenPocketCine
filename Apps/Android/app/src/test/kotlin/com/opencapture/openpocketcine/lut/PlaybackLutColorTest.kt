package com.opencapture.openpocketcine.lut

import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals

class PlaybackLutColorTest {
    @Test
    fun keepsLastLogWhenLiveAndFileSayRec709() {
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG,
            PlaybackLutColor.resolve(CameraCommands.COLOR_HDR, CameraCommands.COLOR_DLOG),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(-1, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(CameraCommands.COLOR_DLOG2, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(CameraCommands.COLOR_DLOG2, CameraCommands.COLOR_DLOG),
        )
        assertEquals(
            CameraCommands.COLOR_NORMAL,
            PlaybackLutColor.resolve(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_NORMAL),
        )
        assertEquals(-1, PlaybackLutColor.resolve(-1, -1))
    }

    @Test
    fun clipKeysWinOverLastLiveLog() {
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(
                CameraCommands.COLOR_DLOG2,
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_DLOG,
            ),
        )
        assertEquals(
            CameraCommands.COLOR_NORMAL,
            PlaybackLutColor.resolve(
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_DLOG2,
                CameraCommands.COLOR_DLOG2,
            ),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(-1, CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_DLOG2),
        )
    }
}
