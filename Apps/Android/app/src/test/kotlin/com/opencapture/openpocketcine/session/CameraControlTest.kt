package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.bridge.SwiftCore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CameraControlTest {
    @Test
    fun shutterIsU16DenomOr8000() {
        val p = CameraCommands.shutter(1600)
        assertEquals(7, p.size)
        assertEquals(0x01, p[0].toInt() and 0xFF)
        val coded = (p[1].toInt() and 0xFF) or ((p[2].toInt() and 0xFF) shl 8)
        assertEquals(1600 or 0x8000, coded)
        assertEquals(0x40, p[6].toInt() and 0xFF)
    }

    @Test
    fun isoIsIndexNotNumber() {
        assertEquals(1, CameraCommands.isoIndex(0x07).size)
        assertEquals(0x07, CameraCommands.isoIndex(0x07)[0].toInt() and 0xFF)
    }

    @Test
    fun resFpsIsOneBlob() {
        val p = CameraCommands.resolutionFps(CameraCommands.RES_4K, 6)
        assertTrue(p.contentEquals(byteArrayOf(0x10, 0x06, 0x00, 0x00, 0x00)))
    }

    @Test
    fun audioDspPatchesOnlyByte2() {
        val blob = ByteArray(26) { 0 }
        blob[0] = 0xC0.toByte()
        blob[2] = CameraCommands.DIR_ALL.toByte()
        val patched = CameraCommands.audioDspSet(blob, CameraCommands.WIND_ON)
        assertEquals(0xC0, patched[0].toInt() and 0xFF)
        assertEquals(CameraCommands.WIND_ON, patched[2].toInt() and 0xFF)
        assertEquals(26, patched.size)
    }

    @Test
    fun statusJsonRoundTripsHudFields() {
        val src =
            CameraStatus(
                iso = 400,
                shutterDenom = 50,
                fps = 24,
                expoMode = CameraCommands.EXPO_MANUAL,
                isoIndex = 0x05,
                colorMode = CameraCommands.COLOR_DLOG,
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 1,
                wbMode = CameraCommands.WB_CUSTOM,
                wbKelvin = 5600,
                wbTint = -5,
                focusMode = CameraCommands.FOCUS_CONTINUOUS,
                audioChannel = CameraCommands.AUDIO_STEREO,
                vocalBoost = 1,
                audioDspBlob = "c0041a0500" + "00".repeat(21),
                audioDspAt2 = CameraCommands.WIND_ON,
            )
        val decoded = CameraStatus.fromJson(src.toJson())
        assertEquals(400, decoded.iso)
        assertEquals(50, decoded.shutterDenom)
        assertEquals(24, decoded.fps)
        assertEquals(CameraCommands.EXPO_MANUAL, decoded.expoMode)
        assertEquals(0x05, decoded.isoIndex)
        assertEquals(CameraCommands.COLOR_DLOG, decoded.colorMode)
        assertEquals(CameraCommands.RES_4K, decoded.resolutionCode)
        assertEquals(5600, decoded.wbKelvin)
        assertEquals(-5, decoded.wbTint)
        assertEquals(CameraCommands.FOCUS_CONTINUOUS, decoded.focusMode)
        assertEquals(CameraCommands.AUDIO_STEREO, decoded.audioChannel)
        assertEquals(1, decoded.vocalBoost)
        assertEquals(1, decoded.windNr)
        assertTrue(decoded.audioDspBlob.startsWith("c0041a"))
    }

    @Test
    fun gimbalStickIsDocumentedPayload() {
        val rest = CameraCommands.gimbalStickPayload(
            CameraCommands.GIMBAL_STICK_CENTER,
            CameraCommands.GIMBAL_STICK_CENTER,
        )
        assertTrue(
            rest.contentEquals(
                byteArrayOf(0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x80.toByte(), 0x22, 0x00),
            ),
        )
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, CameraCommands.gimbalAxis(0f))
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, CameraCommands.gimbalAxis(0.04f))
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, CameraCommands.gimbalAxis(1f))
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, CameraCommands.gimbalAxis(-1f))
        val right = CameraCommands.gimbalAxes(1f, 0f)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, right.first)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, right.second)
        val up = CameraCommands.gimbalAxes(0f, 1f)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, up.first)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, up.second)
    }

    @Test
    fun expoSubscribeUsesDocumentedOffsets() {
        val expo = ByteArray(46)
        expo[2] = 0x32
        expo[3] = 0x80.toByte()
        expo[5] = 0x05
        expo[7] = CameraCommands.EXPO_AUTO.toByte()
        expo[16] = 0x90.toByte()
        expo[17] = 0x01
        val next = StatusExtras.applyExpo(expo, CameraStatus())
        assertEquals(50, next.shutterDenom)
        assertEquals(0x05, next.isoIndex)
        assertEquals(CameraCommands.EXPO_AUTO, next.expoMode)
        assertEquals(400, next.iso)
    }

    @Test
    fun camFovUsesAt0() {
        val value = byteArrayOf(
            0xFF.toByte(), 0x2F, 0x00, 0x00, 0x00, 0x1B, 0x00, 0x00, 0x01, 0x00,
            0x00, 0x00, 0xA8.toByte(), 0x1B, 0x00, 0x00, 0x01, 0x99.toByte(), 0x31,
            0x00, 0x00, 0x00, 0x1C, 0x00, 0x00,
        )
        val next = StatusExtras.applyFov(value, CameraStatus())
        assertEquals(12287, next.zoomFactorRaw)
        val packed = StatusExtras.packSubscribe("cam_fov", value)
        val fromPush = StatusExtras.applySubscribe(packed, CameraStatus())
        assertEquals(12287, fromPush.zoomFactorRaw)
        val roundTrip = CameraStatus(zoomFactorRaw = 12287)
        assertEquals(12287, CameraStatus.fromJson(roundTrip.toJson()).zoomFactorRaw)
    }

    @Test
    fun camcapShutterTwentyFivePDiffersFromSixtyP() {
        val p25 = CameraCommands.parseShutterDenoms(hex(SHUTTER_25P))
        val p60 = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P))
        assertTrue(p25.contains(25))
        assertTrue(p25.contains(50))
        assertTrue(p60.contains(50))
        assertTrue(!p60.contains(25))
        assertTrue(p25 != p60)
        val wheel = CameraCommands.shutterWheelDenoms(p60, 48)
        assertEquals(p60, wheel)
        assertTrue(!wheel.contains(48))
        assertTrue(!wheel.contains(13))
    }

    @Test
    fun dLogStars400AndDLog2Stars1600() {
        val dlog2 = CameraCommands.parseIsoIndices(hex("0108000006030405060708"))
        assertEquals(listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08), dlog2)
        assertEquals("400", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG))
        assertEquals("1600", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG2))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_NORMAL))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_HDR))
        assertEquals(null, CameraCommands.baseIsoLabel(-1))
        assertEquals("400 ★", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_DLOG))
        assertEquals("1600", CameraCommands.isoChipLabel("1600", CameraCommands.COLOR_DLOG))
        assertEquals("1600 ★", CameraCommands.isoChipLabel("1600", CameraCommands.COLOR_DLOG2))
        assertEquals("400", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_DLOG2))
        assertEquals("800", CameraCommands.isoChipLabel("800", CameraCommands.COLOR_DLOG))
        assertEquals("400", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_NORMAL))
        assertTrue(dlog2.contains(0x05))
        assertTrue(dlog2.contains(0x07))
        assertEquals("400", CameraCommands.isoLabel(0x05))
        assertEquals("1600", CameraCommands.isoLabel(0x07))
    }

    @Test
    fun camcapShutterSubscribeUpdatesStatus() {
        val packed = StatusExtras.packSubscribe("camcap_shutter", hex(SHUTTER_60P))
        val next = StatusExtras.applySubscribe(packed, CameraStatus(fps = 60, shutterDenom = 50))
        assertTrue(next.availableShutterDenoms.contains(50))
        assertEquals(60, next.fps)
        val json = next.toJson()
        assertEquals(next.availableShutterDenoms, CameraStatus.fromJson(json).availableShutterDenoms)
    }

    @Test
    fun statusJsonRoundTripsParityFields() {
        val src =
            CameraStatus(
                evComp = 0x10,
                isoLimit = 0x07,
                availableColorModes = listOf(0x3F, 0x3C),
                focusX = 0.25,
                focusY = 0.75,
                hasCameraFocusPoint = true,
                focusTrack = 2,
                zoomLens = 217,
                zoomFactor = 1.0,
                glamourEnabled = false,
                windNr = 1,
                directionalAudio = 0,
                audioMetersLeft = -12.0,
                audioMetersRight = -14.0,
                audioPeakLeft = -6.0,
                audioPeakRight = -8.0,
            )
        val json = src.toJson()
        assertTrue(json.contains("\"windNR\":"))
        assertTrue(json.contains("\"evComp\":16"))
        val decoded = CameraStatus.fromJson(json)
        assertEquals(0x10, decoded.evComp)
        assertEquals(0x07, decoded.isoLimit)
        assertEquals(listOf(0x3F, 0x3C), decoded.availableColorModes)
        assertEquals(0.25, decoded.focusX, 1e-6)
        assertEquals(0.75, decoded.focusY, 1e-6)
        assertEquals(true, decoded.hasCameraFocusPoint)
        assertEquals(2, decoded.focusTrack)
        assertEquals(217, decoded.zoomLens)
        assertEquals(1.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(false as Boolean?, decoded.glamourEnabled)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(-12.0, decoded.audioMetersLeft, 1e-6)
        assertEquals(-14.0, decoded.audioMetersRight, 1e-6)
        assertEquals(-6.0, decoded.audioPeakLeft, 1e-6)
        assertEquals(-8.0, decoded.audioPeakRight, 1e-6)
    }

    @Test
    fun statusJsonParsesCoreWindAndDirectionalRaws() {
        val json =
            """{"windNR":26,"directionalAudio":218,"evComp":16,"zoomLens":651,"zoomFactor":3.0,"glamourEnabled":true}"""
        val decoded = CameraStatus.fromJson(json)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(0x10, decoded.evComp)
        assertEquals(651, decoded.zoomLens)
        assertEquals(3.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(true as Boolean?, decoded.glamourEnabled)
    }

    @Test
    fun cameraModelJsonUsesPocketDefaults() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Pocket 4","datalinkPort":9004,"tcpPoke":true,"wpa3":false,"verified":true,"isDrone":false,"pairingToken":"osmo"}""",
            )
        assertEquals("pocket", parsed.family)
        assertEquals(8, parsed.liveViewEnableReceiver)
        assertEquals(false, parsed.usesNanoLiveViewGate)
        assertEquals(true, parsed.supportsTapFocus)
        assertEquals(true, parsed.supportsFocusMode)
        assertEquals(true, parsed.usesCapturedLiveEnable)
    }

    @Test
    fun cameraModelJsonParsesNanoFields() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Nano","family":"nano","liveViewEnableReceiver":65,"usesNanoLiveViewGate":true,"supportsTapFocus":false,"supportsFocusMode":false,"usesCapturedLiveEnable":true}""",
            )
        assertEquals("nano", parsed.family)
        assertEquals(65, parsed.liveViewEnableReceiver)
        assertEquals(true, parsed.usesNanoLiveViewGate)
        assertEquals(false, parsed.supportsTapFocus)
        assertEquals(false, parsed.supportsFocusMode)
    }

    @Test
    fun waitKeyCoversNewCommands() {
        assertEquals(0x0201, SwiftCore.waitKey(SwiftCore.CMD_SHOOT_PHOTO))
        assertEquals(0x02E1, SwiftCore.waitKey(SwiftCore.CMD_SET_SHOOTING_MODE))
        assertEquals(0x022E, SwiftCore.waitKey(SwiftCore.CMD_SET_EV))
        assertEquals(0x02B8, SwiftCore.waitKey(SwiftCore.CMD_SET_ZOOM_LENS))
        assertEquals(0x02A6, SwiftCore.waitKey(SwiftCore.CMD_SET_TRACKING_BOX))
        assertEquals(0x02A5, SwiftCore.waitKey(SwiftCore.CMD_POLL_TRACKING))
        assertEquals(0x044C, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_RECENTER))
        assertEquals(0x044C, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_FLIP))
        assertEquals(0x020C, SwiftCore.waitKey(SwiftCore.CMD_EXIT_PLAYBACK))
        assertEquals(0x0026, SwiftCore.waitKey(SwiftCore.CMD_MEDIA_LIST))
        assertEquals(0x0028, SwiftCore.waitKey(SwiftCore.CMD_DELETE_MEDIA))
        assertEquals(0x02BF, SwiftCore.waitKey(SwiftCore.CMD_SET_MEDIA_FAVORITE))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_GET_ISO_LIMIT))
        assertEquals(0x0209, SwiftCore.waitKey(SwiftCore.CMD_NANO_LIVE_VIEW_GATE))
        assertEquals(0, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_STICK))
    }

    companion object {
        private const val SHUTTER_25P =
            "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
        private const val SHUTTER_60P =
            "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"

        private fun hex(s: String): ByteArray {
            return ByteArray(s.length / 2) { i ->
                s.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        }
    }
}
