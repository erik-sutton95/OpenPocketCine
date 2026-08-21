package com.opencapture.openpocketcine.feed

import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Blits `GL_TEXTURE_EXTERNAL_OES` (MediaCodec / SurfaceTexture) into a 2D
 * target so the feed-effects shaders can keep `sampler2D` random access.
 */
internal class OesCopyGlProgram(context: Context) {
    private val program: Int
    private val aPosition: Int
    private val uTex: Int
    private val uMatrix: Int
    private val quad: FloatBuffer =
        ByteBuffer.allocateDirect(QUAD.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(QUAD)
            position(0)
        }

    init {
        val vertex = loadAsset(context, "shaders/playback_feed_vertex_es2.glsl")
        val fragment = loadAsset(context, "shaders/oes_copy_fragment_es2.glsl")
        program = link(compile(GLES20.GL_VERTEX_SHADER, vertex), compile(GLES20.GL_FRAGMENT_SHADER, fragment))
        aPosition = GLES20.glGetAttribLocation(program, "aFramePosition")
        uTex = GLES20.glGetUniformLocation(program, "uTexSampler")
        uMatrix = GLES20.glGetUniformLocation(program, "uTexMatrix")
        check(aPosition >= 0 && uTex >= 0 && uMatrix >= 0) { "OES copy program is missing uniforms" }
    }

    fun draw(oesTexture: Int, texMatrix: FloatArray) {
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexture)
        GLES20.glUniform1i(uTex, 0)
        GLES20.glUniformMatrix4fv(uMatrix, 1, false, texMatrix, 0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 4, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
    }

    fun release() {
        GLES20.glDeleteProgram(program)
    }

    companion object {
        private val QUAD =
            floatArrayOf(
                -1f, -1f, 0f, 1f,
                1f, -1f, 0f, 1f,
                -1f, 1f, 0f, 1f,
                1f, 1f, 0f, 1f,
            )

        private fun loadAsset(context: Context, path: String): String =
            context.assets.open(path).bufferedReader().use { it.readText() }

        private fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            check(status[0] != 0) { GLES20.glGetShaderInfoLog(shader) }
            return shader
        }

        private fun link(vertex: Int, fragment: Int): Int {
            val program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vertex)
            GLES20.glAttachShader(program, fragment)
            GLES20.glLinkProgram(program)
            val status = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
            GLES20.glDeleteShader(vertex)
            GLES20.glDeleteShader(fragment)
            check(status[0] != 0) { GLES20.glGetProgramInfoLog(program) }
            return program
        }
    }
}
