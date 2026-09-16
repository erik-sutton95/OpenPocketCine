package com.opencapture.openpocketcine.session

import android.os.DeadObjectException
import android.os.RemoteException
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BleBinderFailureTest {
    @Test
    fun deadObjectIsDeadBinder() {
        assertTrue(BleBinderFailure.isDeadBinder(DeadObjectException()))
    }

    @Test
    fun remoteExceptionIsDeadBinder() {
        assertTrue(BleBinderFailure.isDeadBinder(RemoteException("binder")))
    }

    @Test
    fun wrappedDeadObjectIsDeadBinder() {
        assertTrue(BleBinderFailure.isDeadBinder(RuntimeException("write", DeadObjectException())))
        assertTrue(
            BleBinderFailure.isDeadBinder(
                RuntimeException("outer", IllegalStateException("mid", DeadObjectException())),
            ),
        )
    }

    @Test
    fun payloadAndSecurityErrorsAreNotDeadBinder() {
        assertFalse(BleBinderFailure.isDeadBinder(IllegalArgumentException("too long")))
        assertFalse(BleBinderFailure.isDeadBinder(SecurityException("BLUETOOTH_CONNECT")))
        assertFalse(BleBinderFailure.isDeadBinder(RuntimeException("write failed")))
    }

    @Test
    fun cyclicCauseDoesNotLoop() {
        val a = RuntimeException("a")
        val b = RuntimeException("b", a)
        a.initCause(b)
        assertFalse(BleBinderFailure.isDeadBinder(a))
    }
}
