package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.VideoFormat
import com.opencapture.openpocketcine.session.VideoFrameRate
import com.opencapture.openpocketcine.session.VideoResolution
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CaptureQuickControlTest {
    @Test fun shootingModeRejectsRecordingAtAdmissionAndAtTheSetterBoundary() {
        val stopped = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO)
        val recording = stopped.copy(isRecording = true)
        val admitted = requireNotNull(recordingCategoryQuickControl(LiveSheet.MODE, stopped))
        val changed = admitted.options.first { it != admitted.selection }
        val blocked = requireNotNull(recordingCategoryQuickControl(LiveSheet.MODE, recording))
        assertTrue(admitted.enabled)
        assertFalse(blocked.enabled)
        val sent = mutableListOf<Int>()
        commitCaptureQuickControl(admitted, blocked, changed, true) { sent += -1 }
        assertTrue(sent.isEmpty(), "Recording starting after down invalidates the source")
        applyCaptureShootingMode(changed, recording, null) { sent += it }
        assertTrue(sent.isEmpty(), "Full picker and release cannot bypass recording policy")
        commitCaptureQuickControl(admitted, admitted, changed, true) {
            applyCaptureShootingMode(changed, stopped, null) { sent += it }
        }
        assertEquals(listOf(CaptureLists.shootingModeRaw(changed, null)), sent)
    }

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

    @Test fun recordingCategoryHoldUsesFullPickerPrimaryChoicesAndRejectsStaleLists() {
        val fourK24 = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS24)
        val fourK30 = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS30)
        val status = CameraStatus(
            shootingMode = CameraCommands.SHOOT_VIDEO,
            resolutionCode = VideoResolution.P4K.rawValue,
            fpsIndex = VideoFrameRate.FPS24.rawValue,
            fps = 24,
            availableVideoFormats = listOf(fourK24, fourK30),
            colorMode = CameraCommands.COLOR_NORMAL,
            availableColorModes = listOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_HDR),
        )
        val format = requireNotNull(recordingCategoryQuickControl(LiveSheet.FORMAT, status))
        assertEquals(listOf("24p", "30p"), format.options)
        assertEquals("24p", format.selection)
        val narrowed = requireNotNull(
            recordingCategoryQuickControl(LiveSheet.FORMAT, status.copy(availableVideoFormats = listOf(fourK24))),
        )
        var sends = 0
        commitCaptureQuickControl(format, narrowed, "30p", enabled = true) { sends++ }
        commitCaptureQuickControl(format, format, "24p", enabled = true) { sends++ }
        assertEquals(0, sends)
        commitCaptureQuickControl(format, format, "30p", enabled = true) { sends++ }
        assertEquals(1, sends)

        val color = requireNotNull(recordingCategoryQuickControl(LiveSheet.COLOR, status, family = "pocket"))
        assertEquals(CaptureLists.colorWheelLabels(status, "pocket"), color.options)
        assertTrue(color.options.contains("Normal"))
        assertEquals("Normal", color.selection)

        val mode = requireNotNull(recordingCategoryQuickControl(LiveSheet.MODE, status))
        assertEquals(CaptureLists.shootingModeLabels(null), mode.options)
        assertEquals("Video", mode.selection)
        assertTrue("Photo" in mode.options)
        val photo = requireNotNull(
            recordingCategoryQuickControl(
                LiveSheet.MODE, status.copy(shootingMode = CameraCommands.SHOOT_PHOTO_POCKET4)),
        )
        commitCaptureQuickControl(mode, photo, "Photo", enabled = true) { sends++ }
        assertEquals(1, sends, "A changed shooting-mode source cannot commit")
        assertTrue(LiveSheet.MODE.isTopAnchored)
        assertTrue(!LiveSheet.EXPO.isTopAnchored)
        assertTrue(LiveSheet.FORMAT.isRecordingSetup)
        assertTrue(!LiveSheet.MODE.isRecordingSetup)
    }

    @Test fun shutterReadoutUsesLiveDenomWhenPreferredAngleDoesNotMap() {
        val status = CameraStatus(
            expoMode = CameraCommands.EXPO_MANUAL,
            fps = 24,
            shutterDenom = 48,
            availableShutterDenoms = listOf(24, 48, 50, 60, 120),
            shootingMode = CameraCommands.SHOOT_VIDEO,
        )
        assertEquals("180°", captureShutterReadout(status, true, 180.0))
        assertEquals(
            "72°",
            captureShutterReadout(status.copy(shutterDenom = 120), true, 180.0),
        )
        val synced = GamepadShutterSync.preferredAngle(50, 24)
        assertEquals(172.0, synced)
        assertEquals("172°", captureShutterReadout(status.copy(shutterDenom = 50), true, synced))
        assertEquals(
            "1/50",
            captureShutterReadout(
                status.copy(shutterDenom = 50, shootingMode = CameraCommands.SHOOT_PHOTO),
                true,
                180.0,
            ),
        )
        assertEquals(
            "0.0",
            captureShutterReadout(
                status.copy(expoMode = CameraCommands.EXPO_AUTO, evComp = EvComp.ZERO.rawValue),
                true,
                180.0,
            ),
        )
    }
}
