package com.opencapture.openpocketcine.session

import android.media.MediaCodec
import android.media.MediaCodecList

/** Prefer a silicon HEVC/AVC decoder. `createDecoderByType` can still pick `c2.android.*`. */
internal object LiveHevcCodec {
    fun isSoftwareName(name: String): Boolean {
        val n = name.lowercase()
        return n.contains("omx.google.") ||
            n.contains("c2.android.") ||
            n.contains(".google.") ||
            n.contains("swdecoder") ||
            n.endsWith(".sw")
    }

    fun createDecoder(mime: String): MediaCodec {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        var software: String? = null
        for (info in list.codecInfos) {
            if (info.isEncoder) continue
            if (!info.supportedTypes.any { it.equals(mime, ignoreCase = true) }) continue
            if (isSoftwareName(info.name)) {
                if (software == null) software = info.name
                continue
            }
            return MediaCodec.createByCodecName(info.name)
        }
        return software?.let { MediaCodec.createByCodecName(it) } ?: MediaCodec.createDecoderByType(mime)
    }
}
