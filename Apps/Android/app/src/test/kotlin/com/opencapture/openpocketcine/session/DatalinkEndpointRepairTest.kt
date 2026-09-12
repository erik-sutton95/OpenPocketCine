package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield

class DatalinkEndpointRepairTest {
    @Test fun newAudioRequestsAreRejectedBeforeNegotiationReachesIo() = runBlocking {
        val admission = EndpointCommandAdmission()
        var epoch = 0L
        var requests = 0
        var enteredIo = false
        repairDatalinkEndpoint(Any(), { true }, { enteredIo = true },
            commandAdmission = admission,
            prepare = {
                epoch += 1 // retire the preceding Audio chain
                assertFalse(enteredIo)
                // A newly opened Audio sheet owns the new epoch, so epoch
                // retirement alone cannot block its GET during negotiation.
                if (admission.allows(isClosed = false, isRebuilding = false)) requests += 1
            },
            waitForPicture = {
                assertTrue(admission.allows(isClosed = false, isRebuilding = false),
                    "first-picture requests must remain admitted after negotiation")
            }, enable = {
                assertTrue(enteredIo)
                assertTrue(admission.allows(isClosed = false, isRebuilding = false))
            })
        assertEquals(1L, epoch)
        assertEquals(0, requests, "fresh work must not enter before the IO worker sets rebuilding")
    }

    @Test fun oldNegotiationCompletionCannotAdmitCommandsDuringReplacement() {
        val admission = EndpointCommandAdmission()
        val old = admission.begin()
        val replacement = admission.begin()
        admission.finish(old)
        assertFalse(admission.allows(isClosed = false, isRebuilding = false))
        admission.finish(replacement)
        assertTrue(admission.allows(isClosed = false, isRebuilding = false))
        assertFalse(admission.allows(isClosed = false, isRebuilding = true))
        assertFalse(admission.allows(isClosed = true, isRebuilding = false))
    }

    @Test fun successfulNegotiationEnablesTheOwningLinkOnce() = runBlocking {
        val link = Any()
        var negotiated = false
        var enables = 0
        repairDatalinkEndpoint(link, { it === link }, {
            negotiated = true
        }, enable = {
            assertTrue(negotiated, "enable must follow completed endpoint negotiation")
            enables += 1
        })
        assertEquals(1, enables)
    }

    @Test fun failedNegotiationHandsOffToSessionRecoveryWithoutEnable() = runBlocking {
        var enables = 0
        var handoffs = 0
        repairDatalinkEndpoint(Any(), { true }, {
            throw DatalinkDriver.DatalinkError.NoHandshake()
        }, recoverSession = { handoffs += 1 }, enable = { enables += 1 })
        assertEquals(0, enables)
        assertEquals(1, handoffs, "a failed endpoint cannot release the only recovery owner")
    }

    @Test fun handshakeWithoutNewPictureTransfersToSessionRecoveryAtDeadline() = runBlocking {
        var enables = 0
        var handoffs = 0
        var pictureWaited = false
        repairDatalinkEndpoint(Any(), { true }, {}, pictureTimeoutMs = 20,
            waitForPicture = { pictureWaited = true; awaitCancellation() },
            recoverSession = { handoffs += 1 }, enable = { enables += 1 })
        assertTrue(pictureWaited, "handshake must not itself complete recovery")
        assertEquals(1, enables)
        assertEquals(1, handoffs)
    }

    @Test fun newSourcePictureCompletesWithoutSessionHandoff() = runBlocking {
        var handoffs = 0
        var enables = 0
        var sawFreshPicture = false
        repairDatalinkEndpoint(Any(), { true }, {},
            waitForPicture = {
                assertEquals(1, enables)
                sawFreshPicture = true
            }, recoverSession = { handoffs += 1 }, enable = { enables += 1 })
        assertTrue(sawFreshPicture)
        assertEquals(0, handoffs)
    }

