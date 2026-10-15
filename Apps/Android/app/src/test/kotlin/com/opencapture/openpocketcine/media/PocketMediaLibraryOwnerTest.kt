package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.dji.DjiAndroidMediaAssets
import com.opencapture.opencine.dji.MediaManifest
import com.opencapture.opencine.media.*
import java.nio.file.Files
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import kotlin.test.*
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile

/** SIMULATED owner/IO fixtures. Original wire and manifest golden suites remain byte unchanged. */
@OptIn(ExperimentalCoroutinesApi::class)
class PocketMediaLibraryOwnerTest {
    private fun file(size: Long = 4) = MediaFile(
        path = "DCIM/DJI_001/DJI_20261004120000_0001_D.MP4",
        thumbPath = "MISC/THM/DJI_001/a.scr", handle = 0x40100040L,
        sizeBytes = size, storage = 1, storageKnown = true, resolution = "3840x2160", fps = 25)
    private fun codec(nano: Boolean = false) = PocketMediaLibraryCodec({ null }, { nano }, { -1 })
    private fun TestScope.owner(files: List<MediaFile>, colors: Map<String, Int> = emptyMap(),
        directory: MonitorMediaCacheDirectory = MonitorMediaCacheDirectory(Files.createTempDirectory("pocket-library-owner-").toFile())): MonitorMediaLibraryModel<MediaFile> {
        val codec = codec()
        val cache = MonitorMediaCache(directory, codec, MonitorMediaOriginalEligibility.ExactSize,
            "index.json", listOf("index.json", "color.json"), persistEmptyCatalog = false)
        val favorites = object : MonitorMediaFavoritesStore {
            override fun favorites() = emptySet<String>()
            override fun saveFavorites(keys: Set<String>) {}
        }
        return MonitorMediaLibraryModel(cache, favorites, scope = backgroundScope,
            cacheScanning = MonitorMediaCacheScanning.IMMEDIATE, initialCatalog = MediaCatalog(),
            initialRecords = files.map { codec.record(it, capturedColor = colors[it.path] ?: -1) }, catalogBase = MonitorMediaCatalogBase.FRESH_LISTING)
    }

    @Test fun codecKeepsCanonicalSchemaAddressesAndProxyOrder() {
        val files = listOf(file(), file().copy(path = "DCIM/unknown.ext", proxyPath = null, isStarred = true))
        val codec = codec()
        val records = files.map { codec.record(it) }
        assertContentEquals(encodePocketMediaCatalog(files), codec.encode(records))
        assertEquals(files, codec.decode(codec.encode(records)).map { it.payload })
        val record = records.first()
        assertEquals("thumbs/" + MediaCache.cacheName(files.first().thumbPath) + ".jpg", record.address.thumbnail)
        val original = record.asset.representations.first { it.role == MediaRepresentationRole.ORIGINAL }
        assertEquals("files/" + MediaCache.cacheName(files.first().path), record.address.representations[original.id])
        val proxy = record.asset.representations.first { it.role == MediaRepresentationRole.PROXY }
        val actual = listOfNotNull(record.address.representations[proxy.id]) + record.address.readAlternatives[proxy.id].orEmpty()
        assertEquals(MediaHTTP.proxyPaths(files.first()).map { "play/" + MediaHTTP.playbackCacheFileName(it) }, actual)
    }

    @Test fun cachedNanoRowsKeepLegacyPreferenceOverlayAuthorityAndUnknownKind() {
        val cached = codec(nano = true).record(file().copy(path = "DCIM/unknown.ext"))
        assertEquals(MonitorMediaFavoriteAuthority.LEGACY_COMBINED, cached.favoriteAuthority)
        assertNull(cached.asset.kind)
        assertEquals(MediaAssetKind.VIDEO, cached.facts.presentationKind)
    }

