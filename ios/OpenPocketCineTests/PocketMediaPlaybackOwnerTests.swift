import AVFoundation
import Foundation
import Observation
import OpenCineAppKit
import OpenCineApple
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

private final class PlaybackOwnerFileManager: FileManager, @unchecked Sendable {
  let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  override func urls(
    for directory: FileManager.SearchPathDirectory,
    in domainMask: FileManager.SearchPathDomainMask
  ) -> [URL] {
    directory == .applicationSupportDirectory
      ? [support] : super.urls(for: directory, in: domainMask)
  }
}

@MainActor private final class PlaybackPublicationReentry {
  var admitted = true
  var rejectedAfterPublication = false
  var observedFirstPicture = false
}

/// SIMULATED actual host/native wiring. Original HTTP, recovery and sample retirement goldens stay exact.
@MainActor final class PocketMediaPlaybackOwnerTests: XCTestCase {
  func testActualCachedProxyOrderAndOriginalFallbackKeepExactAddressesWithoutSourceFacts() throws {
    let manager = PlaybackOwnerFileManager()
    let media = CameraMedia(fileManager: manager)
    let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
    defer {
      session.disconnect()
      session.decoder.close()
      try? FileManager.default.removeItem(at: manager.support)
    }
    let file = MediaFile(path: "DCIM/DJI_001/DJI_PLAY.MP4", thumbPath: "PLAY.scr", sizeBytes: 4)
    let proxy = try XCTUnwrap(MediaHTTP.proxyPaths(file).first)
    let directory = media.cacheDirectory(cameraID: session.mediaCameraID)
    let codec = PocketMediaCatalogCodec(
      source: { nil }, sourceOwnsFavorites: { false }, shotColor: { _ in nil })
    let record = codec.record(file)
    try directory.write(try codec.encode([record]), at: "index.json")
    let originalURL = media.fileCacheURL(cameraID: session.mediaCameraID, file: file)
    let proxyURL = media.playbackCacheURL(
      cameraID: session.mediaCameraID, file: file, path: proxy)
    try FileManager.default.createDirectory(
      at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: proxyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([1, 2, 3, 4]).write(to: originalURL)
    try Data([7, 8]).write(to: proxyURL)
    let actual = try XCTUnwrap(session.mediaPlaybackRecord(for: file))
    let choices = session.playbackCandidates(actual)
    guard case .cached(let first) = try XCTUnwrap(choices.first) else {
      return XCTFail("Expected the cached monitor proxy first")
    }
    XCTAssertEqual(first.url, proxyURL)
    XCTAssertEqual(first.sourceKey, proxy)
    XCTAssertEqual(first.mimeType, MediaHTTP.playbackMIMEType(for: proxy))
    XCTAssertEqual(first.role, .proxy)
    try FileManager.default.removeItem(at: proxyURL)
    guard case .cached(let original) = try XCTUnwrap(session.playbackCandidates(actual).first)
    else { return XCTFail("Expected original fallback") }
    XCTAssertEqual(original.url, originalURL)
    XCTAssertEqual(original.sourceKey, file.path)
    XCTAssertEqual(original.role, .original)
    XCTAssertNil(session.mediaLibrary.binding)
    XCTAssertTrue(session.mediaLibrary.catalog.assets.isEmpty)
  }

  func testActualContentReplacementRetiresCapturedLocalAuthorityWithoutParsingPageIdentity()
    throws
  {
    let manager = PlaybackOwnerFileManager()
    let media = CameraMedia(fileManager: manager)
    let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
    defer {
      session.disconnect()
      session.decoder.close()
      try? FileManager.default.removeItem(at: manager.support)
    }
    let file = MediaFile(
      path: "DCIM/DJI_001/DJI_PLAY.MP4", thumbPath: "PLAY.scr", handle: 7, sizeBytes: 4)
    let codec = PocketMediaCatalogCodec(
      source: { nil }, sourceOwnsFavorites: { false }, shotColor: { _ in nil })
    let old = codec.record(file)
    try media.cacheDirectory(cameraID: session.mediaCameraID).write(
      try codec.encode([old]), at: "index.json")
    let library = session.mediaLibrary
    let authority = PocketPlaybackAuthority(session: session, file: file)
    XCTAssertTrue(authority.admission.isCurrent())
    var replaced = file
    replaced.sizeBytes = 5
    let next = codec.record(replaced)
    XCTAssertEqual(replaced.id, file.id)
    XCTAssertNotEqual(next.asset.id, old.asset.id)
    try library.applyLocalRecords(
      .init(resetLibrary: false, upserts: [next], removed: [old.asset.id]),
      token: library.actionToken)
    XCTAssertFalse(authority.admission.isCurrent())
    XCTAssertNil(library.binding)
    XCTAssertTrue(library.catalog.assets.isEmpty)
  }

  func testUnindexedHostAbsenceAndSameCameraRepairKeepLocalAuthoritySeparateFromWire()
    async throws
  {
    let manager = PlaybackOwnerFileManager()
    let media = CameraMedia(fileManager: manager)
    let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
    defer {
      session.disconnect()
      session.decoder.close()
      try? FileManager.default.removeItem(at: manager.support)
    }
    let file = MediaFile(path: "DCIM/DJI_001/DJI_UNINDEXED.MP4", thumbPath: "UNINDEXED.scr")
    let authority = PocketPlaybackAuthority(session: session, file: file)
    XCTAssertTrue(authority.admission.isCurrent())
    XCTAssertTrue(authority.operation.isCurrent)
    XCTAssertNil(session.mediaPlaybackRecord(for: file))
    XCTAssertTrue(session.mediaLibrary.records.isEmpty)
    session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
    session.phase = .live
    XCTAssertTrue(
      authority.admission.isCurrent(),
      "Cached presentation belongs to the unchanged gallery/content")
    XCTAssertFalse(
      authority.operation.isCurrent, "An old IO request cannot acquire the repaired driver")
    try await authority.operation.directory.clear(preserving: ["index.json"])
    XCTAssertFalse(authority.admission.isCurrent())
    XCTAssertTrue(session.mediaLibrary.catalog.assets.isEmpty)
    XCTAssertNil(session.mediaLibrary.binding)
  }

  func testActualNativeAdmissionRetiresQueuedClipAndCannotEraseSuccessorSamples() async throws {
    let manager = PlaybackOwnerFileManager()
    let media = CameraMedia(fileManager: manager)
    let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
    let fixture = try await PlaybackOutputFixture.make(in: self)
    let file = MediaFile(path: "DCIM/DJI_001/DJI_NATIVE.MP4", thumbPath: "NATIVE.scr")
    let codec = PocketMediaCatalogCodec(
      source: { nil }, sourceOwnsFavorites: { false }, shotColor: { _ in nil })
    let directory = media.cacheDirectory(cameraID: session.mediaCameraID)
    try directory.write(try codec.encode([codec.record(file)]), at: "index.json")
    let original = media.fileCacheURL(cameraID: session.mediaCameraID, file: file)
    try FileManager.default.createDirectory(
      at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
    let source = try XCTUnwrap(fixture.item.asset as? AVURLAsset).url
    try FileManager.default.copyItem(at: source, to: original)
    session.mediaLibrary.begin()
    let samples = LiveFrameSampleBus()
    let feed = PlaybackFeedSession()
    feed.setEffects(
      MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
      sampleBus: samples)
    let native = MonitorApplePlaybackOwner(feed: feed)
    let owner = session.makeMediaPlayback(native: native, previousColor: { nil })
    defer {
      owner.close()
      fixture.close()
      session.disconnect()
      session.decoder.close()
      try? FileManager.default.removeItem(at: manager.support)
    }
    XCTAssertNotNil(native.sourceAdmission)
    XCTAssertNotNil(feed.sourceAdmission)
    let installed = expectation(description: "actual native clip is installed")
    native.onItemChanged = { item in if item != nil { installed.fulfill() } }
    let record = try XCTUnwrap(session.mediaPlaybackRecord(for: file))
    owner.load(record, playlist: [record])
    await fulfillment(of: [installed], timeout: 3)
    let old = owner.token
    let oldCallback = native.onEvent
    try await directory.clear(preserving: ["index.json"])
    XCTAssertNil(
      feed.backdropSource(),
      "Final native publication checks the captured root before borrowing a frame")
    XCTAssertTrue(owner.closed)
    XCTAssertNil(native.player.currentItem)
    let retiredPosition = owner.position
    oldCallback?(old, .position(90))
    oldCallback?(old, .playing(true))
    XCTAssertFalse(owner.ready)
    XCTAssertEqual(owner.position, retiredPosition)
    let successor = PlaybackFeedSession()
    defer { successor.shutdown() }
    successor.setEffects(
      MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
      sampleBus: samples)
    fixture.prepare(successor)
    try await fixture.publishScopes(using: successor, samples: samples, in: self)
    let successorBuffer = try XCTUnwrap(samples.playbackSourcePixelBuffer)
    native.play(rate: 1, token: old)
    feed.noteItemReady()
    feed.shutdown()
    XCTAssertTrue(samples.playbackSourcePixelBuffer === successorBuffer)
    XCTAssertTrue(fixture.item.outputs.contains(where: { $0 === successor.output }))
  }

  func testSynchronousSampleObserverCannotPresentOutgoingResultIntoReplacedItem() async throws {
    let outgoing = try await PlaybackOutputFixture.make(in: self, code: 80)
    let incoming = try await PlaybackOutputFixture.make(in: self, code: 180)
    let samples = LiveFrameSampleBus()
    let feed = PlaybackFeedSession()
    defer {
      feed.shutdown()
      outgoing.close()
      incoming.close()
    }
    feed.setEffects(
      MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
      sampleBus: samples)
    outgoing.prepare(feed)
    let replaced = expectation(description: "sample observer replaces the actual native item")
    let reentry = PlaybackPublicationReentry()
    XCTAssertNil(samples.playbackSourcePixelBuffer)
    XCTAssertFalse(feed.debugItemHasPresented)
    // Scope bundles arrive after the separate image completion. Observe the actual
    // first retained picture at the existing post-publication admission callback.
    feed.sourceAdmission = {
      if !reentry.observedFirstPicture, samples.playbackSourcePixelBuffer != nil {
        XCTAssertFalse(feed.debugItemHasPresented)
        reentry.observedFirstPicture = true
        feed.prepare(incoming.item)
        outgoing.player.replaceCurrentItem(with: incoming.item)
        feed.attach(host: outgoing.host, player: outgoing.player)
        reentry.admitted = false
        replaced.fulfill()
      }
      if !reentry.admitted { reentry.rejectedAfterPublication = true }
      return reentry.admitted
    }
    try await NativePlaybackBoundaryStart(fixture: outgoing).start(using: feed, in: self)
    await fulfillment(of: [replaced], timeout: 2)
    outgoing.player.pause()
    XCTAssertTrue(reentry.observedFirstPicture)
    XCTAssertTrue(reentry.rejectedAfterPublication)
    XCTAssertFalse(feed.debugItemHasPresented)
    XCTAssertTrue(incoming.item.outputs.contains(where: { $0 === feed.output }))
    // The outgoing guard must reject its result without closing the newly installed item.
    // Keep this owner's player while moving its admitted item to the successor host.
    reentry.admitted = true
    incoming.host.attachGeneration = feed.reserveHostGeneration()
    feed.prepare(incoming.item)
    feed.attach(host: incoming.host, player: outgoing.player)
    try await NativeSinglePlayerScopePublication(item: incoming.item, player: outgoing.player)
      .publish(using: feed, samples: samples, in: self)
    XCTAssertTrue(feed.debugBoundHost === incoming.host)
    XCTAssertNotNil(samples.playbackSourcePixelBuffer)
  }

  func testSynchronousSampleObserverRevokesContentBeforeOutgoingPresentationOnSameLease()
    async throws
  {
    let fixture = try await PlaybackOutputFixture.make(in: self)
    let samples = LiveFrameSampleBus()
    let feed = PlaybackFeedSession()
    let reentry = PlaybackPublicationReentry()
    defer {
      feed.shutdown()
      fixture.close()
    }
    feed.setEffects(
      MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
      sampleBus: samples)
    fixture.prepare(feed)
    XCTAssertNil(samples.playbackSourcePixelBuffer)
    XCTAssertFalse(feed.debugItemHasPresented)
    let revoked = expectation(description: "same source first picture admission revokes captured content")
    feed.sourceAdmission = {
      if !reentry.observedFirstPicture, samples.playbackSourcePixelBuffer != nil {
        XCTAssertFalse(feed.debugItemHasPresented)
        // Keep the actual bus lease and item; reject the first picture before it presents.
        reentry.observedFirstPicture = true
        reentry.admitted = false
        revoked.fulfill()
      }
      return reentry.admitted
    }
    try await NativePlaybackBoundaryStart(fixture: fixture).start(using: feed, in: self)
    await fulfillment(of: [revoked], timeout: 2)
    fixture.player.pause()
    XCTAssertTrue(reentry.observedFirstPicture)
    XCTAssertNotNil(samples.playbackSourcePixelBuffer)
    XCTAssertFalse(feed.debugItemHasPresented)
    XCTAssertTrue(feed.debugBoundHost === fixture.host)
    XCTAssertTrue(fixture.item.outputs.contains(where: { $0 === feed.output }))
    // Rejection must leave this owner's output usable; no unrelated successor is retired.
    reentry.admitted = true
    feed.prepare(fixture.item)
    feed.attach(host: fixture.host, player: fixture.player)
    try await fixture.publishScopes(using: feed, samples: samples, in: self)
    XCTAssertNotNil(samples.playbackSourcePixelBuffer)
  }

}

/// SIMULATED: start the same encoded AVPlayer fixture, then let each test wait for
/// its actual native publication/admission event. No synthetic buffer is submitted.
@MainActor private final class NativePlaybackBoundaryStart {
  private let fixture: PlaybackOutputFixture
  private var readiness: XCTestExpectation?
  private var observation: NSKeyValueObservation?

  init(fixture: PlaybackOutputFixture) { self.fixture = fixture }

  func start(using session: PlaybackFeedSession, in test: XCTestCase) async throws {
    XCTAssertTrue(fixture.item.outputs.contains(where: { $0 === session.output }))
    let ready = test.expectation(description: "actual encoded clip becomes ready")
    readiness = ready
    observation = fixture.item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor in
        guard let self, self.fixture.item.status != .unknown, let readiness = self.readiness else {
          return
        }
        self.readiness = nil
        readiness.fulfill()
      }
    }
    defer {
      observation?.invalidate()
      observation = nil
      readiness = nil
    }
    await test.fulfillment(of: [ready], timeout: 3)
    guard fixture.item.status == .readyToPlay else {
      throw fixture.item.error ?? NativePlaybackBoundaryError.itemNotReady
    }
    session.noteItemReady()
    fixture.player.play()
  }
}

