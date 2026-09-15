package com.opencapture.openpocketcine

import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Source-contract checks supplement policy tests; these do not claim rendered Compose coverage. */
class CapturePreviewWiringTest {
    private val repository: File get() = generateSequence(File(".").absoluteFile) { it.parentFile }
        .first { File(it, "Apps/Android/app/src/main").isDirectory }
    private fun app(name: String) = File(repository,
        "Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/$name").readText()

    @Test fun heldReadoutUsesTheCompactDialVariantOfTheTappedHost() {
        val caller = app("LivePortraitChrome.kt").substringAfter("quickPreview =")
            .substringBefore("onQuickActiveChange =")
        assertTrue(caller.contains("LiveControlSheet("))
        assertTrue(caller.contains("preview = preview"))
        val body = app("LiveControlSheets.kt")
        val host = body.substringAfter("fun LivePickerHost(").substringBefore("private fun viewportIsPortrait")
        assertTrue(host.contains("LiveControlSheet("))
        assertTrue(host.contains("topCapturePanel"))
        assertTrue(host.contains("fromTop = fromTop"))
        assertTrue(body.contains("CompositionLocalProvider(LocalCapturePreview provides preview, LocalViewportPortrait provides isPortrait)"))
        val content = body.substringAfter("private fun LiveControlSheetContent(").substringBefore("fun LivePickerHost(")
        assertTrue(content.contains("val compact = preview != null"))
        assertTrue(content.contains("\"drag to set\""))
        assertTrue(content.contains("showsClose = !compact"))
        assertTrue(content.contains("if (!compact)"))
        assertTrue(content.contains("compactCaptureBottomPadding"))
        assertTrue(content.contains("showsRecordingCategoryTabs(portrait, compact)"))
        assertTrue(body.contains("sheet.isRecordingSetup && isPortrait"))
        assertTrue(body.contains("capturePanelBottomCorner"))
        for (required in listOf("SheetHeader(", "CaptureLists.NATIVE_ISO_HOP_HELP", "CaptureLists.FACE_PRIORITY_HELP",
            "FocusBody(", "AudioBody(status, enabled, selectedMode, model)", "ModeBar(", "MonitorPanelGrabber()")) {
            assertTrue(content.contains(required), "Tap still keeps the full details drawer: $required")
        }
        val shared = File(repository,
            "Apps/Android/monitor-ui/src/main/kotlin/com/opencapture/monitorui/MonitorQuickControl.kt").readText()
        assertTrue(shared.contains("previewContent(heldPreview, layout.maxHeight)"))
        assertFalse(shared.contains("MonitorValueDrum("), "A reduced second drum must not replace the injected compact body")
        assertFalse(shared.contains("LiveSheet"), "The shared gesture must not own camera taxonomy")
    }

    @Test fun previewInputReachesTheProductionDrumAndCannotEnableChildActions() {
        val body = app("LiveControlSheets.kt")
        val drum = body.substringAfter("private fun CaptureDrumWheel(").substringBefore("private fun initialSelectedMode(")
        assertTrue(drum.contains("val preview = LocalCapturePreview.current"))
        assertTrue(drum.contains("preview?.control?.options ?: options"))
        assertTrue(drum.contains("displayPosition = preview?.position"))
        assertTrue(drum.contains("interactive = interactive && preview == null"))
        assertTrue(drum.contains("if (interactive && preview == null)"))
        assertTrue(body.contains("val enabled = !locked && preview == null"))
        assertTrue(body.contains("if (preview == null) {\n        LaunchedEffect(sheet)"))
        assertTrue(body.contains("effects.mount(sheet, status"))
        assertTrue(body.contains("if (seat.persistAngle) OperatorPrefs.setShutterAngleDegrees"))
        assertTrue(body.contains("CaptureFocusChoices.selection(status)"))
    }
}
