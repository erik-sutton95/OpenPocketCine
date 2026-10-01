package com.opencapture.openpocketcine.session

import android.media.MediaCodec
import android.media.MediaCodecList
import com.opencapture.opencine.media.LiveHevcCodec

/** First hardware decoder for [mime]; a software one only when nothing else decodes it. */
internal fun LiveHevcCodec.createDecoder(mime: String): MediaCodec {
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
