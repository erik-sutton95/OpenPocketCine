package com.opencapture.openpocketcine

import com.opencapture.opencine.dji.commandExtra
import com.opencapture.opencine.dji.payload
import com.opencapture.opencine.dji.setPayload
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.opencine.vocabulary.VideoFrameRate
import com.opencapture.opencine.vocabulary.VideoResolution
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class ShootingModePolishTest {
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
}