private enum NativePlaybackBoundaryError: Error { case itemNotReady }

/// SIMULATED: mirror the original encoded-item readiness and actual scope-publication
/// fixture, with the product's existing player retained across an item/host change.
@MainActor private final class NativeSinglePlayerScopePublication {
  private let item: AVPlayerItem
  private let player: AVPlayer
  private var readiness: XCTestExpectation?
  private var readinessObservation: NSKeyValueObservation?

  init(item: AVPlayerItem, player: AVPlayer) {
    self.item = item
    self.player = player
  }

  func publish(
    using session: PlaybackFeedSession, samples: LiveFrameSampleBus, in test: XCTestCase
  ) async throws {
    let ready = test.expectation(description: "actual encoded clip becomes ready")
    readiness = ready
    readinessObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor in
        guard let self, self.item.status != .unknown, let readiness = self.readiness else {
          return
        }
        self.readiness = nil
        readiness.fulfill()
      }
    }
    await test.fulfillment(of: [ready], timeout: 3)
    readinessObservation?.invalidate()
    readinessObservation = nil
    readiness = nil
    guard item.status == .readyToPlay else {
      throw item.error ?? NativePlaybackBoundaryError.itemNotReady
    }
    XCTAssertTrue(item.outputs.contains(where: { $0 === session.output }))

    let delivered = test.expectation(description: "actual playback output publishes a scope bundle")
    let waiter = NativeSinglePlayerPublicationWait(samples: samples, delivered: delivered)
    waiter.arm()
    session.noteItemReady()
    player.play()
    await test.fulfillment(of: [delivered], timeout: 2)
    waiter.stop()
    player.pause()
  }
}

@MainActor private final class NativeSinglePlayerPublicationWait {
  private let samples: LiveFrameSampleBus
  private let delivered: XCTestExpectation
  private var active = true

  init(samples: LiveFrameSampleBus, delivered: XCTestExpectation) {
    self.samples = samples
    self.delivered = delivered
  }

  func arm() {
    guard active else { return }
    if samples.playbackBundle != nil {
      active = false
      delivered.fulfill()
      return
    }
    withObservationTracking {
      _ = samples.playbackBundle
    } onChange: { [weak self] in
      // Observation fires before storage; resample actual publication after that callback.
      Task { @MainActor in self?.arm() }
    }
  }

  func stop() { active = false }
}
