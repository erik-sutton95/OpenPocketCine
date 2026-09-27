package com.opencapture.openpocketcine.session

import android.os.DeadObjectException
import android.os.RemoteException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class BleBinderFailureTest {
    @Test
    fun onlyBinderDeathsAreDeadBinder() {
        val cases = listOf(
            "dead object" to (DeadObjectException() to true),
            "remote exception" to (RemoteException("binder") to true),
            "wrapped dead object" to (RuntimeException("write", DeadObjectException()) to true),
            "doubly wrapped dead object" to
                (RuntimeException("outer", IllegalStateException("mid", DeadObjectException())) to true),
            "payload too long" to (IllegalArgumentException("too long") to false),
            "missing permission" to (SecurityException("BLUETOOTH_CONNECT") to false),
            "plain write failure" to (RuntimeException("write failed") to false),
        )
        for ((label, case) in cases) {
            val (error, dead) = case
            assertEquals(dead, BleBinderFailure.isDeadBinder(error), label)
        }
    }

    @Test
    fun cyclicCauseDoesNotLoop() {
        val a = RuntimeException("a")
        val b = RuntimeException("b", a)
        a.initCause(b)
        assertFalse(BleBinderFailure.isDeadBinder(a))
    }
}
