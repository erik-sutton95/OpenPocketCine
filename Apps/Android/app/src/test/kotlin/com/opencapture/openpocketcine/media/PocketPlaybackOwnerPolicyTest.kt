package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.*
import java.nio.file.Files
import kotlinx.coroutines.test.*
import kotlinx.coroutines.async
import kotlin.test.*
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile

/** SIMULATED actual codec/source values. No camera/service/catalog is fabricated for playback. */
class PocketPlaybackOwnerPolicyTest {
    private fun file(size: Long = 4) = MediaFile(path = "DCIM/DJI_001/DJI_PLAY.MP4",
        thumbPath = "PLAY.scr", handle = 7, sizeBytes = size, storage = 1, storageKnown = true)
    private fun record(value: MediaFile) = PocketMediaLibraryCodec({ null }, { false }, { -1 }).record(value)

    @Test fun actualCachedProxyLiveProxiesAndOriginalUseOriginalMIMEOrderAndAddresses() {
        val item = file()
        val root = Files.createTempDirectory("pocket-player-policy-").toFile()
        try {
            val paths = MediaHTTP.proxyPaths(item)
            assertTrue(paths.isNotEmpty())
            val proxy = java.io.File(root, "play/" + MediaHTTP.playbackCacheFileName(paths.first()))
            val original = java.io.File(root, "files/" + MediaCache.cacheName(item.path))
            proxy.parentFile.mkdirs(); original.parentFile.mkdirs()
            proxy.writeBytes(byteArrayOf(1)); original.writeBytes(byteArrayOf(2, 3, 4, 5))
            val calls = mutableListOf<String>()
            val choices = pocketPlaybackCandidates(item, live = true,
                cached = { path -> if (path == paths.first()) proxy else if (path == item.path) original else null },
                download = { path, role ->
                    calls += path
                    MonitorPlaybackCandidate.HostDownload(path, MediaHTTP.playbackMIMEType(path), path, role,
                        MonitorPlaybackAdmission { true }, transfer = { error("Not executed in policy test") })
                })
            val first = assertIs<MonitorPlaybackCandidate.Cached>(choices.first()).item
            assertEquals(proxy.toURI(), first.url)
            assertEquals(paths.first(), first.sourceKey)
            assertEquals(MediaRepresentationRole.PROXY, first.role)
            assertEquals(paths + item.path, calls)
            assertEquals(paths, choices.filterIsInstance<MonitorPlaybackCandidate.HostDownload>().dropLast(1).map { it.sourceKey })
            val cachedOriginal = assertIs<MonitorPlaybackCandidate.Cached>(choices[paths.size + 1]).item
            assertEquals(original.toURI(), cachedOriginal.url)
            assertEquals(MediaRepresentationRole.ORIGINAL, cachedOriginal.role)
            assertEquals(MediaHTTP.playbackMIMEType(item.path), cachedOriginal.mimeType)
        } finally { root.deleteRecursively() }
    }

    @Test fun actualOfflineAbsenceDoesNotCreateDownloadOrSourceFacts() {
        val item = file()
        assertTrue(pocketPlaybackCandidates(item, live = false, cached = { null },
            download = { _, _ -> error("Offline source must not be manufactured") }).isEmpty())
    }

