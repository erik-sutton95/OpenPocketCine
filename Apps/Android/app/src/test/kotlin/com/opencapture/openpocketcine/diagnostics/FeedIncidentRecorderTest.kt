package com.opencapture.openpocketcine.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FeedIncidentRecorderTest {
    @Test
    fun freshInputStaleOutputStartsAnOpenIncidentAndPersistsAJob() {
        val recorder = FeedIncidentRecorder { "inc-fresh" }
        recorder.beginSession(session())
        repeat(3) { index ->
            recorder.recordSnapshot(healthy(monotonic = index.toDouble()))
        }
        val job = recorder.recordSnapshot(staleOutput(monotonic = 3.0))
        assertNotNull(job)
        assertEquals(FeedIncidentPersistenceJob.Reason.STARTED, job.reason)
        assertEquals(FeedIncidentKind.FRESH_INPUT_STALE_OUTPUT, job.bundle.header.kind)
        assertEquals(FeedIncidentOutcome.OPEN, job.bundle.header.outcome)
        assertEquals("inc-fresh", job.bundle.header.incidentId)
        assertTrue(job.bundle.prelude.isNotEmpty())
        assertTrue(job.bundle.header.sourceRevision.contains("abc"))
    }

    @Test
    fun recoveredOutputCollectsAftermathThenCloses() {
        val recorder = FeedIncidentRecorder { "inc-rec" }
        recorder.beginSession(session())
        recorder.recordSnapshot(healthy(0.0))
        recorder.recordSnapshot(staleOutput(3.0))
        val recovered = recorder.recordSnapshot(healthy(4.0))
        assertEquals(FeedIncidentOutcome.RECOVERED, recovered?.bundle?.header?.outcome)
        assertTrue(recorder.isCollectingAftermath)
        val closed = recorder.recordSnapshot(healthy(4.0 + FeedIncidentBounds.AFTERMATH_SECONDS))
        assertNotNull(closed)
        assertNull(recorder.openHeader)
        assertTrue(closed.bundle.aftermath.isNotEmpty())
    }

    @Test
    fun repairRecordsUseFixedTokens() {
        val recorder = FeedIncidentRecorder { "inc-rep" }
        recorder.beginSession(session())
        recorder.recordSnapshot(staleOutput(3.0))
        val job =
            recorder.recordRepair(
                FeedRepairRecord(3.1, "decoder", FeedRepairPhase.REQUESTED, "outputSilence"),
            )
        assertNotNull(job)
        val repair = job.bundle.repairs.single()
        assertEquals("decoder", repair.action)
        assertEquals(FeedRepairPhase.REQUESTED, repair.phase)
        assertEquals("outputSilence", repair.reason)
    }

    @Test
    fun missingAssistAgeIsNotAnAssistStall() {
        val snapshot =
            healthy(3.0).copy(
                rates = FeedIncidentRates(packetHz = 25.0, decodedOutputHz = 25.0, assistOutputHz = 0.0, presentHz = 25.0),
                ages =
                    FeedIncidentAges(
                        packetAge = 0.04,
                        decodedOutputAge = 0.04,
                        assistOutputAge = null,
                        presentAge = 0.04,
                    ),
            )
        val verdict = FeedIncidentClassifier.classify(snapshot)
        assertTrue(verdict.kind != FeedIncidentKind.ASSIST_STALLED)
        assertTrue(snapshot.rates.assistOutputHz == 0.0)
        assertTrue(snapshot.ages.assistOutputAge == null)
    }

    @Test
    fun neitherObservableStageIsNotHealthyExposure() {
        val snapshot =
            healthy(2.0).copy(
                lifecycle =
                    FeedIncidentLifecycle(
                        connected = true,
                        liveEstablished = true,
                        outputObservable = false,
                        presentationExpected = false,
                    ),
            )
        assertTrue(!FeedIncidentClassifier.isRecovered(snapshot))
        val recorder = FeedIncidentRecorder { "inc-exp" }
        recorder.beginSession(session())
        recorder.recordSnapshot(healthy(0.0))
        recorder.recordSnapshot(snapshot)
        assertEquals(0.0, recorder.healthyExposure, 0.001)
    }

    @Test
    fun sessionOriginIsCopiedAndDoesNotDowngrade() {
        val recorder = FeedIncidentRecorder { "inc-origin" }
        recorder.beginSession(
            session().copy(
                testSource = FeedIncidentTestSource.AUTOMATION,
                buildIdentity = "android-0123456789abcdef0123456789ab",
            ),
        )
        val job = recorder.recordSnapshot(staleOutput(monotonic = 3.0))
        assertEquals(FeedIncidentTestSource.AUTOMATION, job?.bundle?.header?.testSource)
        assertEquals("android-0123456789abcdef0123456789ab", job?.bundle?.header?.buildIdentity)
        recorder.noteTestSource(FeedIncidentTestSource.MANUAL)
        assertEquals(FeedIncidentTestSource.AUTOMATION, recorder.openHeader?.testSource)
        recorder.noteTestSource(FeedIncidentTestSource.FAULT_INJECTION)
        assertEquals(FeedIncidentTestSource.AUTOMATION, recorder.openHeader?.testSource)
    }

    @Test
    fun playbackSuppressesRecording() {
        val recorder = FeedIncidentRecorder { "inc-none" }
        recorder.beginSession(session())
        val job =
            recorder.recordSnapshot(
                staleOutput(3.0).copy(lifecycle = staleOutput(3.0).lifecycle.copy(playbackActive = true)),
            )
        assertNull(job)
        assertNull(recorder.openHeader)
    }

    private fun session() =
        FeedIncidentSessionContext(
            sessionId = "session-1",
            appVersion = "0.1.0",
            appBuild = "2",
            sourceRevision = "abc1234+",
            osName = "Android",
            osVersion = "16",
            hardwareClass = "Pixel",
            cameraFamily = "pocket",
        )

    private fun healthy(monotonic: Double) =
        FeedIncidentSnapshot(
            monotonicNow = monotonic,
            wallClockMs = 1_000L + (monotonic * 1000).toLong(),
            rates = FeedIncidentRates(packetHz = 25.0, accessUnitHz = 25.0, decodedOutputHz = 25.0, presentHz = 25.0),
            ages = FeedIncidentAges(packetAge = 0.04, accessUnitAge = 0.04, decodedOutputAge = 0.04, presentAge = 0.04),
            lifecycle = FeedIncidentLifecycle(connected = true, liveEstablished = true),
        )

    private fun staleOutput(monotonic: Double) =
        healthy(monotonic).copy(
            rates = FeedIncidentRates(packetHz = 25.0, accessUnitHz = 25.0, decodeSubmitHz = 25.0, decodedOutputHz = 0.0),
            ages = FeedIncidentAges(packetAge = 0.04, accessUnitAge = 0.04, decodedOutputAge = 5.0, presentAge = 5.0),
        )
}
