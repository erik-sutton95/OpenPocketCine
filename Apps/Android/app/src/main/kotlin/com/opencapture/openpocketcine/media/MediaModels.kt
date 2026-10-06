package com.opencapture.openpocketcine.media

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.dji.MediaCommands


fun MediaHTTP.pathUrl(storage: Int, path: String): HttpUrl = pathUrlString(storage, path).toHttpUrl()

internal fun writeU32LE(dest: ByteArray, offset: Int, value: Long) {
    dest[offset] = (value and 0xFF).toByte()
    dest[offset + 1] = ((value shr 8) and 0xFF).toByte()
    dest[offset + 2] = ((value shr 16) and 0xFF).toByte()
    dest[offset + 3] = ((value shr 24) and 0xFF).toByte()
}

internal fun wrappingSub32(a: Long, b: Long): Long = (a - b) and 0xFFFF_FFFFL

internal fun wrappingAdd32(a: Long, b: Long): Long = (a + b) and 0xFFFF_FFFFL

internal fun wrappingMul32(a: Long, b: Long): Long = (a * b) and 0xFFFF_FFFFL
