package com.opencapture.openpocketcine.feed

private const val ATLAS_COLUMNS = 8

/** GLES2-safe 8×8 blue-slice atlas for one packed-2D RGB cube. */
internal data class FeedEffectsCubeAtlas(
    val cubeSize: Int,
    val width: Int,
    val height: Int,
    val rgba: ByteArray,
)

/**
 * Converts the core's packed `width = size², height = size` bitmap into an 8×8 atlas.
 *
 * The maximum 64³ cube becomes exactly 512×512, avoiding a 4096-pixel texture-width
 * dependency on GLES2 devices while retaining adjacent red/green texels for bilinear
 * filtering.
 */
internal fun feedEffectsCubeAtlas(cube: FeedEffectsCube): FeedEffectsCubeAtlas {
    val size = cube.size
    val width = size * ATLAS_COLUMNS
    val height = size * ATLAS_COLUMNS
    val atlas = ByteArray(width * height * 4)
    for (blue in 0 until size) {
        val tileX = blue % ATLAS_COLUMNS
        val tileY = blue / ATLAS_COLUMNS
        for (green in 0 until size) {
            val sourceOffset = (green * size * size + blue * size) * 4
            val destinationOffset = ((tileY * size + green) * width + tileX * size) * 4
            cube.rgba.copyInto(
                destination = atlas,
                destinationOffset = destinationOffset,
                startIndex = sourceOffset,
                endIndex = sourceOffset + size * 4,
            )
        }
    }
    return FeedEffectsCubeAtlas(size, width, height, atlas)
}

/**
 * Vulkan 3D LUT: R along X, G along Y, B along Z — same lattice as iOS
 * `CIColorCube`. The 8-column 2D atlas bilinear-filters across blue tiles.
 */
internal fun feedEffectsCubeVk3d(cube: FeedEffectsCube): ByteArray {
    val n = cube.size
    val out = ByteArray(n * n * n * 4)
    for (blue in 0 until n) {
        for (green in 0 until n) {
            for (red in 0 until n) {
                val src = (green * n * n + blue * n + red) * 4
                val dst = (blue * n * n + green * n + red) * 4
                cube.rgba.copyInto(out, dst, src, src + 4)
            }
        }
    }
    return out
}
