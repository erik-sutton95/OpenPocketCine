package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.*
import java.io.File
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile

/** Actual Pocket source values; shared playback owns attempts, preparation and cache commits. */
internal fun pocketPlaybackCandidates(file: MediaFile, live: Boolean,
    cached: (String) -> File?, download: (String, MediaRepresentationRole) -> MonitorPlaybackCandidate): List<MonitorPlaybackCandidate> {
    val choices = ArrayList<MonitorPlaybackCandidate>()
    fun local(path: String, value: File, role: MediaRepresentationRole) {
        choices += MonitorPlaybackCandidate.Cached(MonitorPlaybackItem(value.toURI(),
            MediaHTTP.playbackMIMEType(path), path, role))
    }
    for (path in MediaHTTP.proxyPaths(file)) {
        val value = cached(path)
        if (value != null) { local(path, value, MediaRepresentationRole.PROXY); break }
    }
    if (live) MediaHTTP.proxyPaths(file).forEach { choices += download(it, MediaRepresentationRole.PROXY) }
    cached(file.path)?.let { local(file.path, it, MediaRepresentationRole.ORIGINAL) }
    if (live) choices += download(file.path, MediaRepresentationRole.ORIGINAL)
    return choices
}

/** No SDK/actor/plain mutable host fields: safe at final native render/publication admission. */
internal fun capturePocketPlaybackAdmission(library: MonitorMediaLibraryModel<MediaFile>,
    directory: MonitorMediaCacheDirectory, record: MonitorMediaRecord<MediaFile>): MonitorPlaybackAdmission {
    val lifetime = library.state.value.lifetimeToken
    val generation = directory.generation
    return MonitorPlaybackAdmission {
        val current = library.state.value
        current.browsing && current.lifetimeToken == lifetime && directory.generation == generation &&
            current.records.any { it.asset.id == record.asset.id }
    }
}

/** Completion policy for the exact outgoing presentation; an admitted removal may close it once. */
internal fun mayAdvancePocketPlaybackAfterRemoval(
    removed: com.opencapture.opencine.media.MediaAssetID?, captured: com.opencapture.opencine.media.MediaAssetID,
    token: com.opencapture.opencine.media.MonitorPlaybackItemToken,
    current: com.opencapture.opencine.appkit.MonitorMediaPlaybackState<MediaFile, PocketPlaybackLook>,
    sameComposition: Boolean, sameGallery: Boolean, sameContent: Boolean,
): Boolean = MonitorPlaybackRemovalAdmission.accepts(removed, captured, token, current.token,
    current.active?.asset?.id, current.closed, sameComposition, sameGallery, sameContent)
