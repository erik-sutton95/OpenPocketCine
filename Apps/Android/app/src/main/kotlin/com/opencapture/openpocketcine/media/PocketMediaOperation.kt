package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.*
import com.opencapture.opencine.vocabulary.MediaFile
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Only the actual Pocket source adapter captures admission; the existing library owns IO. */
internal class PocketMediaOperation(
    val library: MonitorMediaLibraryModel<MediaFile>,
    val authority: MonitorMediaLibraryIOAuthority,
) {
    val id get() = authority.id
    val directory get() = authority.directory
    val generation get() = authority.generation
    fun isCurrent(): Boolean = authority.isCurrent
    fun requireCurrent() { authority.requireCurrent() }

    /** Compatibility for native staging fixtures; copying/commit stay in the same real library. */
    suspend fun download(address: String, temporaryRoot: File,
        ownerDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate, fetch: suspend (File) -> Unit): File =
        withContext(ownerDispatcher) {
            library.cacheHostStagedFile(authority, MonitorMediaLibraryIOPurpose.PLAYBACK, address,
                stagingAt = File(temporaryRoot, "$id.incoming"), staging = fetch)
                ?: throw MediaServiceException(MediaServiceFailure.UNAVAILABLE)
        }
}

/** The donor's one delete command and 400ms optimistic removal, under captured actual authority. */
internal suspend fun deletePocketCapturedContent(asset: com.opencapture.opencine.media.MediaAssetID,
    admitted: () -> Boolean, send: () -> Unit, remove: () -> Boolean,
    wait: suspend () -> Unit = { kotlinx.coroutines.delay(400) }): com.opencapture.opencine.media.MediaAssetID? {
    if (!admitted()) return null
    send()
    wait()
    if (!admitted()) return null
    return asset.takeIf { remove() }
}
