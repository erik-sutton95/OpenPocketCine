@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.Bitmap
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import com.opencapture.opencine.runtime.NativeGlBackend
import com.opencapture.opencine.runtime.NativeGlProgram

/** SIMULATED native-pixel oracle: original SDK adapter retained unchanged in tests. */
internal class OriginalMedia3GlBackend(private val context: Context) : NativeGlBackend {
    override fun createProgram(vertexAsset: String, fragmentAsset: String): NativeGlProgram =
        Media3Program(GlProgram(context, vertexAsset, fragmentAsset))
    override fun normalizedCoordinateBounds() = GlUtil.getNormalizedCoordinateBounds()
    override val homogeneousCoordinateVectorSize get() = GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE
    override fun createTexture(width: Int, height: Int) = GlUtil.createTexture(width, height, false)
    override fun createTexture(bitmap: Bitmap) = GlUtil.createTexture(bitmap)
    override fun createFramebuffer(texture: Int) = GlUtil.createFboForTexture(texture)
    override fun focusFramebuffer(framebuffer: Int, width: Int, height: Int) =
        GlUtil.focusFramebufferUsingCurrentContext(framebuffer, width, height)
    override fun deleteFramebuffer(framebuffer: Int) = GlUtil.deleteFbo(framebuffer)
    override fun deleteTexture(texture: Int) = GlUtil.deleteTexture(texture)
    override fun checkError() = GlUtil.checkGlError()
}

private class Media3Program(private val program: GlProgram) : NativeGlProgram {
    override fun use() = program.use()
    override fun setBufferAttribute(name: String, values: FloatArray, size: Int) = program.setBufferAttribute(name, values, size)
    override fun setFloatsUniform(name: String, values: FloatArray) = program.setFloatsUniform(name, values)
    override fun setSamplerTexIdUniform(name: String, texture: Int, unit: Int) = program.setSamplerTexIdUniform(name, texture, unit)
    override fun bindAttributesAndUniforms() = program.bindAttributesAndUniforms()
    override fun delete() = program.delete()
}
