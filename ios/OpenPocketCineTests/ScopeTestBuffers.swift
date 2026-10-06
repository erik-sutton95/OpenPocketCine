import AVFoundation
import CoreVideo
import Foundation
import OpenPocketViewCore
import Observation
import UIKit
import XCTest
import OpenCineApple

@testable import OpenPocketCine

/// Shared synthetic-buffer factories for the scope-pipeline tests.
///
/// Everything is **legal-scaled**: the camera writes `container10 = 64 + curve × 876`
/// in a tv-range container, and `LiveFrameTap` expands that back to curve
/// fractions. So D-Log2 black is Y10 119 (→ tap byte 16), 18% grey is Y10 331
/// (→ 78), clip is Y10 940 (→ 255). Neutral chroma is 512 (10-bit) / 128 (8-bit).
/// BGRA buffers carry tap-domain curve bytes directly.
enum ScopeTestBuffers {
    /// Legal-scaled 10-bit container code for a curve fraction.
    static func legal10(_ curveFraction: Double) -> Int {
        Int((64 + curveFraction * 876).rounded())
    }

    /// D-Log2 wire anchors (legal-scaled): black 119, grey 331, clip 940.
    static let dlog2Black10 = 119
    static let dlog2Grey10 = 331
    static let clip10 = 940

    // MARK: - BGRA (tap-domain curve bytes)