    @Test fun actualContentRootAndGalleryAuthorityRejectRecycledPageWithoutDriverFacts() = runTest {
        val root = Files.createTempDirectory("pocket-player-content-").toFile()
        val directory = MonitorMediaCacheDirectory(root)
        val codec = PocketMediaLibraryCodec({ null }, { false }, { -1 })
        val oldFile = file()
        val old = record(oldFile)
        val cache = MonitorMediaCache(directory, codec, MonitorMediaOriginalEligibility.ExactSize,
            "index.json", listOf("index.json"), persistEmptyCatalog = false)
        val favorites = object : MonitorMediaFavoritesStore {
            override fun favorites() = emptySet<String>()
            override fun saveFavorites(keys: Set<String>) {}
        }
        val library = MonitorMediaLibraryModel(cache, favorites, scope = backgroundScope,
            cacheScanning = MonitorMediaCacheScanning.IMMEDIATE, initialCatalog = MediaCatalog(), initialRecords = listOf(old))
        library.begin()
        try {
            val captured = capturePocketPlaybackAdmission(library, directory, old)
            assertTrue(captured.isCurrent())
            assertNull(library.binding)
            assertTrue(library.state.value.catalog.assets.isEmpty())
            library.display(sort = MonitorMediaSort.NAME)
            library.select(setOf(old.asset.id), true)
            assertTrue(captured.isCurrent(), "Local view/selection does not retire content")
            val nextFile = oldFile.copy(sizeBytes = 8)
            assertEquals(oldFile.id, nextFile.id)
            val next = record(nextFile)
            assertNotEquals(old.asset.id, next.asset.id)
            library.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = false,
                upserts = listOf(next), removed = listOf(old.asset.id)), library.actionToken)
            assertFalse(captured.isCurrent())
            val repaired = capturePocketPlaybackAdmission(library, directory, next)
            assertTrue(repaired.isCurrent())
            directory.clear(listOf("index.json"))
            assertFalse(repaired.isCurrent())
            assertNull(library.binding)
            assertTrue(library.state.value.catalog.assets.isEmpty())
            val afterClear = capturePocketPlaybackAdmission(library, directory, next)
            library.close()
            assertFalse(afterClear.isCurrent())
        } finally { library.dispose(); root.deleteRecursively() }
    }
    @Test fun actualDeleteContinuationAndPageClaimRejectReplacementAndNavigationButAcceptOwnRemoval() = runTest {
        for (change in listOf("replacement", "navigation", "ownRemoval")) {
            val root = Files.createTempDirectory("pocket-player-delete-").toFile()
            val directory = MonitorMediaCacheDirectory(root)
            val codec = PocketMediaLibraryCodec({ null }, { false }, { -1 })
            val first = record(file())
            val next = record(file().copy(path = "DCIM/DJI_001/DJI_NEXT.MP4", handle = 8))
            val cache = MonitorMediaCache(directory, codec, MonitorMediaOriginalEligibility.ExactSize, "index.json", listOf("index.json"))
            val favorites = object : MonitorMediaFavoritesStore {
                override fun favorites() = emptySet<String>()
                override fun saveFavorites(keys: Set<String>) {}
            }
            val library = MonitorMediaLibraryModel(cache, favorites, scope = backgroundScope,
                cacheScanning = MonitorMediaCacheScanning.IMMEDIATE, initialCatalog = MediaCatalog(), initialRecords = listOf(first, next))
            library.begin()
            val native = java.lang.reflect.Proxy.newProxyInstance(MonitorPlaybackPort::class.java.classLoader,
                arrayOf(MonitorPlaybackPort::class.java)) { _, _, _ -> null } as MonitorPlaybackPort
            val playback = MonitorMediaPlaybackModel<MediaFile, PocketPlaybackLook>(library, native,
                backgroundScope, candidates = { emptyList() })
            playback.setItemAdmission { row -> capturePocketPlaybackAdmission(library, directory, row) }
            playback.load(first, listOf(first, next))
            val page = playback.state.value.token
            val action = library.actionToken
            val captured = capturePocketPlaybackAdmission(library, directory, first)
            val entered = kotlinx.coroutines.CompletableDeferred<Unit>()
            val release = kotlinx.coroutines.CompletableDeferred<Unit>()
            var commands = 0
            try {
                val pending = async {
                    deletePocketCapturedContent(first.asset.id,
                        admitted = { captured.isCurrent() && library.isCurrent(action) },
                        send = { commands += 1 },
                        remove = { library.applyLocalRemoval(setOf(first.asset.id), action); true },
                        wait = { entered.complete(Unit); release.await() })
                }
                entered.await()
                when (change) {
                    "replacement" -> library.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = false,
                        upserts = listOf(record(file(8))), removed = listOf(first.asset.id)), action)
                    "navigation" -> {
                        playback.load(next, listOf(first, next))
                        playback.load(first, listOf(first, next))
                    }
                }
                release.complete(Unit)
                val removed = pending.await()
                runCurrent()
                assertEquals(1, commands, "Original one-command optimistic policy is unchanged")
                val mayAdvance = mayAdvancePocketPlaybackAfterRemoval(removed, first.asset.id, page,
                    playback.state.value, sameComposition = true, sameGallery = true, sameContent = true)
                if (change == "ownRemoval") {
                    assertEquals(first.asset.id, removed)
                    assertTrue(playback.state.value.closed)
                    assertTrue(mayAdvance, "Only its admitted removal can accept its one native-close revision")
                } else {
                    assertFalse(mayAdvance)
                    if (change == "replacement") {
                        assertNull(removed)
                        assertNotNull(library.record(record(file(8)).asset.id))
                    } else {
                        assertEquals(first.asset.id, removed)
                        assertTrue(playback.state.value.token.revision > page.revision + 1)
                    }
                }
            } finally { playback.close(); library.dispose(); root.deleteRecursively() }
        }
    }

}
