package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FeedEffectsCubeAtlasTest {
    @Test
    fun `repacking preserves red-fastest cube pixels in blue slice tiles`() {
        val size = 2
        val source = ByteArray(size * size * size * 4)
        for (green in 0 until size) {
            for (blue in 0 until size) {
                for (red in 0 until size) {
                    val value = (blue * 40 + green * 10 + red).toByte()
                    val offset = (green * size * size + blue * size + red) * 4
                    source.fill(value, offset, offset + 4)
                }
            }
        }

        val atlas = feedEffectsCubeAtlas(FeedEffectsCube(size, source))

        assertEquals(16, atlas.width)
        assertEquals(16, atlas.height)
        for (green in 0 until size) {
            for (blue in 0 until size) {
                for (red in 0 until size) {
                    val expected = ByteArray(4) { (blue * 40 + green * 10 + red).toByte() }
                    val atlasOffset = (green * atlas.width + blue * size + red) * 4
                    assertContentEquals(
                        expected,
                        atlas.rgba.copyOfRange(atlasOffset, atlasOffset + 4),
                    )
                }
            }
        }
    }

    @Test
    fun `official 33 cube is an 8-column 264 atlas`() {
        val size = 33
        val atlas =
            feedEffectsCubeAtlas(
                FeedEffectsCube(size, ByteArray(size * size * size * 4)),
            )
        assertEquals(264, atlas.width)
        assertEquals(264, atlas.height)
        assertEquals(264 * 264 * 4, atlas.rgba.size)
        assertEquals(size, atlas.cubeSize)
    }

    @Test
    fun `largest supported cube fits the fixed 512 square atlas`() {
        val size = 64
        val atlas =
            feedEffectsCubeAtlas(
                FeedEffectsCube(size, ByteArray(size * size * size * 4)),
            )

        assertEquals(512, atlas.width)
        assertEquals(512, atlas.height)
        assertEquals(512 * 512 * 4, atlas.rgba.size)
    }

    @Test
    fun `fromPacked rejects a truncated payload`() {
        assertNull(FeedEffectsCube.fromPacked(ByteArray(7)))
        assertNull(FeedEffectsCube.fromPacked(ByteArray(12)))
        val cube = FeedEffectsCube.fromPacked(ByteArray(2 * 2 * 2 * 4))
        assertEquals(2, cube?.size)
    }
}
