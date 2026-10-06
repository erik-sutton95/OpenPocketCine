package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.dji.DJIMediaCatalogRecordSource
import com.opencapture.opencine.dji.DjiAndroidMediaAssets
import com.opencapture.opencine.media.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.opencapture.opencine.vocabulary.MediaKind
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile

/** Pure canonical JSON plus captured source records. No listing/command loop or shadow index. */
internal class PocketMediaLibraryCodec(
    private val source: () -> DJIMediaCatalogRecordSource?,
    private val sourceOwnsFavorites: () -> Boolean,
    private val color: (MediaFile) -> Int,
) : MonitorMediaCatalogCodec<MediaFile> {
    override fun decode(bytes: ByteArray): List<MonitorMediaRecord<MediaFile>> =
        decodePocketMediaCatalog(bytes).map { record(it) }

    override fun encode(records: List<MonitorMediaRecord<MediaFile>>): ByteArray =
        encodePocketMediaCatalog(records.map { it.payload.copy(isStarred = it.favorite) })

    override fun capture(asset: MediaAsset, binding: MediaBrowseBinding): MonitorMediaRecord<MediaFile> {
        val file = source()?.mediaCatalogRecord(asset.id, binding)?.file
            ?: throw MediaServiceException(MediaServiceFailure.RETIRED)
        val record = record(file, sourceAuthority = sourceOwnsFavorites())
        if (record.asset != asset) throw MediaServiceException(MediaServiceFailure.RETIRED)
        return record
    }

    override fun captureCatalog(delta: MediaCatalogDelta, binding: MediaBrowseBinding,
        existing: List<MonitorMediaRecord<MediaFile>>): MonitorMediaCatalogCapture<MediaFile> {
        // Entire actual payload and its immutable cache addresses are captured before async IO.
        val upserts = delta.upserts.map { capture(it, binding) }
        val sourceFavoriteKeys = if (sourceOwnsFavorites()) {
            val values = linkedMapOf<MediaAssetID, MonitorMediaRecord<MediaFile>>()
            if (!delta.reset) existing.filterNot { it.asset.id in delta.removed }.forEach { values[it.asset.id] = it }
            upserts.forEach { values[it.asset.id] = it }
            values.values.filter { it.payload.isStarred }.map { it.payload.path }.toSet()
        } else null
        return MonitorMediaCatalogCapture(delta.reset, upserts, delta.removed, sourceFavoriteKeys = sourceFavoriteKeys)
    }

    override suspend fun prepareCatalog(capture: MonitorMediaCatalogCapture<MediaFile>, binding: MediaBrowseBinding,
        existing: List<MonitorMediaRecord<MediaFile>>): MonitorMediaCatalogCapture<MediaFile> = withContext(Dispatchers.IO) {
        // Actual cache metadata/migration is host IO over already captured files. No source lookup.
        capture.copy(upserts = capture.upserts.map { it.copy(facts = facts(it.payload, color(it.payload))) })
    }

    fun record(file: MediaFile, capturedColor: Int = -1, sourceAuthority: Boolean = false): MonitorMediaRecord<MediaFile> {
        val asset = DjiAndroidMediaAssets.asset(file)
        val representations = linkedMapOf<MediaRepresentationID, String>()
        val alternatives = linkedMapOf<MediaRepresentationID, List<String>>()
        asset.representations.forEach { representation ->
            when (representation.role) {
                MediaRepresentationRole.ORIGINAL -> representations[representation.id] = "files/" + MediaCache.cacheName(file.path)
                MediaRepresentationRole.PROXY -> {
                    val paths = MediaHTTP.proxyPaths(file).map { "play/" + MediaHTTP.playbackCacheFileName(it) }
                    if (paths.isNotEmpty()) {
                        representations[representation.id] = paths.first()
                        alternatives[representation.id] = paths.drop(1)
                    }
                }
                else -> Unit
            }
        }
        return MonitorMediaRecord(asset, file,
            MonitorMediaCacheAddress("thumbs/" + MediaCache.cacheName(file.thumbPath) + ".jpg", representations,
                file.path, alternatives), favorite = file.isStarred, facts = facts(file, capturedColor),
            favoriteAuthority = if (sourceAuthority) MonitorMediaFavoriteAuthority.SOURCE else MonitorMediaFavoriteAuthority.LEGACY_COMBINED,
            sourceFavorite = file.isStarred)
    }

    private fun facts(file: MediaFile, capturedColor: Int) = MonitorMediaFilterFacts(
        format = file.fileExtension.takeIf { it.isNotEmpty() }, resolution = file.resolution,
        dateKey = file.dateKey.takeIf { it.isNotEmpty() }, orderKey = file.filenameTimestamp,
        color = capturedColor.takeIf { it >= 0 }?.toString(),
        presentationKind = if (file.kind == MediaKind.PHOTO) MediaAssetKind.PHOTO else MediaAssetKind.VIDEO)
}

/** One exact existing preference authority, shared owner invokes writes after admission. */
internal class PocketMediaFavoritesStore(private val cache: MediaCache, private val cameraID: String) : MonitorMediaFavoritesStore {
    override fun favorites(): Set<String> = cache.loadFavorites(cameraID)
    override fun saveFavorites(keys: Set<String>) { cache.persistFavorites(cameraID, keys) }
}
