package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DatalinkSocketHealthTest {
    @Test fun successfulLocalSendCannotReviveATerminatedReceiver() {
        val health = DatalinkSocketHealth()
        health.noteReceiverStarted()
        health.noteReceiverFailed()
        health.noteWriteSucceeded() // a UDP keepalive can still enter the local kernel
        assertTrue(health.needsRebuild)
        health.noteReceiverStarted()
        assertFalse(health.needsRebuild)
    }

    @Test fun transientSendFailureCanRecoverWhenTheReceiverRemainsAlive() {
        val health = DatalinkSocketHealth()
        health.noteReceiverStarted()
        health.noteWriteRejected()
        assertTrue(health.needsRebuild)
        health.noteWriteSucceeded()
        assertFalse(health.needsRebuild)
    }
}
