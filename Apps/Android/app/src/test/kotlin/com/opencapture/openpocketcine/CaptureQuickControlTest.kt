package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CaptureQuickControlTest {
    @Test fun everyHeldPanelMountHasZeroGetsSetsAndPreferenceWrites() = runBlocking {
        val effects = CapturePanelEffects(preview = true)
        val traffic = mutableListOf<String>()
        val status = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL,
            focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = -1)
        repeat(3) { // Repeated open/close and tool changes must not become camera demand.
            for (sheet in LiveSheet.entries) {
                effects.mount(sheet, status, true,
                    { traffic += "audio GET" }, { traffic += "focus GET" }, { traffic += "ISO GET" },
                    { traffic += "seed/pref write" }, { traffic += "reseat/pref write" })
                effects.run { traffic += "shutter angle preference" }
            }
        }
        assertTrue(traffic.isEmpty())
    }

    @Test fun tappedPanelStillUsesTheExistingRefreshOrder() = runBlocking {
        val effects = CapturePanelEffects(preview = false)
        val status = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, focusTrack = -1)
        for ((sheet, expected) in listOf(
            LiveSheet.AUDIO to listOf("audio", "seed"),
            LiveSheet.FOCUS to listOf("focus", "seed"),
            LiveSheet.ISO to listOf("seed", "iso", "reseat"),
        )) {
            val calls = mutableListOf<String>()
            effects.mount(sheet, status, true, { calls += "audio" }, { calls += "focus" },
                { calls += "iso" }, { calls += "seed" }, { calls += "reseat" })
            assertEquals(expected, calls)
        }
    }

    @Test fun liveShutterReseatingCanPersistButPreviewReseatingCannot() {
        val status = CameraStatus(fps = 24, shutterDenom = 100, availableShutterDenoms = listOf(25, 50, 100))
        val seat = CaptureLists.reseatShutterAngle(status, 180.0)
        assertTrue(seat.persistAngle)
        var writes = 0
        CapturePanelEffects(preview = true).run { if (seat.persistAngle) writes++ }
        assertEquals(0, writes)
        CapturePanelEffects(preview = false).run { if (seat.persistAngle) writes++ }
        assertEquals(1, writes)
    }

    @Test fun focusTapAndHoldOfferFiveNativeChoicesWithUnknownUnselected() {
        assertEquals(listOf("AF-S", "AF-C", "Showcase", "Lock", "Priority"), CaptureFocusChoices.labels)
        val statuses = listOf(CameraStatus(focusMode = CameraCommands.FOCUS_SINGLE)) +
            (0..3).map { CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = it) }
        for ((index, status) in statuses.withIndex()) {
            assertEquals(CaptureFocusChoices.labels, captureQuickFocusControl(status).options)
            assertEquals(CaptureFocusChoices.labels[index], CaptureFocusChoices.selection(status))
            assertEquals(CaptureFocusChoices.selection(status), captureQuickFocusControl(status).selection)
        }
        for (status in listOf(CameraStatus(),
            CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = -1),
            CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = 99))) {
            assertEquals("", CaptureFocusChoices.selection(status))
            assertEquals("", captureQuickFocusControl(status).selection)
        }
    }

    @Test fun releaseDispatchPreservesExistingFocusMappingAndItsNativeSequence() {
        val single = CameraStatus(focusMode = CameraCommands.FOCUS_SINGLE, focusTrack = 0)
        val calls = mutableListOf<String>()
        fun apply(label: String, status: CameraStatus) = applyCaptureFocusChoice(label, status,
            { calls += "mode:$it" }, { calls += "track:$it" })
        apply("Lock", single)
        assertEquals(listOf("mode:true", "track:2"), calls)
        calls.clear()
        apply("Showcase", single.copy(focusMode = CameraCommands.FOCUS_CONTINUOUS))
        assertEquals(listOf("track:1"), calls)
        calls.clear()
        apply("AF-S", single.copy(focusMode = CameraCommands.FOCUS_CONTINUOUS))
        assertEquals(listOf("mode:false"), calls)
        calls.clear()
        apply("AF-S", single)
        apply("Invented mode", single)
        assertTrue(calls.isEmpty())
        apply("AF-C", single.copy(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = -1))
        assertEquals(listOf("track:0"), calls, "Unknown track must not masquerade as an already selected AF-C choice")
    }

    @Test fun releaseRejectsStaleSourceOptionsStatusDisabledAndUnchangedValues() {
        val source = MonitorQuickControl(listOf("AF-S", "AF-C", "Showcase", "Lock", "Priority"),
            "AF-S", context = "1:0", identity = "camera-a")
        var sends = 0
        for (current in listOf(source.copy(identity = "camera-b"), source.copy(context = "2:0"),
            source.copy(options = listOf("AF-S", "AF-C")), source.copy(selection = "AF-C"),
            source.copy(enabled = false), null)) {
            commitCaptureQuickControl(source, current, "Lock", enabled = true) { sends++ }
        }
        commitCaptureQuickControl(source, source, "Lock", enabled = false) { sends++ }
        commitCaptureQuickControl(source, source, "AF-S", enabled = true) { sends++ }
        commitCaptureQuickControl(source, source, "Invented mode", enabled = true) { sends++ }
        assertEquals(0, sends)
        commitCaptureQuickControl(source, source, "Lock", enabled = true) { sends++ }
        assertEquals(1, sends)
    }

    @Test fun pauseResumeAndSourceTransitionsInvalidateEvenIfAccessReturnsBeforeRelease() {
        val lifetime = CaptureQuickLifetime()
        lifetime.update(true)
        val source = MonitorQuickControl(listOf("100", "200"), "100", identity = lifetime.epoch)
        lifetime.update(false)
        assertFalse(lifetime.active)
        lifetime.update(true)
        assertTrue(lifetime.active)
        var sends = 0
        commitCaptureQuickControl(source, source.copy(identity = lifetime.epoch), "200", lifetime.active) { sends++ }
        assertEquals(0, sends)
        val resumed = source.copy(identity = lifetime.epoch)
        lifetime.invalidate() // Connection phase changes while the monitor remains mounted.
        commitCaptureQuickControl(resumed, source.copy(identity = lifetime.epoch), "200", lifetime.active) { sends++ }
        assertEquals(0, sends)
    }
}