    @Test fun cancelledPictureWaitCannotHandoffOrEnableAgain() = runBlocking {
        val waiting = kotlinx.coroutines.CompletableDeferred<Unit>()
        var enables = 0
        var handoffs = 0
        val job = launch {
            repairDatalinkEndpoint(Any(), { true }, {},
                waitForPicture = { waiting.complete(Unit); awaitCancellation() },
                recoverSession = { handoffs += 1 }, enable = { enables += 1 })
        }
        waiting.await()
        job.cancelAndJoin()
        assertEquals(1, enables)
        assertEquals(0, handoffs)
    }

    @Test fun activeAudioPredecessorCannotUseReplacementEndpointAfterCaughtFailure() = runBlocking {
        var epoch = 0L
        var requests = 0
        val firstRequest = kotlinx.coroutines.CompletableDeferred<Unit>()
        val resume = kotlinx.coroutines.CompletableDeferred<Unit>()
        val active = launch(EndpointCommandEpoch(epoch)) {
            ensureEndpointCommandCurrent(epoch)
            requests += 1
            firstRequest.complete(Unit)
            // Mirrors a refresh chain whose first GET absorbs a failed wait.
            runCatching { resume.await(); throw IllegalStateException("retired GET") }
            ensureEndpointCommandCurrent(epoch)
            requests += 1
        }
        firstRequest.await()
        epoch += 1
        resume.complete(Unit)
        active.join()
        assertEquals(1, requests, "a running predecessor must retain its original request epoch")
    }

    @Test fun receivedVideoRemainsStaleWhenReplacementEndpointHasNoPackets() {
        val history = LiveSessionVideoHistory()
        history.noteVideoPacket()
        // open() clears endpoint packet count and both receive timestamps.
        val hadVideo = history.hadVideo(endpointPackets = 0, endpointVideoAgeMs = null)
        assertTrue(hadVideo, "warm negotiation cannot erase the held session's video history")
        assertTrue(LiveViewEnablePolicy.shouldTreatLiveVideoAsStale(null, hadVideo, false),
            "finishing a socket operation does not make a held picture live")
        history.reset()
        assertFalse(history.hadVideo(0, null), "explicit disconnect starts a new session history")
    }

    @Test fun gimbalConfigurationRequiresActiveFreshLiveSession() {
        fun admitted(hasGimbal: Boolean = true, live: Boolean = true, active: Boolean = true,
            warming: Boolean = false, recovering: Boolean = false,
            stale: Boolean = false, hasLink: Boolean = true) =
            acceptsGimbalConfiguration(hasGimbal, live, active, warming, recovering, stale, hasLink)
        assertTrue(admitted())
        assertFalse(admitted(hasGimbal = false))
        assertFalse(admitted(live = false))
        assertFalse(admitted(active = false))
        assertFalse(admitted(warming = true))
        assertFalse(admitted(recovering = true))
        assertFalse(admitted(stale = true))
        assertFalse(admitted(hasLink = false))
    }

    @Test fun replacementWhileNegotiatingCannotEnableAnotherLink() = runBlocking {
        val old = Any()
        var current = old
        var enables = 0
        repairDatalinkEndpoint(old, { it === current }, {
            current = Any()
        }, enable = { enables += 1 })
        assertEquals(0, enables)
    }

    @Test fun cancellationInterruptsNegotiationAndNeverEnables() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        var enables = 0
        val job = launch {
            repairDatalinkEndpoint(Any(), { true }, {
                entered.countDown()
                try { release.await() } finally { finished.countDown() }
            }, enable = { enables += 1 })
        }
        yield()
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        job.cancel()
        val interrupted = finished.await(250, TimeUnit.MILLISECONDS)
        release.countDown()
        job.cancelAndJoin()
        assertTrue(interrupted, "cancelled repair must interrupt its blocking handshake")
        assertEquals(0, enables)
    }
}