    @Test fun settingsClearKeepsClipListAndRejectsPendingCanonicalCommit() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val parent = Files.createTempDirectory("pocket-library-settings-").toFile()
        val root = MonitorMediaCacheRoot(parent)
        val directory = root.directory("camera")
        directory.write("index".toByteArray(), "index.json")
        directory.write("old color".toByteArray(), "color.json")
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val model = owner(emptyList(), directory = directory)
        val operation = PocketMediaOperation(model, model.captureIO(MonitorMediaLibraryIOKey("a"), null) { true })
        val temporaryRoot = Files.createTempDirectory("pocket-http-stage-").toFile()
        val pending = async {
            runCatching {
                operation.download("files/a", temporaryRoot, dispatcher) { staged ->
                    staged.writeText("outgoing")
                    started.complete(Unit)
                    release.await()
                }
            }
        }
        started.await()
        model.clearCache()
        assertEquals("index", directory.file("index.json").readText())
        assertEquals("old color", directory.file("color.json").readText())
        release.complete(Unit)
        assertTrue(pending.await().isFailure)
        assertFalse(directory.file("files/a").exists())
        assertTrue(temporaryRoot.listFiles().orEmpty().isEmpty())
    }

    @Test fun newerDestinationLeaseSurvivesOutgoingDownloadCompletion() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val directory = MonitorMediaCacheDirectory(Files.createTempDirectory("pocket-library-download-").toFile())
        val temporaryRoot = Files.createTempDirectory("pocket-http-stage-").toFile()
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val model = owner(emptyList(), directory = directory)
        val outgoing = PocketMediaOperation(model, model.captureIO(MonitorMediaLibraryIOKey("a"), null) { true })
        val old = async {
            runCatching { outgoing.download("files/a", temporaryRoot, dispatcher) { staged ->
                staged.writeText("old"); started.complete(Unit); release.await()
            } }
        }
        started.await()
        val successor = PocketMediaOperation(model, model.captureIO(MonitorMediaLibraryIOKey("a"), null) { true })
        successor.download("files/a", temporaryRoot, dispatcher) { it.writeText("new") }
        release.complete(Unit)
        assertTrue(old.await().isFailure)
        assertEquals("new", directory.file("files/a").readText())
        assertTrue(temporaryRoot.listFiles().orEmpty().isEmpty())
    }

    @Test fun staleContentCompletionCannotWriteEvenWhenCanonicalRootRemains() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val model = owner(listOf(file()))
        val captured = model.state.value.records.single()
        val token = model.actionToken
        val operation = PocketMediaOperation(model,
            model.captureIO(MonitorMediaLibraryIOKey(captured.payload.path), captured.asset.id) {
                model.isCurrent(token) && model.record(captured.asset.id) != null
            })
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val temporaryRoot = Files.createTempDirectory("pocket-http-stage-").toFile()
        val pending = async {
            runCatching { operation.download("files/a", temporaryRoot, dispatcher) { staged ->
                staged.writeText("old"); started.complete(Unit); release.await()
            } }
        }
        started.await()
        model.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = false,
            upserts = listOf(codec().record(file(8))), removed = listOf(captured.asset.id)), token)
        release.complete(Unit)
        assertTrue(pending.await().isFailure)
        assertFalse(model.cache.directory.file("files/a").exists())
        model.dispose()
    }

    @Test fun actualFavoritePreferenceKeysKeepExactSortedSeparatorBytes() {
        val preferences = PocketMediaTestPreferences()
        val parent = Files.createTempDirectory("pocket-library-prefs-").toFile()
        val cache = MediaCache(parent, preferences)
        val store = PocketMediaFavoritesStore(cache, "camera")
        store.saveFavorites(setOf("b", "a"))
        assertEquals("a\u001fb", preferences.getString("opc.media.fav.camera", null))
        assertEquals(setOf("a", "b"), store.favorites())
        cache.rememberCameraId("camera")
        assertEquals("camera", preferences.getString("opc.media.lastCameraID", null))
    }

    @Test fun actualWarmColorMapCannotRecreateMetadataAfterClear() = runTest {
        val parent = Files.createTempDirectory("pocket-library-color-").toFile()
        val root = MonitorMediaCacheRoot(parent)
        val cache = MediaCache(parent, PocketMediaTestPreferences(), root)
        val directory = root.directory("camera")
        cache.rememberShotColor("take", 65, "camera")
        assertEquals(65, cache.readShotColor("take", "camera"))
        val outgoingGeneration = directory.generation
        directory.clear(preserving = listOf("index.json"))
        assertEquals(-1, cache.readShotColor("take", "camera"))
        cache.rememberShotColor("take", 65, "camera", outgoingGeneration)
        assertFalse(directory.file("color.json").exists())
        cache.rememberShotColor("successor", 3, "camera", directory.generation)
        assertEquals(-1, cache.readShotColor("take", "camera"))
        assertEquals(3, cache.readShotColor("successor", "camera"))
    }

    @Test fun actualColorCompletionUpdatesLocalFactsWithoutInventingSourcePagesAndRejectsReplacement() = runTest {
        val item = file()
        val codec = codec()
        val model = owner(listOf(item))
        val rawCatalog = model.state.value.catalog
        val token = model.actionToken
        assertTrue(applyPocketMediaColor(model, codec, item, 65, token))
        assertEquals("65", model.state.value.records.single().facts.color)
        assertEquals(rawCatalog, model.state.value.catalog)
        assertEquals(0, model.state.value.catalogPageCount)
        val replacement = item.copy(sizeBytes = 8)
        model.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = false,
            upserts = listOf(codec.record(replacement)), removed = listOf(DjiAndroidMediaAssets.asset(item).id)), token)
        assertFalse(applyPocketMediaColor(model, codec, item, 3, token))
        assertNull(model.state.value.records.single().facts.color)
        model.dispose()
    }

    @Test fun actualCodecModelKeepsOriginalManifestCategoryFormatResolutionAndOrderGoldens() = runTest {
        val videos = listOf(
            MediaFile(path = "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4", thumbPath = "new.scr", resolution = "3840x2160"),
            MediaFile(path = "DCIM/DJI_001/DJI_20260404103742_0001_D.MP4", thumbPath = "old.scr", isStarred = true, resolution = "1920x1080"))
        val photo = MediaFile(path = "DCIM/DJI_001/DJI_20260801000000_0002_D.JPG", thumbPath = "photo.scr")
        val model = owner(videos + photo)
        model.visibility(MonitorMediaLibraryVisibility.ALL_RECORDS)
        model.filter(category = MonitorMediaCategoryFilter.VIDEOS); assertEquals(2, model.displayedRecords.size)
        model.filter(category = MonitorMediaCategoryFilter.PHOTOS); assertEquals(1, model.displayedRecords.size)
        model.filter(category = MonitorMediaCategoryFilter.FAVORITES); assertEquals(1, model.displayedRecords.size)
        model.filter(category = MonitorMediaCategoryFilter.ALL, formats = setOf("MP4")); assertEquals(2, model.displayedRecords.size)
        model.filter(formats = emptySet(), resolutions = setOf("3840x2160")); assertEquals(1, model.displayedRecords.size)
        model.resetFilters(); model.display(sort = MonitorMediaSort.OLDEST)
        assertEquals("DJI_20260404103742_0001_D.MP4", model.displayedRecords.first().payload.filename)
        model.filter(category = MonitorMediaCategoryFilter.VIDEOS); model.display(sort = MonitorMediaSort.NEWEST)
        assertEquals("DJI_20260814125250_0034_D.MP4", model.displayedRecords.first().payload.filename)
        model.dispose()
    }

    @Test fun actualCodecModelKeepsOriginalNanoDateAndCapturedColourGoldens() = runTest {
        val files = MediaManifest.decode(javaClass.classLoader!!.getResourceAsStream("nano-manifest.bin")!!.readBytes())
        val model = owner(files, mapOf(files[0].path to 0x41))
        model.visibility(MonitorMediaLibraryVisibility.ALL_RECORDS)
        assertEquals(34, model.state.value.records.size)
        assertEquals("DJI_20260814125250_0034_D.MP4", model.state.value.records.first().payload.filename)
        assertEquals("DJI_20260404103742_0001_D.MP4", model.state.value.records.last().payload.filename)
        model.filter(dateStart = "20260801")
        assertTrue(model.displayedRecords.all { it.payload.dateKey >= "20260801" })
        model.filter(dateStart = null, dateEnd = "20260430")
        assertTrue(model.displayedRecords.all { it.payload.dateKey <= "20260430" })
        model.filter(dateEnd = null, colors = setOf("65"))
        assertEquals(listOf(files[0].path), model.displayedRecords.map { it.payload.path })
        assertEquals(0, model.state.value.catalogPageCount); assertTrue(model.state.value.catalog.assets.isEmpty())
        model.dispose()
    }

    @Test fun actualCodecModelKeepsOriginalOfflineThumbnailOnlyExclusion() = runTest {
        val cached = MediaFile(path = "DCIM/DJI_001/CACHED.MP4", thumbPath = "MISC/THM/CACHED.scr")
        val thumb = MediaFile(path = "DCIM/DJI_001/THUMB_ONLY.MP4", thumbPath = "MISC/THM/THUMB_ONLY.scr")
        val model = owner(listOf(cached, thumb))
        val records = model.state.value.records
        val original = records[0].asset.representations.first { it.role == MediaRepresentationRole.ORIGINAL }
        model.cache.directory.write(byteArrayOf(1), records[0].address.representations.getValue(original.id))
        model.cache.directory.write(byteArrayOf(2), requireNotNull(records[1].address.thumbnail))
        model.refreshLocalCache(); model.visibility(MonitorMediaLibraryVisibility.CACHED_ONLY)
        assertEquals(listOf("CACHED.MP4"), model.displayedRecords.map { it.payload.filename })
        assertNotNull(model.state.value.entries[records[1].asset.id]?.thumbnail)
        assertTrue(model.state.value.catalog.assets.isEmpty())
        model.dispose()
    }
}
