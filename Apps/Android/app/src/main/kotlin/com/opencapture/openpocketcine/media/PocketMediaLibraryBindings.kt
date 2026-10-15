package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.MonitorMediaLibraryActionToken
import com.opencapture.opencine.appkit.MonitorMediaLibraryModel
import com.opencapture.opencine.vocabulary.MediaFile

/** Admitted host metadata changes only the actual record facts, never the source catalog/page count. */
internal fun applyPocketMediaColor(owner: MonitorMediaLibraryModel<MediaFile>,
    codec: PocketMediaLibraryCodec, file: MediaFile, mode: Int,
    token: MonitorMediaLibraryActionToken): Boolean {
    if (mode < 0 || !owner.isCurrent(token)) return false
    val current = owner.record(com.opencapture.opencine.dji.DjiAndroidMediaAssets.asset(file).id) ?: return false
    owner.updateLocalFacts(mapOf(current.asset.id to codec.record(current.payload, mode).facts), token)
    return owner.isCurrent(token)
}
