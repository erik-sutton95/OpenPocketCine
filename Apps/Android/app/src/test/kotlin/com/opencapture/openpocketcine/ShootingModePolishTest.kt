package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.VideoFormat
import com.opencapture.openpocketcine.session.VideoFrameRate
import com.opencapture.openpocketcine.session.VideoResolution
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ShootingModePolishTest {
    private val pocket3 = CameraModel(name = "Osmo Pocket 3")
    private val leftoverVideo = listOf(
        VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS24),
        VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60),
    )

    @Test
    fun superNightIsVideoAndPocket3ReadsLowLight() {
        assertFalse(CameraCommands.isPhotoMode(CameraCommands.SHOOT_SUPER_NIGHT))
        assertTrue(CameraCommands.isPhotoMode(CameraCommands.SHOOT_PHOTO))
        assertTrue(CameraCommands.isPhotoMode(CameraCommands.SHOOT_PHOTO_POCKET4))
        assertEquals("SuperNight", CameraCommands.shootingModeLabel(CameraCommands.SHOOT_SUPER_NIGHT))
        assertEquals(
            "Low-Light",
            CameraCommands.shootingModeLabel(CameraCommands.SHOOT_SUPER_NIGHT, "Osmo Pocket 3"),
        )
        assertEquals(
            "SuperNight",
            CameraCommands.shootingModeLabel(CameraCommands.SHOOT_SUPER_NIGHT, "Osmo Pocket 4 Pro"),
        )
        assertEquals(
            CameraCommands.SHOOT_SUPER_NIGHT,
            CaptureLists.shootingModeRaw("Low-Light", "Osmo Pocket 3"),
        )
        assertNull(CaptureLists.shootingModeRaw("SuperNight", "Osmo Pocket 3"))
        assertTrue("Low-Light" in CaptureLists.shootingModeLabels("Osmo Pocket 3"))
        assertTrue("SuperNight" !in CaptureLists.shootingModeLabels("Osmo Pocket 3"))
        assertTrue("SuperNight" in CaptureLists.shootingModeLabels("Osmo Pocket 4"))
    }

    @Test
    fun photoSkipsRecordConfirmationAndSuperNightDoesNot() {
        assertFalse(
            CaptureShutterPolicy.requiresRecordConfirmation(true, CameraCommands.SHOOT_PHOTO),
        )
        assertFalse(
            CaptureShutterPolicy.requiresRecordConfirmation(true, CameraCommands.SHOOT_PHOTO_POCKET4),
        )
        assertTrue(
            CaptureShutterPolicy.requiresRecordConfirmation(true, CameraCommands.SHOOT_SUPER_NIGHT),
        )
        assertTrue(
            CaptureShutterPolicy.requiresRecordConfirmation(true, CameraCommands.SHOOT_VIDEO),
        )
        assertFalse(
            CaptureShutterPolicy.requiresRecordConfirmation(false, CameraCommands.SHOOT_VIDEO),
        )
        val live = CaptureShutterPolicy.request(
            CameraCommands.SHOOT_VIDEO, recording = false, locked = false, busy = false,
            phase = com.opencapture.openpocketcine.core.ConnectionPhase.LIVE,
        )
        val slowMo = live.copy(shootingMode = CameraCommands.SHOOT_SLOWMO)
        val photo = live.copy(shootingMode = CameraCommands.SHOOT_PHOTO)
        val rec = live.copy(recording = true)
        val locked = live.copy(locked = true)
        assertTrue(CaptureShutterPolicy.shouldDismiss(live, slowMo))
        assertTrue(CaptureShutterPolicy.shouldDismiss(live, photo))
        assertTrue(CaptureShutterPolicy.shouldDismiss(live, rec))
        assertFalse(CaptureShutterPolicy.canCommit(live, photo))
        assertFalse(CaptureShutterPolicy.canCommit(live, locked))
        assertTrue(CaptureShutterPolicy.canCommit(live, live))
        assertFalse(photo.canConfirm)
        assertTrue(live.canConfirm)
    }

    @Test
    fun photoFormatIsReadOnlyAndDoesNotKeepVideoFps() {
        val photo = CameraStatus(
            shootingMode = CameraCommands.SHOOT_PHOTO,
            resolutionCode = CameraCommands.RES_4K,
            fpsIndex = 6,
            fps = 60,
            availableVideoFormats = leftoverVideo,
        )
        assertEquals("Photo", CaptureLists.recFormatChipLabel(photo))
        assertFalse(CaptureLists.formatPickerEditable(photo))
        assertEquals(listOf("Photo"), CaptureLists.formatDrumLabels(photo, tab = 0))
        assertEquals(emptyList(), CaptureLists.modeTabs(LiveSheet.FORMAT, photo, offersIsoAuto = false))
        assertNull(CaptureLists.nextVideoFormat(photo, tab = 0, drum = "60p", fromDrum = true))
        assertEquals("FORMAT", CaptureLists.headerTitle(LiveSheet.FORMAT, -1, photo.shootingMode))
        assertEquals("Photo", CaptureLists.headerSubtitle(LiveSheet.FORMAT, -1, 0, false, photo.shootingMode))
        val hold = recordingCategoryQuickControl(LiveSheet.FORMAT, photo, "Osmo Pocket 3")
        assertEquals(listOf("Photo"), hold?.options)
        assertFalse(hold!!.enabled)
    }

    @Test
    fun photoShutterHasNoAngleLadder() {
        assertEquals(emptyList(), CaptureLists.shutterModeTabs(false, CameraCommands.SHOOT_PHOTO))
        assertEquals(listOf("Speed", "Angle"), CaptureLists.shutterModeTabs(false, CameraCommands.SHOOT_VIDEO))
        assertFalse(CaptureLists.isAngleSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 1, CameraCommands.SHOOT_PHOTO))
        assertTrue(CaptureLists.isAngleSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 1, CameraCommands.SHOOT_VIDEO))
        assertEquals(
            0,
            CaptureLists.shutterTabAfterExpoChange(
                CameraCommands.EXPO_MANUAL, shutterUsesAngle = true, CameraCommands.SHOOT_PHOTO,
            ),
        )
        val photo = CameraStatus(
            shootingMode = CameraCommands.SHOOT_PHOTO,
            expoMode = CameraCommands.EXPO_MANUAL,
            shutterDenom = 50,
            fps = 25,
        )
        assertEquals(
            CaptureLists.shutterLabels(photo),
            CaptureLists.shutterWheelOptions(photo, isEvSheet = false, isAngleSheet = false),
        )
    }

    @Test
    fun pocket3SlowMoFallbackIsDocumentedPairsOnly() {
        val formats = VideoFormat.pickerFormats(emptyList(), pocket3, CameraCommands.SHOOT_SLOWMO)
        assertEquals(
            listOf(
                VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS100),
                VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS120),
                VideoFormat(VideoResolution.P2_7K, VideoFrameRate.FPS120),
                VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS120),
                VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS240),
            ),
            formats,
        )
        assertTrue(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS240) !in formats)
        val advertised = listOf(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS240))
        assertEquals(
            advertised,
            VideoFormat.pickerFormats(advertised, pocket3, CameraCommands.SHOOT_SLOWMO),
        )
        assertTrue(
            VideoFormat.pickerFormats(emptyList(), CameraModel("Osmo Pocket 4 Pro"), CameraCommands.SHOOT_SLOWMO)
                .isEmpty(),
        )
    }

    @Test
    fun slowMoPayloadsUseDocumentedTrailers() {
        assertContentEquals(
            byteArrayOf(0x10, 0x0A, 0x00, 0x04, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS100).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x10, 0x07, 0x00, 0x04, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS120).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x2D, 0x07, 0x00, 0x04, 0x00),
            VideoFormat(VideoResolution.P2_7K, VideoFrameRate.FPS120).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x0A, 0x07, 0x00, 0x04, 0x00),
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS120).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x0A, 0x08, 0x00, 0x08, 0x00),
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS240).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x10, 0x08, 0x00, 0x08, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS240).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x10, 0x13, 0x00, 0x04, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS200).payload(CameraCommands.SHOOT_SLOWMO),
        )
        assertContentEquals(
            byteArrayOf(0x10, 0x13, 0x00, 0x00, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS200).setPayload,
        )
        assertContentEquals(
            byteArrayOf(0x10, 0x07, 0x00, 0x00, 0x00),
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS120).setPayload,
        )
        assertEquals(
            "16\u001f10\u001f0",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS100)
                .commandExtra(CameraCommands.SHOOT_SLOWMO, "Osmo Pocket 3"),
        )
        assertEquals(
            "10\u001f8\u001f0",
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS240)
                .commandExtra(CameraCommands.SHOOT_SLOWMO, "Osmo Pocket 4 Pro"),
        )
        assertEquals(
            "16\u001f19\u001f0",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS200)
                .commandExtra(CameraCommands.SHOOT_SLOWMO, "Osmo Pocket 4 Pro"),
        )
        assertEquals(
            "16\u001f19",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS200)
                .commandExtra(CameraCommands.SHOOT_SLOWMO, "Osmo Pocket 4"),
        )
        assertEquals(
            "16\u001f6",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60)
                .commandExtra(CameraCommands.SHOOT_VIDEO, "Osmo Pocket 3"),
        )
        assertEquals(
            "16\u001f3",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS30)
                .commandExtra(CameraCommands.SHOOT_SUPER_NIGHT, "Osmo Pocket 3"),
        )
    }

    @Test
    fun pocket3LowLightFallbackIs1080And4KAt24To30() {
        val formats = VideoFormat.pickerFormats(emptyList(), pocket3, CameraCommands.SHOOT_SUPER_NIGHT)
        val expected = listOf(VideoResolution.P1080, VideoResolution.P4K).flatMap { res ->
            listOf(VideoFrameRate.FPS24, VideoFrameRate.FPS25, VideoFrameRate.FPS30)
                .map { VideoFormat(res, it) }
        }
        assertEquals(expected, formats)
        assertTrue(VideoFormat(VideoResolution.P2_7K, VideoFrameRate.FPS24) !in formats)
        assertTrue(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60) !in formats)
    }

    @Test
    fun timeAndHyperlapseDoNotInventFormatPairs() {
        assertTrue(
            VideoFormat.pickerFormats(emptyList(), pocket3, CameraCommands.SHOOT_TIMELAPSE).isEmpty(),
        )
        assertTrue(
            VideoFormat.pickerFormats(emptyList(), pocket3, CameraCommands.SHOOT_HYPERLAPSE).isEmpty(),
        )
        val advertised = listOf(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS30))
        assertEquals(
            advertised,
            VideoFormat.pickerFormats(advertised, pocket3, CameraCommands.SHOOT_TIMELAPSE),
        )
        val lapse = CameraStatus(
            shootingMode = CameraCommands.SHOOT_TIMELAPSE,
            resolutionCode = CameraCommands.RES_4K,
            fpsIndex = 2,
            fps = 25,
        )
        assertFalse(CaptureLists.formatPickerEditable(lapse))
        assertEquals(listOf("25p"), CaptureLists.fpsDrumLabels(lapse, tab = 0))
        assertEquals(listOf("4K"), CaptureLists.modeTabs(LiveSheet.FORMAT, lapse, offersIsoAuto = false))
        assertNull(CaptureLists.nextVideoFormat(lapse, tab = 0, drum = "60p", fromDrum = true))
        val leftover240 = CameraStatus(
            shootingMode = CameraCommands.SHOOT_SLOWMO,
            resolutionCode = CameraCommands.RES_1080,
            fpsIndex = 8,
            fps = 240,
        )
        assertEquals(
            listOf(VideoResolution.P1080),
            CaptureLists.formatResolutions(leftover240),
        )
        assertNull(
            CaptureLists.nextVideoFormat(leftover240, tab = 0, drum = "240p", fromDrum = false),
            "empty SlowMo on a non-Pocket-3 body must not SET 4K240 from a leftover 1080/240",
        )
        assertTrue(
            CaptureShutterPolicy.usesShutterTriggerOnPocket3(
                CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 3",
            ),
        )
        assertFalse(
            CaptureShutterPolicy.usesShutterTriggerOnPocket3(
                CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 4 Pro",
            ),
        )
        assertFalse(
            CaptureShutterPolicy.usesShutterTriggerOnPocket3(
                CameraCommands.SHOOT_HYPERLAPSE, "Osmo Pocket 3",
            ),
        )
        assertEquals("1", CaptureShutterPolicy.shootPhotoExtra(start = true))
        assertEquals("0", CaptureShutterPolicy.shootPhotoExtra(start = false))
        assertEquals(
            CaptureShutterPolicy.CaptureKind.SHUTTER_TRIGGER,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 3"),
        )
        assertEquals(
            CaptureShutterPolicy.CaptureKind.VIDEO_RECORD,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 4 Pro"),
        )
        assertEquals(
            CaptureShutterPolicy.CaptureKind.VIDEO_RECORD,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_SUPER_NIGHT, "Osmo Pocket 3"),
        )
        assertEquals(
            CaptureShutterPolicy.CaptureKind.PHOTO,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_PHOTO, "Osmo Pocket 3"),
        )
    }

    @Test
    fun portraitPhotoOpensModeNotRecSetup() {
        assertEquals("MODE", CaptureShutterPolicy.portraitSetupLabel(CameraCommands.SHOOT_PHOTO))
        assertEquals(LiveSheet.MODE, CaptureShutterPolicy.portraitSetupSheet(CameraCommands.SHOOT_PHOTO))
        assertTrue(CaptureShutterPolicy.portraitSetupOpensMode(CameraCommands.SHOOT_PHOTO))
        assertEquals("REC SETUP", CaptureShutterPolicy.portraitSetupLabel(CameraCommands.SHOOT_VIDEO))
        assertEquals(LiveSheet.FORMAT, CaptureShutterPolicy.portraitSetupSheet(CameraCommands.SHOOT_VIDEO))
        assertEquals("REC SETUP", CaptureShutterPolicy.portraitSetupLabel(CameraCommands.SHOOT_SUPER_NIGHT))
        assertFalse(CaptureShutterPolicy.canRevertFormatFailure(CameraCommands.SHOOT_PHOTO, CameraCommands.SHOOT_VIDEO))
        assertTrue(CaptureShutterPolicy.canRevertFormatFailure(CameraCommands.SHOOT_VIDEO, CameraCommands.SHOOT_VIDEO))
        val fourK30 = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS30)
        assertTrue(
            VideoFormat.allowsOperatorSet(fourK30, emptyList(), pocket3, CameraCommands.SHOOT_VIDEO),
        )
        assertFalse(
            VideoFormat.allowsOperatorSet(
                fourK30, emptyList(), CameraModel("Osmo Pocket 4 Pro"), CameraCommands.SHOOT_VIDEO,
            ),
        )
        assertFalse(CaptureLists.formatPickerEditable(CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO)))
    }

    @Test
    fun firstUnknownModeKeepsCapsButLaterModeChangeDropsThem() {
        assertTrue(CameraStatus.shouldPreserveModeDependentCaps(-1, CameraCommands.SHOOT_VIDEO))
        assertTrue(CameraStatus.shouldPreserveModeDependentCaps(CameraCommands.SHOOT_VIDEO, CameraCommands.SHOOT_VIDEO))
        assertFalse(CameraStatus.shouldPreserveModeDependentCaps(CameraCommands.SHOOT_VIDEO, CameraCommands.SHOOT_PHOTO))
        val video = CameraStatus(
            shootingMode = CameraCommands.SHOOT_VIDEO,
            availableVideoFormats = leftoverVideo,
            availableShutterDenoms = listOf(50, 100),
            availableIsoIndices = listOf(3, 4, 5),
            availableColorModes = listOf(CameraCommands.COLOR_NORMAL),
        )
        val seeded = CameraStatus(
            shootingMode = CameraCommands.SHOOT_VIDEO,
            availableShutterDenoms = emptyList(),
        ).mergingModeDependentCaps(
            CameraStatus(shootingMode = -1, availableShutterDenoms = listOf(50)),
        )
        assertEquals(listOf(50), seeded.availableShutterDenoms)
        val photo = video.copy(shootingMode = CameraCommands.SHOOT_PHOTO)
        val resurrected = photo.copy(
            availableShutterDenoms = emptyList(),
            availableIsoIndices = emptyList(),
            availableColorModes = emptyList(),
            availableVideoFormats = emptyList(),
        ).mergingModeDependentCaps(video)
        assertTrue(resurrected.availableShutterDenoms.isEmpty())
        assertTrue(resurrected.availableIsoIndices.isEmpty())
        assertTrue(resurrected.availableColorModes.isEmpty())
        assertTrue(resurrected.availableVideoFormats.isEmpty())
        val dropped = photo.droppingStaleModeDependentCaps(video)
        assertTrue(dropped.availableVideoFormats.isEmpty())
        assertTrue(dropped.availableShutterDenoms.isEmpty())
        assertTrue(dropped.availableIsoIndices.isEmpty())
        assertTrue(dropped.availableColorModes.isEmpty())
        val freshIso = photo.copy(availableIsoIndices = listOf(7, 8))
        assertEquals(listOf(7, 8), freshIso.droppingStaleModeDependentCaps(video).availableIsoIndices)
    }

    @Test
    fun modeChangeDropsLeftoverVideoCapsUnlessANewTableArrived() {
        val video = CameraStatus(
            shootingMode = CameraCommands.SHOOT_VIDEO,
            availableVideoFormats = leftoverVideo,
        )
        val photo = video.copy(shootingMode = CameraCommands.SHOOT_PHOTO)
        assertTrue(photo.droppingStaleVideoFormats(video).availableVideoFormats.isEmpty())
        val slowMoTable = listOf(VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS240))
        val slowMo = video.copy(
            shootingMode = CameraCommands.SHOOT_SLOWMO,
            availableVideoFormats = slowMoTable,
        )
        assertEquals(slowMoTable, slowMo.droppingStaleVideoFormats(video).availableVideoFormats)
        assertEquals(leftoverVideo, video.droppingStaleVideoFormats(video).availableVideoFormats)
        val cleared = video.clearedModeDependentCapabilities()
        assertTrue(cleared.availableVideoFormats.isEmpty())
        assertTrue(cleared.availableShutterDenoms.isEmpty())
        assertTrue(cleared.availableIsoIndices.isEmpty())
        assertTrue(cleared.availableColorModes.isEmpty())
        assertEquals(CameraCommands.SHOOT_VIDEO, cleared.shootingMode)
    }

    @Test
    fun effectiveFormatsIgnoreStaleVideoTableInPhoto() {
        val photo = CameraStatus(
            shootingMode = CameraCommands.SHOOT_PHOTO,
            availableVideoFormats = leftoverVideo,
        )
        assertTrue(CaptureLists.effectiveVideoFormats(photo, pocket3).isEmpty())
        val slowMo = CameraStatus(shootingMode = CameraCommands.SHOOT_SLOWMO)
        assertEquals(
            VideoFormat.pickerFormats(emptyList(), pocket3, CameraCommands.SHOOT_SLOWMO),
            CaptureLists.effectiveVideoFormats(slowMo, pocket3),
        )
    }

    @Test
    fun livePhotoIsStillCaptureWithoutLivePhotoMenuOption() {
        assertTrue(CameraCommands.isPhotoMode(CameraCommands.SHOOT_LIVE_PHOTO))
        assertEquals("Live Photo", CameraCommands.shootingModeLabel(CameraCommands.SHOOT_LIVE_PHOTO))
        assertTrue("Live Photo" !in CaptureLists.shootingModeLabels("Osmo Pocket 4 Pro"))
        assertTrue("Live Photo" !in CaptureLists.shootingModeLabels(null))
        assertTrue(
            "Live Photo" in
                CaptureLists.shootingModeLabels("Osmo Pocket 4 Pro", CameraCommands.SHOOT_LIVE_PHOTO),
        )
        assertNull(CaptureLists.shootingModeRaw("Live Photo", "Osmo Pocket 4 Pro"))
        assertEquals(
            CaptureShutterPolicy.CaptureKind.PHOTO,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_LIVE_PHOTO, "Osmo Pocket 4 Pro"),
        )
        assertFalse(
            CaptureShutterPolicy.requiresRecordConfirmation(true, CameraCommands.SHOOT_LIVE_PHOTO),
        )
        assertEquals("MODE", CaptureShutterPolicy.portraitSetupLabel(CameraCommands.SHOOT_LIVE_PHOTO))
        assertEquals(listOf("Mode"), CaptureShutterPolicy.recordingCategoryTabs(CameraCommands.SHOOT_LIVE_PHOTO))
        assertEquals(LiveSheet.MODE, CaptureShutterPolicy.opening(LiveSheet.COLOR, CameraCommands.SHOOT_LIVE_PHOTO))
        assertEquals(LiveSheet.MODE, CaptureShutterPolicy.retainedSheet(LiveSheet.FORMAT, CameraCommands.SHOOT_LIVE_PHOTO))
        assertNull(CaptureShutterPolicy.retainedSheet(LiveSheet.AUDIO, CameraCommands.SHOOT_LIVE_PHOTO))
        assertEquals(LiveSheet.ISO, CaptureShutterPolicy.retainedSheet(LiveSheet.ISO, CameraCommands.SHOOT_LIVE_PHOTO))
        assertFalse(CaptureShutterPolicy.showsColorReadout(CameraCommands.SHOOT_LIVE_PHOTO))
        assertFalse(CaptureShutterPolicy.showsAudioControls(CameraCommands.SHOOT_PHOTO))
        assertTrue(CaptureShutterPolicy.showsVideoTransport(CameraCommands.SHOOT_VIDEO))
    }

    @Test
    fun photoHidesVideoColorAudioAndIsoStars() {
        val leftover = CameraStatus(
            shootingMode = CameraCommands.SHOOT_PHOTO,
            colorMode = CameraCommands.COLOR_DLOG_M,
            availableColorModes = listOf(CameraCommands.COLOR_DLOG_M, CameraCommands.COLOR_NORMAL),
            audioChannel = CameraCommands.AUDIO_STEREO,
            availableVideoFormats = leftoverVideo,
        )
        assertNull(recordingCategoryQuickControl(LiveSheet.COLOR, leftover, family = "pocket"))
        assertTrue(CaptureLists.isoMarkedLabels(leftover).isEmpty())
        assertFalse(CaptureShutterPolicy.showsAudioControls(leftover.shootingMode))
        val photoIso = leftover.copy(
            colorMode = CameraCommands.COLOR_DLOG2,
            availableIsoIndices = listOf(0, 0x03, 0x04, 0x05),
            isoLimit = 0x05,
        )
        assertTrue(CaptureLists.offersIsoAuto(photoIso))
        assertEquals("100\u2013200", CaptureLists.isoAutoLabels(photoIso).first())
        assertEquals("100\u20131600", CaptureLists.isoAutoLabel(photoIso))
        assertEquals(
            IsoLimit.Max800,
            CaptureLists.isoLimit("100\u2013800", photoIso),
        )
        val emptyCaps = leftover.copy(colorMode = CameraCommands.COLOR_DLOG2, isoIndex = 0x05)
        assertTrue(CaptureLists.offersIsoAuto(emptyCaps))
        assertEquals(
            CaptureLists.isoFallback(CameraCommands.COLOR_NORMAL),
            CaptureLists.isoIndices(emptyCaps),
        )
        val video = leftover.copy(shootingMode = CameraCommands.SHOOT_VIDEO)
        assertEquals(setOf("400"), CaptureLists.isoMarkedLabels(video.copy(colorMode = CameraCommands.COLOR_DLOG)))
    }

    @Test
    fun pocket4ProTele200UsesAdvertisedCapabilityNotInvented240() {
        assertEquals(200, VideoFrameRate.FPS200.fps)
        assertEquals("200p", VideoFrameRate.FPS200.drumLabel)
        assertEquals(VideoFrameRate.FPS200, VideoFrameRate.fromDrumLabel("200p"))
        assertEquals(VideoFrameRate.FPS200, VideoFrameRate.fromFps(200))
        assertEquals(200, VideoFrameRate.fps(0x13))
        assertEquals(200, CameraCommands.fpsFromSubscribeIndex(0x13))
        val tele200 = listOf(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS200))
        val pro = CameraModel("Osmo Pocket 4 Pro")
        assertEquals(tele200, VideoFormat.pickerFormats(tele200, pro, CameraCommands.SHOOT_SLOWMO))
        assertTrue(
            VideoFormat.allowsOperatorSet(
                tele200.first(), tele200, pro, CameraCommands.SHOOT_SLOWMO,
            ),
        )
        assertFalse(
            VideoFormat.allowsOperatorSet(
                VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS240),
                tele200,
                pro,
                CameraCommands.SHOOT_SLOWMO,
            ),
        )
        assertTrue(
            VideoFormat.pickerFormats(emptyList(), pro, CameraCommands.SHOOT_SLOWMO).isEmpty(),
        )
        val status = CameraStatus(
            shootingMode = CameraCommands.SHOOT_SLOWMO,
            resolutionCode = VideoResolution.P4K.rawValue,
            fpsIndex = VideoFrameRate.FPS200.rawValue,
            fps = 200,
            availableVideoFormats = tele200,
        )
        val hold = recordingCategoryQuickControl(LiveSheet.FORMAT, status, "Osmo Pocket 4 Pro")
        assertEquals(listOf("200p"), hold?.options)
        assertEquals("200p", hold?.selection)
        assertTrue(hold!!.enabled)
        assertTrue(CameraModel.looksLikePocket4Pro("Osmo Pocket 4 Pro"))
        assertTrue(CameraModel.looksLikePocket4Pro("OsmoPocket4P-ABCD"))
        assertFalse(CameraModel.looksLikePocket4Pro("Osmo Pocket 4"))
        assertFalse(CameraModel.looksLikePocket4Pro("Hero4Pro"))
        assertTrue(CameraModel.supportsSlowMoFormatTrailer("OsmoPocket4P-ABCD"))
        assertFalse(CameraModel.supportsSlowMoFormatTrailer("Osmo Pocket 4"))
    }
}
