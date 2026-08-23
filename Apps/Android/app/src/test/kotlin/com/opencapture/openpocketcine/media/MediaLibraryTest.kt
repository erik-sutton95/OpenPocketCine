package com.opencapture.openpocketcine.media

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MediaLibraryTest {
    private fun fixture(): ByteArray =
        javaClass.classLoader!!.getResourceAsStream("nano-manifest.bin")!!.readBytes()

    @Test
    fun portraitHeaderStacksTheItemCountUnderTheTitle() {
        assertTrue(MediaLibraryHeaderMetrics.stacksCountUnderTitle(portrait = true))
        assertFalse(MediaLibraryHeaderMetrics.stacksCountUnderTitle(portrait = false))
    }

    @Test
    fun thumbnailGridMatchesOpenZCineMinima() {
        assertEquals(148, MediaThumbnailSize.SMALL.gridMinimumDp)
        assertEquals(210, MediaThumbnailSize.MEDIUM.gridMinimumDp)
        assertEquals(280, MediaThumbnailSize.LARGE.gridMinimumDp)
        assertEquals(200, MediaThumbnailSize.SMALL.gridMaximumDp)
        assertEquals(300, MediaThumbnailSize.MEDIUM.gridMaximumDp)
        assertEquals(380, MediaThumbnailSize.LARGE.gridMaximumDp)
    }

    @Test
    fun emptyCopyDoesNotNameSisterApps() {
        val copy =
            listOf(
                MediaLibraryCopy.FILTER_EMPTY,
                MediaLibraryCopy.EMPTY_ALL,
                MediaLibraryCopy.EMPTY_FAVORITES,
                MediaLibraryCopy.EMPTY_VIDEOS,
                MediaLibraryCopy.EMPTY_PHOTOS,
                MediaLibraryCopy.DISCONNECTED,
                MediaLibraryCopy.DISCONNECTED_EMPTY_CACHE,
                MediaOperatorCopy.CLIP_NOT_CACHED,
            )
        for (text in copy) {
            assertFalse(text.contains("OpenZCine", ignoreCase = true))
            assertFalse(text.contains("Nikon", ignoreCase = true))
            assertFalse(text.contains("protocol is not", ignoreCase = true))
        }
    }

    @Test
    fun decodesNanoManifestCountAndNames() {
        val files = MediaManifest.decode(fixture())
        assertEquals(34, files.size)
        assertEquals(34, MediaManifest.headerCount(fixture()))
        assertEquals("DJI_20260814125250_0034_D.MP4", files.first().filename)
        assertEquals("DJI_20260404103742_0001_D.MP4", files.last().filename)
        assertTrue(files.all { it.kind == MediaKind.VIDEO })
        assertTrue(files.all { it.filename.endsWith(".MP4") })
    }

    @Test
    fun pairsThumbsHandlesAndDuration() {
        val files = MediaManifest.decode(fixture())
        val first = files[0]
        assertEquals("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4", first.path)
        assertEquals("MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr", first.thumbPath)
        assertEquals(0x40100880L, first.handle)
        assertEquals(209, first.durationSeconds)
        assertEquals(25, first.fps)
        assertEquals("3840x2160", first.resolution)
        assertFalse(first.isStarred)
        assertTrue(first.sizeBytes > 0)

        val second = files[1]
        assertEquals("DJI_20260814122657_0033_D.MP4", second.filename)
        assertTrue(second.thumbPath.endsWith("DJI_20260814122657_0033_D.scr"))
        assertEquals(0x40100840L, second.handle)
        assertEquals(1551, second.durationSeconds)
    }

    @Test
    fun handleFitIsNanoGeometry() {
        val files = MediaManifest.decode(fixture())
        val withCmd = files.filter { it.cmdHandle != 0L }
        assertEquals(34, withCmd.size)
        assertEquals(0x40100880L, files[0].cmdHandle)
        assertEquals(files[0].handle, files[0].cmdHandle)
        val steps = files.zipWithNext { a, b -> wrappingSub32(a.handle, b.handle) }
        assertTrue(steps.all { it == 0x40L })
    }

    @Test
    fun httpPathsUseStorageAndScr() {
        val files = MediaManifest.decode(fixture())
        val file = files[0]
        val storage = MediaHTTP.storageGuess(file.handle, singleSdStorage = false)
        assertEquals(1, storage)
        val thumb = MediaHTTP.pathUrlString(storage, file.thumbPath)
        assertEquals(
            "http://192.168.2.1/v2?storage=1&path=MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            thumb,
        )
        val original = MediaHTTP.pathUrlString(storage, file.path)
        assertTrue(original.contains("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4"))
        assertTrue(MediaHTTP.previewPaths(file).any { it.endsWith(".LRF") })
        val play = MediaHTTP.playbackCandidates(file, firstStorage = 1)
        assertEquals(listOf(1, 0, 1, 0), play.map { it.first })
        assertTrue(play.all { it.second.endsWith(".LRF") || it.second.endsWith(".MP4") })
        assertTrue(play.first().second.endsWith(".LRF"))
        assertTrue(play.last().second.endsWith(".MP4"))
        assertTrue(MediaHTTP.isProxyPath(play[0].second))
        assertFalse(MediaHTTP.isProxyPath(file.path))
        assertEquals(file.path, MediaHTTP.deliveryPath(file))
        assertFalse(MediaHTTP.isProxyPath(MediaHTTP.deliveryPath(file)))
        assertTrue(MediaHTTP.previewPaths(file).first() != MediaHTTP.deliveryPath(file))
        assertTrue(MediaHTTP.proxyPaths(file).all { MediaHTTP.isProxyPath(it) })
        assertTrue(MediaHTTP.proxyPaths(file).none { it == file.path })
        assertTrue(MediaHTTP.proxyPaths(file).isNotEmpty())
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(play[0].second))
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(file.path))
        assertTrue(MediaHTTP.playbackCacheFileName(play[0].second).endsWith(".mp4"))
        assertTrue(MediaHTTP.playbackCacheFileName(file.path).endsWith(".MP4"))
        assertTrue(MediaHTTP.pathUrl(storage, file.thumbPath).encodedPath == "/v2")
    }

    @Test
    fun listPayloadMatchesOsmosis() {
        val newest = MediaListCommand.listPayload(counter = 1, cursor = 1)
        assertEquals(1, newest[4].toInt() and 0xFF)
        assertEquals(listOf(0x01, 0x00, 0x00, 0x00), newest.slice(10..13).map { it.toInt() and 0xFF })
        assertEquals(0x2D, newest[14].toInt() and 0xFF)
        val onboard = MediaListCommand.listPayload(counter = 2, cursor = MediaListCommand.NEWEST_INTERNAL)
        assertEquals(2, onboard[4].toInt() and 0xFF)
        assertEquals(listOf(0x01, 0x00, 0x00, 0x40), onboard.slice(10..13).map { it.toInt() and 0xFF })
        assertEquals(
            listOf(0x01, 0x01, 0x00, 0x00),
            MediaCommands.exitPlaybackPayload().map { it.toInt() and 0xFF },
        )
        assertEquals(
            listOf(0x01, 0x01, 0x00, 0x01),
            MediaCommands.enterPlaybackPayload().map { it.toInt() and 0xFF },
        )
    }

    @Test
    fun deleteAndFavoritePayloadsMatchCapture() {
        val del = MediaCommands.deletePayload(handle = 0x40104480L, counter = 1)
        assertEquals(
            listOf(
                0x01,
                0x80, 0x44, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00,
                0x01, 0x00, 0x00, 0x00,
                0x01, 0x01, 0x00, 0x00,
            ),
            del.map { it.toInt() and 0xFF },
        )
        val fav = MediaCommands.favoritePayload(handle = 0x40104040L, on = true, counter = 1)
        assertEquals(
            listOf(
                0x01, 0x01,
                0x40, 0x40, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00, 0x01, 0x00, 0x00, 0x00,
            ),
            fav.map { it.toInt() and 0xFF },
        )
    }

    @Test
    fun chunkAssemblerStripsSubheader() {
        val assembler = MediaChunkAssembler()
        val payload =
            byteArrayOf(0x4A, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDE.toByte(), 0xAD.toByte())
        assertTrue(assembler.ingest(cmdSet = 0x00, cmdId = 0x27, payload = payload))
        assertEquals(listOf(0xDE, 0xAD), assembler.assembled(2).map { it.toInt() and 0xFF })
        val ended =
            assembler.ingest(
                cmdSet = 0x00,
                cmdId = 0x27,
                payload = byteArrayOf(0x4A, 0x03, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00),
            )
        assertTrue(ended)
        assertTrue(assembler.sawEnd)
    }

    @Test
    fun nextCursorUsesOldestVideoHandle() {
        val files = MediaManifest.decode(fixture())
        val handles = files.map { it.handle }
        val oldest = MediaListCommand.oldestVideoHandle(handles)
        assertEquals(handles.minOrNull(), oldest)
        assertFalse(MediaListCommand.hasOlderPage(recordCount = 34, cursor = oldest))
        assertTrue(MediaListCommand.hasOlderPage(recordCount = 45, cursor = oldest))
        val older = MediaListCommand.nextCursor(handles, files[0].handle)
        assertEquals(files.drop(1).minOf { it.handle }, older)
    }

    @Test
    fun queryFiltersAndSorts() {
        val files = MediaManifest.decode(fixture())
        val videos = MediaLibraryQuery.filtered(files, MediaLibraryTab.VIDEOS)
        assertEquals(34, videos.size)
        val photos = MediaLibraryQuery.filtered(files, MediaLibraryTab.PHOTOS)
        assertTrue(photos.isEmpty())
        val oldest = MediaLibraryQuery.sorted(files, MediaLibrarySort.OLDEST)
        assertTrue(oldest.first().filename.contains("20260404"))
        assertEquals("3:29", MediaClipFormatting.durationLabel(209))
    }

    @Test
    fun fiftyFpsClipOffersHalfSpeedConform() {
        val file =
            MediaFile(
                path = "DCIM/DJI_001/DJI_20260819000000_0050_D.MP4",
                thumbPath = "MISC/THM/DJI_001/DJI_20260819000000_0050_D.scr",
                resolution = "3840x2160",
                fps = 50,
            )
        val source = ConformPreview.probeLocal(listedRate = file.fps?.toDouble())
        val availability = ConformPreview.availability(source)
        assertEquals(50.0, source.captureRate)
        assertTrue(availability.targets.contains(25.0))
        assertEquals("25 fps · 50%", ConformPreview.targetLabel(50.0, 25.0))
        assertEquals(
            PlaybackVideoLayout.Size(3840f, 2160f),
            PlaybackVideoLayout.sizeFromResolution(file.resolution),
        )
    }

    @Test
    fun filterAndSortOfManifestFiles() {
        val videos =
            listOf(
                MediaFile(
                    path = "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
                    thumbPath = "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
                    handle = 0x40100880L,
                    durationSeconds = 209,
                    resolution = "3840x2160",
                ),
                MediaFile(
                    path = "DCIM/DJI_001/DJI_20260404103742_0001_D.MP4",
                    thumbPath = "MISC/THM/DJI_001/DJI_20260404103742_0001_D.scr",
                    handle = 0x40100040L,
                    durationSeconds = 12,
                    isStarred = true,
                    resolution = "1920x1080",
                ),
            )
        val photo =
            MediaFile(
                path = "DCIM/DJI_001/DJI_20260801000000_0002_D.JPG",
                thumbPath = "MISC/THM/DJI_001/DJI_20260801000000_0002_D.scr",
            )
        val all = videos + photo
        assertEquals(2, MediaLibraryQuery.filtered(all, MediaLibraryTab.VIDEOS).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.PHOTOS).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.FAVORITES).size)
        assertEquals(2, MediaLibraryQuery.filtered(all, MediaLibraryTab.ALL, formats = setOf("MP4")).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.ALL, resolutions = setOf("3840x2160")).size)
        val oldest = MediaLibraryQuery.sorted(all, MediaLibrarySort.OLDEST)
        assertEquals("DJI_20260404103742_0001_D.MP4", oldest.first().filename)
        val newest = MediaLibraryQuery.sorted(videos, MediaLibrarySort.NEWEST)
        assertEquals("DJI_20260814125250_0034_D.MP4", newest.first().filename)
        assertEquals("4K", MediaClipPresentation.resolutionLabel("3840x2160"))
        assertEquals("1080p", MediaClipPresentation.resolutionLabel("1920x1080"))
    }

    @Test
    fun offlineLibraryHidesThumbOnlyClips() {
        val cached =
            MediaFile(path = "DCIM/DJI_001/CACHED.MP4", thumbPath = "MISC/THM/CACHED.scr")
        val thumbOnly =
            MediaFile(path = "DCIM/DJI_001/THUMB_ONLY.MP4", thumbPath = "MISC/THM/THUMB_ONLY.scr")
        val shown = MediaLibraryQuery.cachedOnly(listOf(cached, thumbOnly), setOf(cached.path))
        assertEquals(listOf("CACHED.MP4"), shown.map { it.filename })
    }

    @Test
    fun starByteIsStrictlyOne() {
        val bytes = ByteArray(20)
        bytes[0] = 0xFF.toByte()
        bytes[1] = 0x19
        bytes[2] = 0x06
        bytes[9] = 44
        val files = MediaManifest.decode(bytes)
        assertTrue(files.isEmpty())
    }

    @Test
    fun liveResumeExitsUntilPlaybackClears() {
        assertEquals(
            MediaLiveResume.Action.EXIT_PLAYBACK,
            MediaLiveResume.action(attempt = 1, inPlayback = true, exitAcknowledged = false, pictureFresh = false),
        )
        assertEquals(
            MediaLiveResume.Action.ENABLE_LIVE_VIEW,
            MediaLiveResume.action(attempt = 2, inPlayback = false, exitAcknowledged = true, pictureFresh = false),
        )
        assertEquals(
            MediaLiveResume.Action.DONE,
            MediaLiveResume.action(attempt = 3, inPlayback = false, exitAcknowledged = true, pictureFresh = true),
        )
        assertEquals(
            MediaLiveResume.Action.EXIT_PLAYBACK,
            MediaLiveResume.strayPlaybackAction(browsing = false, inPlayback = true),
        )
        assertEquals(null, MediaLiveResume.strayPlaybackAction(browsing = true, inPlayback = true))
    }

    @Test
    fun sortCyclesNewestOldestNameRating() {
        assertEquals(MediaLibrarySort.OLDEST, MediaLibrarySort.NEWEST.next)
        assertEquals(MediaLibrarySort.NAME, MediaLibrarySort.OLDEST.next)
        assertEquals(MediaLibrarySort.RATING, MediaLibrarySort.NAME.next)
        assertEquals(MediaLibrarySort.NEWEST, MediaLibrarySort.RATING.next)
    }

    @Test
    fun downloadFinishesAtContentLengthWithoutWaitingForEof() {
        val body = ByteArray(100) { it.toByte() }
        val padded = body + ByteArray(40) { 0xFF.toByte() }
        val out = ByteArrayOutputStream()
        val written = MediaTransfer.readUntilLength(ByteArrayInputStream(padded), out, expected = 100) { }
        assertEquals(100L, written)
        assertEquals(100, out.size())
        assertEquals(body.toList(), out.toByteArray().toList())
    }

    @Test
    fun downloadedUsesNinetyPercentThreshold() {
        assertTrue(MediaCache.isCompleteDownload(100, 100))
        assertFalse(MediaCache.isCompleteDownload(90, 100))
        assertTrue(MediaCache.isCompleteDownload(1, 0))
        assertFalse(MediaCache.isCompleteDownload(0, 100))
    }
}
