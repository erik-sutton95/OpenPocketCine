package com.opencapture.openpocketcine.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReliableCursorTest {
    @Test
    fun reliableCursorAcceptsForwardProgressAndRejectsRewind() {
        assertTrue(isForwardReliableCursor(current = 0x1000, candidate = 0x1020))
        assertFalse(isForwardReliableCursor(current = 0x1020, candidate = 0x0FF8))
        assertFalse(isForwardReliableCursor(current = 0x1020, candidate = 0x1020))
    }

    @Test
    fun reliableCursorAdvancesAcrossUInt16Wrap() {
        assertTrue(isForwardReliableCursor(current = 0xFFF8, candidate = 0x0008))
        assertFalse(isForwardReliableCursor(current = 0x0008, candidate = 0xFFF8))
    }
}
