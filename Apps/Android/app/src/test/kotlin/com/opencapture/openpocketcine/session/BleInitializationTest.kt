package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BleInitializationTest {
    private val fff4 = BleInitialization.Channel.FFF4
    private val fff5 = BleInitialization.Channel.FFF5

    @Test fun rejectedFff4DescriptorWithoutCallbackContinuesToFff5() {
        for (rejection in rejections()) {
            val fixture = Fixture(notifyResult = { if (it == fff4) rejection else BleRequestResult.Accepted })
            fixture.initialization.servicesDiscovered()
            assertEquals(listOf(fff4, fff5), fixture.notifications)
            assertEquals(0, fixture.arms)
            fixture.initialization.notificationWritten(fff5, 0)
            assertEquals(1, fixture.arms)
            assertFalse(fixture.completed, "Admission is not pairing-arm completion")
            fixture.initialization.armWritten(0)
            assertTrue(fixture.completed)
            assertNull(fixture.failure)
        }
    }

    @Test fun rejectedFff5DescriptorWithoutCallbackStillPermitsPairingArm() {
        for (rejection in rejections()) {
            val fixture = Fixture(notifyResult = { if (it == fff5) rejection else BleRequestResult.Accepted })
            fixture.initialization.servicesDiscovered()
            fixture.initialization.notificationWritten(fff4, 0)
            assertEquals(1, fixture.arms)
            assertFalse(fixture.completed)
        }
    }

    @Test fun missingFff4CccdAndHandledFailureAdvanceInsteadOfWaitingForImpossibleCallback() {
        for (fallback in listOf(BleRequestResult.MissingDescriptor, BleRequestResult.HandledFailure)) {
            val fixture = Fixture(notifyResult = { if (it == fff4) fallback else BleRequestResult.Accepted })
            fixture.initialization.servicesDiscovered()
            assertEquals(listOf(fff4, fff5), fixture.notifications)
            fixture.initialization.notificationWritten(fff5, 0)
            assertEquals(1, fixture.arms)
            assertFalse(fixture.completed)
        }
    }

    @Test fun rejectedFff4LocalRegistrationFailsOnceWithoutFff5OrArm() {
        assertRequiredLocalFailure { false }
    }

    @Test fun throwingFff4LocalRegistrationCannotFallThroughDescriptorTolerance() {
        assertRequiredLocalFailure { throw IllegalStateException("private platform detail") }
    }

    private fun assertRequiredLocalFailure(enableLocal: () -> Boolean) {
        val descriptors = mutableListOf<BleInitialization.Channel>()
        val fixture = Fixture(notifyResult = { channel ->
            admitBleNotification(
                enableLocal = enableLocal,
                writeDescriptor = { descriptors += channel; BleRequestResult.Accepted },
            )
        })
        fixture.initialization.servicesDiscovered()
        assertTrue(fixture.completed, "Required local notification registration must fail promptly")
        assertEquals("Bluetooth notification setup failed", assertNotNull(fixture.failure).message)
        assertEquals(listOf(fff4), fixture.notifications)
        assertTrue(descriptors.isEmpty())
        assertEquals(0, fixture.arms)
        assertTrue(fixture.journal.any { it.contains("stage=fff4_notify") && it.endsWith("reason=local_registration") })
        assertFalse(fixture.journal.any { it.contains("private platform detail") })
        fixture.initialization.notificationWritten(fff4, 0)
        fixture.initialization.notificationWritten(fff5, 0)
        fixture.initialization.armWritten(0)
        fixture.initialization.servicesDiscovered()
        assertEquals(listOf(fff4), fixture.notifications)
        assertEquals(0, fixture.arms)
        assertEquals(1, fixture.completions)
    }

    @Test fun rejectedAndThrowingFff5LocalRegistrationRemainTolerated() {
        for (throws in listOf(false, true)) {
            val descriptors = mutableListOf<BleInitialization.Channel>()
            val fixture = Fixture(notifyResult = { channel ->
                admitBleNotification(
                    enableLocal = {
                        if (channel == fff4) true
                        else if (throws) throw IllegalStateException("private platform detail")
                        else false
                    },
                    writeDescriptor = { descriptors += channel; BleRequestResult.Accepted },
                )
            })
            fixture.initialization.servicesDiscovered()
            fixture.initialization.notificationWritten(fff4, 0)
            assertEquals(listOf(fff4, fff5), fixture.notifications)
            assertEquals(listOf(fff4), descriptors)
            assertEquals(1, fixture.arms)
            assertFalse(fixture.completed)
            fixture.initialization.armWritten(0)
            assertTrue(fixture.completed)
            assertNull(fixture.failure)
        }
    }

    @Test fun deadBinderDuringLocalRegistrationKeepsCleanupWithTheLinkOwner() {
        var closes = 0
        val fixture = Fixture(notifyResult = {
            admitBleNotification(
                enableLocal = { throw android.os.DeadObjectException() },
                writeDescriptor = { error("Dead binder cannot submit a descriptor") },
                closeIfDeadBinder = { error ->
                    BleBinderFailure.isDeadBinder(error).also { if (it) closes++ }
                },
            )
        })
        fixture.initialization.servicesDiscovered()
        fixture.initialization.notificationWritten(fff4, 0)
        fixture.initialization.armWritten(0)
        assertEquals(1, closes)
        assertEquals(listOf(fff4), fixture.notifications)
        assertEquals(0, fixture.arms)
        assertFalse(fixture.completed, "Link cleanup already fails the pending connection")
    }

    @Test fun rejectedPairingArmFailsImmediatelyWithoutWaitingForCallback() {
        for (rejection in rejections()) {
            val fixture = Fixture(armResult = rejection)
            fixture.initialization.servicesDiscovered()
            fixture.initialization.notificationWritten(fff4, 0)
            fixture.initialization.notificationWritten(fff5, 0)
            assertEquals(1, fixture.arms)
            assertTrue(fixture.completed, "Rejected arm cannot produce its required success callback")
            assertEquals("pairing arm failed", assertNotNull(fixture.failure).message)
        }
    }

    @Test fun healthyCommandsStayOrderedAndSuccessRequiresSuccessfulArmCallback() {
        val fixture = Fixture()
        fixture.initialization.servicesDiscovered()
        assertEquals(listOf(fff4), fixture.notifications)
        fixture.initialization.notificationWritten(fff4, 0)
        assertEquals(listOf(fff4, fff5), fixture.notifications)
        assertEquals(0, fixture.arms)
        fixture.initialization.notificationWritten(fff5, 0)
        assertEquals(1, fixture.arms)
        assertFalse(fixture.completed)
        fixture.initialization.armWritten(0)
        assertTrue(fixture.completed)
        assertNull(fixture.failure)
        assertEquals(1, fixture.completions)
    }

    @Test fun fff5FailureCallbackRemainsToleratedButArmFailureDoesNot() {
        val fixture = Fixture()
        fixture.initialization.servicesDiscovered()
        fixture.initialization.notificationWritten(fff4, 0)
        fixture.initialization.notificationWritten(fff5, 3)
        assertEquals(1, fixture.arms)
        assertFalse(fixture.completed)
        fixture.initialization.armWritten(3)
        assertTrue(fixture.completed)
        assertNotNull(fixture.failure)
    }

    @Test fun deadBinderAbortAndRetiredAttemptCannotAdvanceOrComplete() {
        val closed = Fixture(notifyResult = { BleRequestResult.LinkClosed })
        closed.initialization.servicesDiscovered()
        closed.initialization.notificationWritten(fff4, 0)
        closed.initialization.armWritten(0)
        assertEquals(listOf(fff4), closed.notifications)
        assertEquals(0, closed.arms)
        assertFalse(closed.completed, "BleLink already owns dead-binder failure cleanup")
        val retired = Fixture()
        retired.initialization.close()
        retired.initialization.servicesDiscovered()
        retired.initialization.notificationWritten(fff4, 0)
        retired.initialization.armWritten(0)
        assertTrue(retired.notifications.isEmpty())
        assertFalse(retired.completed)
    }

    @Test fun duplicateOrOutOfOrderCallbacksCannotSendExtraCommandsOrCompleteEarly() {
        val fixture = Fixture()
        fixture.initialization.armWritten(0)
        fixture.initialization.notificationWritten(fff5, 0)
        assertFalse(fixture.completed)
        fixture.initialization.servicesDiscovered()
        fixture.initialization.servicesDiscovered()
        fixture.initialization.notificationWritten(fff5, 0)
        assertEquals(listOf(fff4), fixture.notifications)
        fixture.initialization.notificationWritten(fff4, 0)
        fixture.initialization.notificationWritten(fff4, 0)
        fixture.initialization.notificationWritten(fff5, 0)
        fixture.initialization.notificationWritten(fff5, 0)
        fixture.initialization.armWritten(0)
        fixture.initialization.armWritten(0)
        assertEquals(listOf(fff4, fff5), fixture.notifications)
        assertEquals(1, fixture.arms)
        assertEquals(1, fixture.completions)
    }

    @Test fun lateCallbackForLocallyRejectedFff4CannotAdvanceTheCurrentFff5Request() {
        val fixture = Fixture(notifyResult = {
            if (it == fff4) BleRequestResult.Rejected(201) else BleRequestResult.Accepted
        })
        fixture.initialization.servicesDiscovered()
        fixture.initialization.notificationWritten(fff4, 0)
        assertEquals(listOf(fff4, fff5), fixture.notifications)
        assertEquals(0, fixture.arms)
        fixture.initialization.notificationWritten(fff5, 0)
        assertEquals(1, fixture.arms)
    }

    @Test fun ownerFenceRejectsRetiredGattBeforeItCanCompleteCurrentInitialization() {
        val owner = CallbackOperationOwner<Any>()
        val firstGatt = Any()
        val secondGatt = Any()
        val first = owner.begin().also { owner.attach(it, firstGatt) }
        val old = Fixture()
        old.initialization.servicesDiscovered()
        val current = owner.begin().also { owner.attach(it, secondGatt) }
        old.initialization.close()
        val replacement = Fixture()
        replacement.initialization.servicesDiscovered()
        assertFalse(owner.runIfCurrent(first, firstGatt) { replacement.initialization.armWritten(0) })
        assertFalse(owner.runIfCurrent(current, firstGatt) { replacement.initialization.notificationWritten(fff4, 0) })
        assertEquals(listOf(fff4), replacement.notifications)
        assertFalse(replacement.completed)
        assertTrue(owner.runIfCurrent(current, secondGatt) { replacement.initialization.notificationWritten(fff4, 0) })
        assertEquals(listOf(fff4, fff5), replacement.notifications)
    }

    @Test fun timeoutBreadcrumbNamesTheLastStageAndMonotonicElapsedTimeWithoutChangingCompletion() {
        var now = 50L
        val lines = mutableListOf<String>()
        var completions = 0
        val initialization = BleInitialization(
            requestNotify = { BleRequestResult.Accepted },
            requestArm = { BleRequestResult.Accepted },
            complete = { completions++ },
            nowMs = { now },
            journal = lines::add,
        )
        fun timeout(stage: String) {
            now += 10
            initialization.timedOut()
            assertEquals("ble: initialization stage=$stage elapsedMs=${now - 50} timeout", lines.last())
            assertEquals(0, completions, "The existing BleLink timeout still owns cleanup")
        }
        timeout("connection")
        initialization.connected()
        timeout("discovery")
        initialization.discoveryStatus(0)
        initialization.servicesDiscovered()
        timeout("fff4_notify")
        initialization.notificationWritten(fff4, 0)
        timeout("fff5_notify")
        initialization.notificationWritten(fff5, 3)
        timeout("pairing_arm")
        assertTrue(lines.any { it.endsWith("descriptor_callback status=3") })
        initialization.close()
        val closedLines = lines.size
        initialization.timedOut()
        assertEquals(closedLines, lines.size)
    }

    @Test fun nativeBooleanAndNumericRejectionsAreJournaledWithoutExceptionText() {
        for (rejection in rejections()) {
            val lines = mutableListOf<String>()
            var failure: Throwable? = null
            val initialization = BleInitialization(
                requestNotify = { BleRequestResult.MissingDescriptor },
                requestArm = { rejection },
                complete = { failure = it },
                nowMs = { 0L },
                journal = lines::add,
            )
            initialization.servicesDiscovered()
            assertEquals("pairing arm failed", assertNotNull(failure).message)
            assertTrue(lines.last().contains("stage=pairing_arm elapsedMs=0 admitted=0 reason=rejected"))
            if ((rejection as BleRequestResult.Rejected).status != null) {
                assertTrue(lines.last().endsWith("status=201"))
            }
        }
    }

    private fun rejections() = listOf(
        BleRequestResult.fromBoolean(false),
        BleRequestResult.fromStatus(201),
    )

    private class Fixture(
        notifyResult: (BleInitialization.Channel) -> BleRequestResult = { BleRequestResult.Accepted },
        armResult: BleRequestResult = BleRequestResult.Accepted,
    ) {
        val notifications = mutableListOf<BleInitialization.Channel>()
        val journal = mutableListOf<String>()
        var arms = 0
        var completed = false
        var completions = 0
        var failure: Throwable? = null
        val initialization = BleInitialization(
            requestNotify = { notifications += it; notifyResult(it) },
            requestArm = { arms++; armResult },
            complete = { completed = true; completions++; failure = it },
            journal = journal::add,
        )
    }
}
