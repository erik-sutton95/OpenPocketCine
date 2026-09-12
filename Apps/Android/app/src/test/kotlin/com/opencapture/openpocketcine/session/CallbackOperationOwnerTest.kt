@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.opencapture.openpocketcine.session

import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CallbackOperationOwnerTest {
    @Test fun replacedQueuedStartCompletesItsOwnSuspendedCaller() = kotlinx.coroutines.test.runTest {
        val owner = CallbackOperationOwner<Any>()
        val attempt = owner.begin()
        var queuedStart: (() -> Unit)? = null
        var failed = false
        val job = launch {
            try {
                kotlinx.coroutines.suspendCancellableCoroutine<Unit> { continuation ->
                    queuedStart = {
                        runOwnedConnectionStart(owner, attempt, continuation) {
                            error("replaced start must not open GATT")
                        }
                    }
                }
            } catch (_: IllegalStateException) { failed = true }
        }
        runCurrent()
        owner.begin() // disconnect or new connect before worker handles the start
        queuedStart!!()
        runCurrent()
        val completed = job.isCompleted
        job.cancel() // always clean up the pre-fix suspended caller
        assertTrue(completed, "rejected start must finish the continuation it never installed")
        assertTrue(failed)
    }

    @Test
    fun delayedOldCancellationCannotUnbindReplacementRequest() {
        val owner = CallbackOperationOwner<Any>()
        val first = owner.begin()
        val cancelledOldRequest = { owner.runIfCurrent(first) { error("old request unbound current network") } }
        val replacement = owner.begin()
        assertFalse(cancelledOldRequest())
        assertTrue(owner.runIfCurrent(replacement) {})
    }

    @Test
    fun queuedConnectCannotStartAfterDisconnectOrReplacement() {
        val owner = CallbackOperationOwner<Any>()
        val first = owner.begin()
        var connections = 0
        val queuedConnect = { owner.runIfCurrent(first) { connections++ } }
        val disconnect = owner.begin()
        assertFalse(queuedConnect())
        owner.finish(disconnect)
        assertEquals(0, connections)
    }

    @Test
    fun oldGattCannotReportLossOrCompleteNewPairing() {
        val owner = CallbackOperationOwner<Any>()
        val firstGatt = Any()
        val secondGatt = Any()
        val first = owner.begin()
        owner.attach(first, firstGatt)
        val second = owner.begin()
        owner.attach(second, secondGatt)
        var events = 0
        assertFalse(owner.runIfCurrent(first, firstGatt) { events++ })
        assertFalse(owner.runIfCurrent(second, firstGatt) { events++ })
        assertTrue(owner.runIfCurrent(second, secondGatt) { events++ })
        assertEquals(1, events)
    }

    @Test
    fun oldTimeoutCannotRetireNewConnectionOrClearItsWritePacing() {
        val owner = CallbackOperationOwner<Any>()
        val first = owner.begin()
        val second = owner.begin()
        var writing = true
        assertFalse(owner.runIfCurrent(first) { writing = false; owner.finish(first) })
        assertTrue(writing)
        assertTrue(owner.runIfCurrent(second) {})
    }
}