    static func makeBGRA(
        width: Int = 128, height: Int = 72, code: (Int, Int) -> UInt8
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("CVPixelBufferCreate failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let value = code(x, y)
                let p = base.advanced(by: y * stride + x * 4)
                p[0] = value
                p[1] = value
                p[2] = value
                p[3] = 255
            }
        }
        return buffer
    }

    static func makeFlatBuffer(code: UInt8, width: Int = 128, height: Int = 72) -> CVPixelBuffer {
        makeBGRA(width: width, height: height) { _, _ in code }
    }

    /// Tinted flat field: BGRA bytes carry the given curve codes per channel.
    static func makeFlatBuffer(
        red: UInt8, green: UInt8, blue: UInt8, width: Int = 128, height: Int = 72
    ) -> CVPixelBuffer {
        let buffer = makeBGRA(width: width, height: height) { _, _ in 0 }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let p = base.advanced(by: y * stride + x * 4)
                p[0] = blue
                p[1] = green
                p[2] = red
            }
        }
        return buffer
    }

    static func makeEdgeBuffer(width: Int = 128, height: Int = 72) -> CVPixelBuffer {
        makeBGRA(width: width, height: height) { x, _ in x > width / 2 ? 255 : 16 }
    }

    /// Metal-compatible IOSurface BGRA. `filled == false` when the host cannot
    /// CPU-write the surface (skip hardware-dependent asserts there).
    static func makeIOSurfaceBGRA(width: Int, height: Int, left: UInt8, right: UInt8)
        -> (buffer: CVPixelBuffer, filled: Bool)
    {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("IOSurface BGRA create failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return (buffer, false)
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let src = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let on = x < width / 2 ? left : right
                let p = src.advanced(by: y * stride + x * 4)
                p[0] = on
                p[1] = on
                p[2] = on
                p[3] = 255
            }
        }
        return (buffer, true)
    }

    // MARK: - 10-bit x420 (legal-scaled wire codes, MSB-aligned words)

    /// `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` with per-column 10-bit
    /// luma codes and neutral chroma 512. Stores `value << 6` (MSB alignment).
    /// `nil` when the host cannot create the format.
    static func makeX420(
        width: Int, height: Int, ioSurface: Bool = false, luma10: (Int, Int) -> Int
    ) -> CVPixelBuffer? {
        var attrs: [String: Any] = [:]
        if ioSurface {
            attrs[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] as [String: Any]
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            attrs.isEmpty ? nil : attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
        else { return nil }
        let lumaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chromaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for y in 0..<height {
            for x in 0..<width {
                lumaBase.storeBytes(
                    of: UInt16(luma10(x, y) << 6),
                    toByteOffset: y * lumaBPR + x * 2, as: UInt16.self)
            }
        }
        let chromaH = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let chromaW = CVPixelBufferGetWidthOfPlane(buffer, 1)
        for y in 0..<chromaH {
            for x in 0..<chromaW {
                chromaBase.storeBytes(
                    of: UInt16(512 << 6), toByteOffset: y * chromaBPR + x * 4, as: UInt16.self)
                chromaBase.storeBytes(
                    of: UInt16(512 << 6), toByteOffset: y * chromaBPR + x * 4 + 2, as: UInt16.self)
            }
        }
        return buffer
    }

    // MARK: - 8-bit 420v (video-range luma, neutral chroma 128)

    static func make420v(width: Int, height: Int, leftY: UInt8, rightY: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("420v create failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(
            to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<height {
            for x in 0..<width {
                yBase[y * yStride + x] = x < width / 2 ? leftY : rightY
            }
        }
        let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let uvH = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let uvW = CVPixelBufferGetWidthOfPlane(buffer, 1)
        for y in 0..<uvH {
            for x in 0..<uvW {
                uv[y * uvStride + x * 2] = 128
                uv[y * uvStride + x * 2 + 1] = 128
            }
        }
        return buffer
    }
}

/// SIMULATED: real encoded clip -> AVPlayerItemVideoOutput -> native feed -> source-owned scopes.
/// This fixture never calls an app/shared submit helper or writes sample-bus publications.
@MainActor
final class PlaybackOutputFixture {
    let item: AVPlayerItem
    let player = AVPlayer()
    let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    private let url: URL
    private var readiness: XCTestExpectation?
    private var readinessObservation: NSKeyValueObservation?

    private init(url: URL) {
        self.url = url
        item = AVPlayerItem(url: url)
    }

    static func make(in test: XCTestCase, code: UInt8 = 180) async throws -> PlaybackOutputFixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simulated-playback-output-\(UUID().uuidString).mov")
        do {
            let writer = try PlaybackClipWriter(url: url, code: code)
            try await writer.write(in: test)
            return PlaybackOutputFixture(url: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func prepare(_ session: PlaybackFeedSession) {
        // The real owner attaches its output before the item becomes current.
        session.prepare(item)
        player.replaceCurrentItem(with: item)
        session.attach(host: host, player: player)
    }

    func publishScopes(
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
            throw item.error ?? PlaybackFixtureError.itemNotReady
        }
        XCTAssertTrue(item.outputs.contains(where: { $0 === session.output }))

        let delivered = test.expectation(description: "actual playback output publishes a scope bundle")
        let waiter = PlaybackPublicationWait(samples: samples, delivered: delivered)
        waiter.arm()
        session.noteItemReady()
        player.play()
        // Same publication timeout as the former direct-buffer fixtures.
        await test.fulfillment(of: [delivered], timeout: 2)
        waiter.stop()
        player.pause()
    }

    func close() {
        readinessObservation?.invalidate()
        readinessObservation = nil
        readiness = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? FileManager.default.removeItem(at: url)
    }
}

private enum PlaybackFixtureError: Error {
    case cannotAddVideo, writingFailed, itemNotReady
}

@MainActor
private final class PlaybackPublicationWait {
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

@MainActor
private final class PlaybackClipWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let buffer: CVPixelBuffer
    private var frame = 0
    private let frameCount = 60
    private var finishedAppending = false
    private var cancelled = false
    private var completed: XCTestExpectation?
    private var failure: Error?

    init(url: URL, code: UInt8) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64, AVVideoHeightKey: 64,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ])
        buffer = ScopeTestBuffers.makeFlatBuffer(code: code, width: 64, height: 64)
        guard writer.canAdd(input) else { throw PlaybackFixtureError.cannotAddVideo }
        writer.add(input)
    }

    func write(in test: XCTestCase) async throws {
        guard writer.startWriting() else {
            throw writer.error ?? PlaybackFixtureError.writingFailed
        }
        writer.startSession(atSourceTime: .zero)
        let completion = test.expectation(description: "actual flat H264 fixture written")
        completed = completion
        input.requestMediaDataWhenReady(on: .main) { [weak self] in
            // This callback was explicitly scheduled on the main queue.
            MainActor.assumeIsolated { self?.appendAvailableFrames() }
        }
        await test.fulfillment(of: [completion], timeout: 3)
        guard writer.status == .completed else {
            cancelled = true
            completed = nil
            let error = failure ?? writer.error ?? PlaybackFixtureError.writingFailed
            writer.cancelWriting()
            throw error
        }
    }

    private func appendAvailableFrames() {
        guard !cancelled, !finishedAppending else { return }
        while input.isReadyForMoreMediaData, frame < frameCount {
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            else {
                cancelled = true
                failure = writer.error ?? PlaybackFixtureError.writingFailed
                writer.cancelWriting()
                completed?.fulfill()
                completed = nil
                return
            }
            frame += 1
        }
        guard frame == frameCount else { return }
        finishedAppending = true
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self, !self.cancelled else { return }
                self.completed?.fulfill()
                self.completed = nil
            }
        }
    }
}
