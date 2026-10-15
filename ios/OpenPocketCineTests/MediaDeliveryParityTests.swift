import Foundation
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI
import UIKit
import XCTest

@testable import OpenPocketCine

private final class DeliveryParityFileManager: FileManager, @unchecked Sendable {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        directory == .applicationSupportDirectory ? [support] : super.urls(for: directory, in: domainMask)
    }
}

/// SIMULATED cached files and disconnected sessions over the shipping delivery composition.
@MainActor final class MediaDeliveryParityTests: XCTestCase {
    /// A2-06: a cached still is shared as its original, never through the movie exporter.
    func testCachedPhotoSharesItsOriginalWithoutAMovieExport() async throws {
        let manager = DeliveryParityFileManager()
        let media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        let model = AppModel(session: session)
        defer {
            model.delivery.close()
            session.disconnect()
            session.decoder.close()
            try? FileManager.default.removeItem(at: manager.support)
        }
        let photo = MediaFile(path: "DCIM/DJI_001/SIMULATED_0001.JPG", thumbPath: "", sizeBytes: 4)
        let url = media.fileCacheURL(cameraID: session.mediaCameraID, file: photo)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        XCTAssertTrue(session.isDownloaded(photo))
        var configuration = MonitorClipDelivery.defaultConfiguration()
        configuration.bakeLUT = false
        let library = model.clipLibrary()
        let outcome = await model.delivery.run(
            records: [photo], destination: .nativeShare, action: .systemShare, admission: .init { true },
            source: .init(
                originals: library.originals, still: { library.localURL($0) },
                export: { _, _, _ in XCTFail("A still never reaches the movie exporter"); return nil },
                filename: \.filename, metadata: { _ in nil }),
            includeMetadata: false, remote: nil,
            internet: MonitorDeliveryInternetService<Int>?.none, lease: nil) { _ in }
        guard case .share(let urls, _, let lease) = outcome else {
            return XCTFail("A cached photo must reach the share sheet, got \(outcome)")
        }
        // The share sheet gets its own lease of the cached original, never the cache file.
        XCTAssertEqual(urls.map(\.lastPathComponent), [url.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data([0xFF, 0xD8, 0xFF, 0xD9]))
        model.delivery.exports.release(lease)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "The cached original stays")
    }

    /// A2-05: Frame.io from the camera network caches first; an uncached clip keeps the route.
    func testFrameioHopFromAnUncachedSelectionStaysOnTheCameraNetwork() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        let clip = MediaFile(path: "DCIM/DJI_001/SIMULATED_0002.MP4", thumbPath: "", sizeBytes: 1_000)
        let popup = model.deliveryPopup(files: [clip], preferred: .remoteUpload)
        defer { popup.model.close() }
        popup.model.hopToInternet()
        for _ in 0..<200 where popup.model.projectsError == nil && !model.internetHop.isActive {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.internetHop.isActive, "An uncached clip must not leave the camera network")
        XCTAssertNotNil(popup.model.projectsError)
    }

    /// A2-04: a delivery outcome is announced in the gallery and at the root.
    func testGalleryAnnouncesADeliveryOutcome() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        try await assertAnnounced(MediaLibraryView().environment(model), model: model)
    }

    func testRootAnnouncesADeliveryOutcomeWithoutAMediaSurface() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        try await assertAnnounced(LinkExperience().environment(model), model: model)
    }

    private func assertAnnounced(_ view: some View, model: AppModel) async throws {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        try XCTSkipIf(Self.labels(host.view).isEmpty, "No accessibility tree: enable app accessibility")
        model.delivery.fail("Export settings are unavailable.")
        var announced = false
        for _ in 0..<60 where !announced {
            try await Task.sleep(for: .milliseconds(50))
            host.view.layoutIfNeeded()
            announced = Self.labels(host.view).contains("Export settings are unavailable.")
        }
        XCTAssertTrue(announced, "The failed delivery's outcome must be visible")
    }

    private static func labels(_ object: NSObject, depth: Int = 0) -> [String] {
        guard depth < 64, !object.accessibilityElementsHidden else { return [] }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return [] }
        let own = object.accessibilityLabel.map { [$0] } ?? []
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            return own + elements.flatMap { labels($0, depth: depth + 1) }
        }
        return own + ((object as? UIView)?.subviews ?? []).flatMap { labels($0, depth: depth + 1) }
    }
}

/// One delivery owner (A2-16, A2-52, A2-55, A2-57, A2-61, A2-73, A2-74, A2-76): delivery, Frame.io,
/// export, the share sheet and the internet hop are the shared owners. The app keeps only its
/// session adapter, copy and namespaces, so no app copy of a retired type or hop step comes back.
final class DeliveryOwnershipRuleTests: XCTestCase {
    func testDeliveryHasNoAppCopyOfASharedOwner() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenPocketCine")
        // The rule reads the app's Swift sources by path. A device bundle carries no
        // source tree, so the enumeration is empty there; the full rule still runs on
        // every host that has the sources.
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sources.path),
            "The app's source tree does not exist inside a device bundle")
        let types = [
            "FrameioAuthCoordinator", "FrameioConfig", "FrameioTokenStore",
            "FrameioKeychainStorage", "FrameioClients", "FrameioProjectListing",
            "FrameioDestination", "FrameioMark", "FrameioMarkShape", "MediaDeliveryUploadOptions",
            "MediaExportFormat", "MediaDeliveryDestination", "MediaDeliveryChrome",
            "MediaDeliveryCopy", "MediaClipDeliveryMetadata", "MediaDeliveryPresentation",
            "MediaDeliveryError", "MediaDeliveryBeginRequest", "MediaDeliveryRunOutcome",
            "MediaPhotosSaver", "MediaShareStaging", "MediaDeliveryOverlayState",
            "MediaDeliveryCoordinator", "MediaSharePayload", "MediaDeliveryRunner",
            "MediaDeliveryPopup", "CapturedMediaDeliveryPopup", "MediaDeliveryPreparationSource",
            "MediaShareSheet", "MediaLUT",
        ]
        let steps = [
            "beginInternetHop", "transferInternetHop", "endInternetHop",
            "consumeInternetHopReturn", "waitForInternetPath", "canReachInternet",
        ]
        let pattern = try NSRegularExpression(
            pattern: "\\b(?:struct|enum|class|actor|typealias|protocol)\\s+(" + types.joined(separator: "|")
                + ")\\b|\\bfunc\\s+(" + steps.joined(separator: "|") + ")\\b")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" })
        XCTAssertGreaterThan(files.count, 10, "The rule must read the app's sources")
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                found.append(file.lastPathComponent + ": " + (text as NSString).substring(with: match.range))
            }
        }
        XCTAssertEqual(found, [], "Delivery has one shared owner; these are app copies")
    }
}
