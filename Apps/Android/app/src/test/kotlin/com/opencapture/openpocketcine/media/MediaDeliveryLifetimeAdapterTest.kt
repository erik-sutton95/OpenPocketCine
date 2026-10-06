package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.MonitorDeliveryCompletion
import com.opencapture.opencine.appkit.MonitorDeliveryModel
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import com.opencapture.opencine.cameracontrols.admittedDeliveryToast
import com.opencapture.opencine.cameracontrols.MediaDeliveryResult
import com.opencapture.opencine.cameracontrols.MediaDeliveryOverlayState

/** SIMULATED completion facts cross the actual admitted share/copy adapter. */
class MediaDeliveryLifetimeAdapterTest {
    private class Gate {
        val result = CompletableDeferred<MediaDeliveryResult>()
        suspend fun wait(): MediaDeliveryResult = withContext(NonCancellable) { result.await() }
    }

    @Test fun cancelledOldShareResultNeverLaunchesIntent() = runTest {
        val old = Gate()
        val presented = mutableListOf<List<File>>()
        val delivery = MonitorDeliveryModel<MediaDeliveryOverlayState, MediaDeliveryResult, Unit>(backgroundScope)
        val admitted: (MediaDeliveryResult) -> String? = { outcome ->
            admittedDeliveryToast(outcome) { files -> presented.add(files); true }
        }
        delivery.begin(onComplete = admitted) { MonitorDeliveryCompletion(old.wait()) }
        runCurrent()
        delivery.begin(onComplete = admitted) {
            MonitorDeliveryCompletion(MediaDeliveryResult.Message("Saved 1 clip to Photos"))
        }
        runCurrent()
        old.result.complete(MediaDeliveryResult.ShareReady(listOf(File("SIMULATED-old.mp4"))))
        runCurrent()
        assertTrue(presented.isEmpty())
        assertEquals("Saved 1 clip to Photos", delivery.state.value.toast)
        delivery.close()
    }

    @Test fun admittedIntentResultPreservesSingleAndBatchCopy() = runTest {
        val delivery = MonitorDeliveryModel<MediaDeliveryOverlayState, MediaDeliveryResult, Unit>(backgroundScope)
        delivery.begin(onComplete = { outcome -> admittedDeliveryToast(outcome) { false } }) {
            MonitorDeliveryCompletion(MediaDeliveryResult.ShareReady(listOf(File("SIMULATED-one.mp4"))))
        }
        runCurrent()
        assertEquals("Couldn't share this clip.", delivery.state.value.toast)
        val files = listOf(File("SIMULATED-one.mp4"), File("SIMULATED-two.mp4"))
        delivery.begin(onComplete = { outcome -> admittedDeliveryToast(outcome) { false } }) {
            MonitorDeliveryCompletion(MediaDeliveryResult.ShareReady(files))
        }
        runCurrent()
        assertEquals("Couldn't share these clips.", delivery.state.value.toast)
        delivery.begin(onComplete = { outcome ->
            admittedDeliveryToast(outcome) { actual -> assertEquals(files, actual); true }
        }) { MonitorDeliveryCompletion(MediaDeliveryResult.ShareReady(files)) }
        runCurrent()
        assertEquals("Ready to share 2 clips", delivery.state.value.toast)
        delivery.close()
    }

    @Test fun explicitCloseBeforeScopeCancellationRejectsLateIntent() = runTest {
        val caller = CoroutineScope(backgroundScope.coroutineContext +
            SupervisorJob(backgroundScope.coroutineContext[kotlinx.coroutines.Job]))
        val delivery = MonitorDeliveryModel<MediaDeliveryOverlayState, MediaDeliveryResult, Unit>(caller)
        val late = Gate()
        var presentations = 0
        delivery.begin(onComplete = { outcome ->
            admittedDeliveryToast(outcome) { presentations++; true }
        }) { MonitorDeliveryCompletion(late.wait()) }
        runCurrent()
        delivery.close()
        caller.cancel()
        late.result.complete(MediaDeliveryResult.ShareReady(listOf(File("SIMULATED-late.mp4"))))
        runCurrent()
        assertEquals(0, presentations)
        assertFalse(delivery.state.value.running)
        assertNull(delivery.state.value.toast)
    }
}
