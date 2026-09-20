package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DatalinkHandshakeAdmissionTest {
    @Test fun shortAckCannotRegisterBeforeInitialWindow() {
        val admission = DatalinkHandshakeAdmission()
        admission.reset(1)
        admission.receive(packet(0, 15, 1), 1)
        assertNull(admission.initialCommandSequence(), "The short ACK has no command window")
        admission.receive(packet(1, 34, 0x6000), 1)
        assertEquals(0x6008, admission.initialCommandSequence())
    }

    @Test fun telemetryBeforeAckStillRequiresBothAndLatchesTheInitialWindow() {
        val admission = DatalinkHandshakeAdmission()
        admission.reset(1)
        admission.receive(packet(1, 34, 0x6000), 1)
        assertNull(admission.initialCommandSequence())
        admission.receive(packet(0, 15, 1), 1)
        admission.receive(packet(1, 34, 0x6010), 1)
        assertEquals(0x6008, admission.initialCommandSequence())
    }

    @Test fun longStatusAndOtherPacketTypesCannotSubstituteForWindow() {
        val admission = DatalinkHandshakeAdmission()
        admission.reset(1)
        admission.receive(packet(0, 15, 1), 1)
        for (input in listOf(packet(1, 91, 0x6000), packet(1, 33, 0x6000),
                packet(2, 34, 0x6000), packet(3, 34, 0x6000))) {
            admission.receive(input, 1)
            assertNull(admission.initialCommandSequence())
        }
        admission.receive(packet(1, 34, 0x6000), 1)
        assertEquals(0x6008, admission.initialCommandSequence())
    }

    @Test fun zeroAndWraparoundAreValidWindowSequences() {
        for ((channel, next) in listOf(0 to 8, 0xfff8 to 0)) {
            val admission = DatalinkHandshakeAdmission()
            admission.reset(1)
            admission.receive(packet(0, 15, 1), 1)
            admission.receive(packet(1, 34, channel), 1)
            assertEquals(next, admission.initialCommandSequence())
        }
    }

    @Test fun retiredEpochCannotAcknowledgeOrSeedReplacement() {
        val admission = DatalinkHandshakeAdmission()
        admission.reset(1)
        admission.receive(packet(0, 15, 1), 1)
        admission.reset(2)
        admission.receive(packet(1, 34, 0x6000), 1)
        admission.receive(packet(0, 15, 1), 1)
        assertNull(admission.initialCommandSequence())
        admission.receive(packet(1, 34, 0x9000), 2)
        admission.reset(1)
        admission.receive(packet(0, 15, 1), 2)
        assertEquals(0x9008, admission.initialCommandSequence())
    }

    private fun packet(type: Int, count: Int, channel: Int): ByteArray = ByteArray(count).also {
        it[6] = type.toByte()
        it[8] = channel.toByte()
        it[9] = (channel ushr 8).toByte()
    }
}
