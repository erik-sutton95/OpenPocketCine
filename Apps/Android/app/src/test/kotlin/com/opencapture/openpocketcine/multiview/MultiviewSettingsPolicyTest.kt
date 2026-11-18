package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.CapabilitySnapshot
import com.opencapture.opencine.core.SettingAccess
import com.opencapture.opencine.core.SupportStatus
import com.opencapture.opencine.dji.fromJson
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.ControlCapabilities
import com.opencapture.opencine.vocabulary.ControlCapability
import com.opencapture.opencine.vocabulary.NoOffer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewSettingsPolicyTest {
    private fun categories(camera: CameraModel, status: CameraStatus): List<MultiviewSettingsCategory> =
        multiviewSettingsCategories(camera, status, ControlCapabilities.derive(
            CapabilitySnapshot(audioLevels = SupportStatus.SUPPORTED), camera.captureProfile))

    @Test fun audioAdmissionUsesTypedSupport() {
        val camera = CameraModel("SIMULATED camera")
        val video = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO)
        val declarations = listOf(ControlCapability.unknown<NoOffer>(), ControlCapability.unsupported<NoOffer>(),
            ControlCapability.supported<NoOffer>(), ControlCapability.supported<NoOffer>(access = SettingAccess.READ_ONLY))
        for (audio in declarations) {
            val controls = ControlCapabilities(audio = audio)
            assertEquals(audio.isOffered, MultiviewSettingsCategory.AUDIO in multiviewSettingsCategories(camera, video, controls),
                "${audio.support}/${audio.access}")
            assertFalse(MultiviewSettingsCategory.AUDIO in multiviewSettingsCategories(camera,
                video.copy(shootingMode = CameraCommands.SHOOT_PHOTO), controls))
        }
    }

    @Test fun nativeCategoriesFollowCameraCapabilitiesAndShootingModeInIOSOrder() {
        val pocket = CameraModel.fromJson("""{"name":"Osmo Pocket 4","family":"pocket","supportsFocusMode":true,"supportsTapFocus":true}""")
        val video = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO)
        // Pocket iOS's rail: mode before format and color.
        assertEquals(listOf(MultiviewSettingsCategory.ISO, MultiviewSettingsCategory.SHUTTER,
            MultiviewSettingsCategory.EXPOSURE, MultiviewSettingsCategory.WB, MultiviewSettingsCategory.FOCUS,
            MultiviewSettingsCategory.MODE, MultiviewSettingsCategory.RESOLUTION, MultiviewSettingsCategory.COLOR,
            MultiviewSettingsCategory.AUDIO),
            categories(pocket, video))
        val photo = categories(pocket, video.copy(shootingMode = CameraCommands.SHOOT_PHOTO))
        assertTrue(photo.containsAll(listOf(MultiviewSettingsCategory.ISO, MultiviewSettingsCategory.WB, MultiviewSettingsCategory.MODE)))
        assertFalse(photo.any { it in listOf(MultiviewSettingsCategory.RESOLUTION, MultiviewSettingsCategory.COLOR, MultiviewSettingsCategory.AUDIO) })
        val nano = CameraModel("Osmo Nano", family = "nano", supportsFocusMode = false, supportsTapFocus = false)
        assertFalse(MultiviewSettingsCategory.FOCUS in categories(nano, video))
        assertFalse(MultiviewSettingsCategory.APERTURE in categories(pocket, video))
        assertTrue(MultiviewSettingsCategory.APERTURE in categories(CameraModel.fromJson("""{"name":"Osmo Action 6","family":"other","supportsFocusMode":false,"supportsAperture":true}"""), video))
    }

    @Test fun everyCategoryOpensItsLiveViewSheet() {
        assertEquals(LiveSheet.EXPO, MultiviewSettingsCategory.EXPOSURE.liveSheet)
        assertEquals(LiveSheet.FORMAT, MultiviewSettingsCategory.RESOLUTION.liveSheet)
        assertEquals(MultiviewSettingsCategory.entries.size, MultiviewSettingsCategory.entries.map { it.liveSheet }.toSet().size)
    }

    @Test fun recordingLocksModeFormatAndColorButKeepsExposureControls() {
        for (category in MultiviewSettingsCategory.entries) {
            assertFalse(category.locked(false))
            assertEquals(category.liveSheet in listOf(LiveSheet.MODE, LiveSheet.FORMAT, LiveSheet.COLOR), category.locked(true))
        }
    }
}
