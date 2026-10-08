package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.dji.fromJson
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.FocusOption
import com.opencapture.opencine.vocabulary.GamepadGimbalStick
import com.opencapture.opencine.vocabulary.GimbalDoubleTap
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalRamp
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.IsoLimit
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Every picker the app builds from camera-vocabulary values, pinned to the lists main showed before the
 * vocabulary took Insta360's values (I-2): ISO 160, I-Log, Dolby Vision and the 8K-class sizes never
 * reach a DJI picker.
 */
class PickerListsTest {
    private fun list(text: String) = text.split("|")

    @Test fun gimbalPickers() {
        assertEquals(list("Follow|Tilt locked|FPV|Direction Lock"), GimbalMode.pickerOrder.map { it.label })
        assertEquals(list("Slow|Default|Fast"), GimbalSpeed.pickerOrder.map { it.label })
        assertEquals(list("Off|Soft|Medium"), GimbalRamp.pickerOrder.map { it.label })
        assertEquals(list("Recenter|Level"), GimbalDoubleTap.pickerOrder.map { it.label })
    }

    @Test fun focusPicker() {
        assertEquals(list("AF-S|AF-C|Showcase|Lock|Priority"), FocusOption.entries.map { it.chip })
    }

    @Test fun shootingModePickers() {
        val standard = list("Video|Photo|TimeLapse|HyperLapse|SuperNight|SlowMo")
        for (name in listOf("Osmo Pocket 4 Pro", "Osmo Pocket 4", "Osmo Nano", "Osmo Action 6", null)) {
            assertEquals(standard, CaptureLists.shootingModeLabels(name), "$name")
        }
        assertEquals(list("Video|Photo|TimeLapse|HyperLapse|Low-Light|SlowMo"), CaptureLists.shootingModeLabels("Osmo Pocket 3",
            profile = CameraModel.fromJson("""{"name":"Osmo Pocket 3"}""").captureProfile!!.labels))
        assertEquals(
            list("Video|Photo|Live Photo|TimeLapse|HyperLapse|SuperNight|SlowMo"),
            CaptureLists.shootingModeLabels("Osmo Pocket 4 Pro", CameraCommands.SHOOT_LIVE_PHOTO),
        )
    }

    @Test fun colorPickers() {
        val wheels = listOf(
            Triple("Osmo Pocket 4 Pro", "pocket", "Normal|HDR|D-Log|D-Log2"),
            Triple("Osmo Pocket 4", "pocket", "Normal|HDR|D-Log"),
            Triple("Osmo Pocket 3", "pocket", "Normal|HDR|D-Log M"),
            Triple("Osmo Nano", "nano", "Normal 8-bit|Normal 10-bit|D-Log M 10-bit"),
            Triple("Osmo Action 6", "other", "Normal 10-bit|D-Log M"),
            Triple("", "pocket", "Normal|HDR|D-Log"),
        )
        for ((name, family, labels) in wheels) {
            assertEquals(list(labels), CaptureLists.colorWheelLabels(CameraStatus(), family, name,
                CameraModel.fromJson("""{"name":"$name","family":"$family"}""").captureProfile!!.labels), name)
        }
    }

    @Test fun isoPickers() {
        val full = list("100|200|400|800|1600|3200|6400|12800|25600")
        for (color in listOf(
            CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_HDR, CameraCommands.COLOR_DLOG_M,
            CameraCommands.COLOR_NORMAL10, -1,
        )) {
            assertEquals(full, CaptureLists.isoDrumLabels(CameraStatus(colorMode = color)), "color $color")
        }
        assertEquals(list("400|800|1600|3200|6400"), CaptureLists.isoDrumLabels(CameraStatus(colorMode = CameraCommands.COLOR_DLOG)))
        assertEquals(list("100|200|400|800|1600|3200"), CaptureLists.isoDrumLabels(CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)))
        val camcap = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, availableIsoIndices = listOf(0, 3, 4, 5, 6, 7, 8))
        assertEquals(list("100|200|400|800|1600|3200"), CaptureLists.isoDrumLabels(camcap))
    }

    @Test fun exposureAndControlPickers() {
        assertEquals(list("Auto|Manual"), CaptureLists.expoLabels)
        assertEquals(
            list("−3.0|−2.7|−2.3|−2.0|−1.7|−1.3|−1.0|−0.7|−0.3|0.0|+0.3|+0.7|+1.0|+1.3|+1.7|+2.0|+2.3|+2.7|+3.0"),
            CaptureLists.evLabels,
        )
        assertEquals(list("Max200|Max400|Max800|Max1600|Max3200|Max6400|Max12800|Max25600"), IsoLimit.entries.map { it.name })
        assertEquals(list("Linear|Standard|Fine"), CameraCommands.VirtualJoystickCurve.entries.map { it.label })
        assertEquals(list("Left|Right"), GamepadGimbalStick.entries.map { it.label })
    }
}
