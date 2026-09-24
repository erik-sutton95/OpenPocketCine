import CoreImage
import CoreVideo
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class MonitorBackdropLifecycleTests: XCTestCase {
    private let step = MonitorBackdropPolicy.minimumIntervalNanoseconds
    func testUnchangedInputSkipsNativeWorkAndPublicationWithoutResettingCadence() async throws {
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let source = try makeSource()
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                calls.increment()
                return snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        let first = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(first).isUnchanged)
        clock.now = step / 2
        let early = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertNil(early)
        clock.now = step
        let repeated = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        let reused = try XCTUnwrap(repeated)
        XCTAssertTrue(reused.isUnchanged, "The view must not republish a cached snapshot")
        XCTAssertTrue(reused.snapshot?.image(for: .compact) === snapshot.image(for: .compact))
        XCTAssertTrue(renderer.isCurrent(reused))
        XCTAssertEqual(calls.value, 1)
        clock.now = step * 2 - 1
        var prepared = false
        let afterHit = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            prepared = true
            return [source]
        }
        XCTAssertNil(afterHit)
        XCTAssertFalse(prepared, "A cache hit still consumes the existing admission interval")
    }

    func testEveryInputChangeInvalidatesTheSingleCachedResult() async throws {
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let first = try makeSource()
        let second = try makeSource()
        let replacement = try makeSource()
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                calls.increment()
                return snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        var sources = [first, second]
        var canvas = snapshot.canvasSize
        var surround: UInt32 = 0x08090A
        var expectedCalls = 0
        func checkChanged(_ label: String) async throws {
            clock.now += step
            let changed = await renderer.render(
                owner: owner, canvasSize: canvas, surroundRGB: surround
            ) {
                sources
            }
            XCTAssertFalse(try XCTUnwrap(changed).isUnchanged, label)
            expectedCalls += 1
            XCTAssertEqual(calls.value, expectedCalls, label)
            clock.now += step
            let repeated = await renderer.render(
                owner: owner, canvasSize: canvas, surroundRGB: surround
            ) {
                sources
            }
            XCTAssertTrue(try XCTUnwrap(repeated).isUnchanged, label)
            XCTAssertEqual(calls.value, expectedCalls, label)
        }
        try await checkChanged("initial ordered inputs")
        sources[1] = replacement
        try await checkChanged("new buffer with identical dimensions and look")
        sources[1].effects.mirror = true
        try await checkChanged("look on a non-first layer")
        sources[1].effects.lutRGBA = Data([1, 2, 3, 4])
        try await checkChanged("LUT data, not just dimension")
        sources[0].effects.zebraHighlightIRE += 1
        try await checkChanged("effect parameter")
        sources[0].frame.origin.x += 1
        try await checkChanged("frame position")
        sources[0].frame.size.width += 1
        try await checkChanged("frame size")
        sources[1].clip.origin.y += 1
        try await checkChanged("clip position")
        sources[1].clip.size.height += 1
        try await checkChanged("clip size")
        canvas.width += 1
        try await checkChanged("canvas width")
        canvas.height += 1
        try await checkChanged("canvas height")
        surround = 0
        try await checkChanged("surround color")
        sources.reverse()
        try await checkChanged("ordered layers")
        sources.removeLast()
        try await checkChanged("layer count")
        sources = [first, second]
        canvas = snapshot.canvasSize
        surround = 0x08090A
        try await checkChanged("returning to an older input does not keep a second cache entry")
    }

    func testFailedRenderAndOwnerRestartCannotReuseAnOlderSnapshot() async throws {
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let original = try makeSource()
        var source = original
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                calls.increment() == 2 ? nil : snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        _ = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) { [source] }
        source.effects.peaking = true
        clock.now += step
        let failure = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertNil(try XCTUnwrap(failure).snapshot)
        clock.now += step
        let retry = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(retry).isUnchanged)
        XCTAssertNotNil(retry?.snapshot, "A failed result must not be cached")
        XCTAssertEqual(calls.value, 3)
        source = original
        clock.now += step
        let restored = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(restored).isUnchanged)
        XCTAssertEqual(calls.value, 4, "Returning to an earlier input must rerender")
        renderer.deactivate(owner)
        renderer.activate(owner)
        clock.now += step
        let restarted = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(restarted).isUnchanged)
        let nextOwner = UUID()
        renderer.activate(nextOwner)
        clock.now += step
        let remounted = await renderer.render(owner: nextOwner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(remounted).isUnchanged)
        renderer.deactivate(owner)
        clock.now += step
        let repeated = await renderer.render(owner: nextOwner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertTrue(
            try XCTUnwrap(repeated).isUnchanged, "Old-owner cleanup cannot clear the new cache")
        XCTAssertEqual(calls.value, 6)
    }

    func testCancelledSuccessfulWorkCannotPopulateNextOwnersCache() async throws {
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let source = try makeSource()
        let started = expectation(description: "Native work started")
        let release = DispatchSemaphore(value: 0)
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                if calls.increment() == 1 {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 3)
                }
                return snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        let pending = Task {
            await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) { [source] }
        }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel()
        let nextOwner = UUID()
        renderer.activate(nextOwner)
        clock.now += step
        let overlap = await renderer.render(owner: nextOwner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertNil(overlap)
        release.signal()
        let stale = await pending.value
        XCTAssertNil(stale)
        let fresh = await renderer.render(owner: nextOwner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(fresh).isUnchanged)
        XCTAssertEqual(calls.value, 2, "Cancelled successful native output must not seed a cache")
        clock.now += step
        let repeated = await renderer.render(owner: nextOwner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertTrue(try XCTUnwrap(repeated).isUnchanged)
    }

    func testReusableWorkingRasterIdentityNeverSkipsNativeWork() async throws {
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let large = try makeBuffer(width: 1600, height: 8)
        let reusable = FeedWorkingRaster.prepared(large)
        XCTAssertTrue(FeedWorkingRaster.isReusableOutput(reusable))
        XCTAssertFalse(FeedWorkingRaster.isReusableOutput(large))
        let source = try makeSource(buffer: reusable)
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                calls.increment()
                return snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        _ = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) { [source] }
        // The real producer overwrites this output while our source retains it.
        XCTAssertTrue(FeedWorkingRaster.prepared(large) === reusable)
        clock.now += step
        let repeated = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
            [source]
        }
        XCTAssertFalse(try XCTUnwrap(repeated).isUnchanged)
        XCTAssertEqual(calls.value, 2)
    }

    func testZebraReusesAHeldSourceUntilItsExposureCeilingChanges() async throws {
        ScopeExposureCeiling.reset()
        defer { ScopeExposureCeiling.reset() }
        ScopeExposureCeiling.setISO(1600)
        let clock = InspectorPreviewTestClock()
        let calls = BackdropTestCounter()
        let snapshot = try makeSnapshot()
        let stable = try makeSource()
        var zebra = try makeSource()
        zebra.effects.zebra = true
        zebra.effects.colorMode = .dLog2
        let source = zebra
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now },
            operation: { _, _ in
                calls.increment()
                return snapshot
            })
        let owner = UUID()
        renderer.activate(owner)
        func render() async throws -> MonitorVideoBackdropRenderer.Result {
            clock.now += step
            let result = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) {
                [stable, source]
            }
            return try XCTUnwrap(result)
        }
        let first = try await render()
        let held = try await render()
        ScopeExposureCeiling.setISO(400)
        let moved = try await render()
        let settled = try await render()
        XCTAssertFalse(first.isUnchanged)
        XCTAssertTrue(held.isUnchanged, "A held zebra source settles")
        XCTAssertFalse(moved.isUnchanged, "A new ceiling moves the zebra threshold")
        XCTAssertTrue(settled.isUnchanged)
        XCTAssertEqual(calls.value, 2)
    }

    func testCachedInputsRetainBuffersUntilInvalidated() async throws {
        let clock = InspectorPreviewTestClock()
        let snapshot = try makeSnapshot()
        let releases = BackdropTestCounter()
        let released = expectation(description: "Invalidation releases retained input identity")
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now }, operation: { _, _ in snapshot })
        let owner = UUID()
        renderer.activate(owner)
        var sources = [
            try makeSource(
                buffer: makeBuffer(onRelease: {
                    releases.increment()
                    released.fulfill()
                }))
        ]
        _ = await renderer.render(owner: owner, canvasSize: snapshot.canvasSize) { sources }
        sources = []
        // Give the completed worker closure time to release its transient inputs;
        // only the cache should retain the external backing bytes now.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(releases.value, 0)
        renderer.deactivate(owner)
        await fulfillment(of: [released], timeout: 2)
        XCTAssertEqual(releases.value, 1)
    }

    private func makeSource(buffer: CVPixelBuffer? = nil) throws -> MonitorVideoBackdropSource {
        let rect = CGRect(x: 0, y: 0, width: 8, height: 8)
        return MonitorVideoBackdropSource(
            buffer: try buffer ?? makeBuffer(), effects: LiveImageEffects(), frame: rect, clip: rect
        )
    }

    private func makeBuffer(
        width: Int = 8, height: Int = 8, onRelease: @escaping @Sendable () -> Void = {}
    ) throws -> CVPixelBuffer {
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: width * height * 4, alignment: 64)
        bytes.initializeMemory(as: UInt8.self, repeating: 0, count: width * height * 4)
        let lifetime = Unmanaged.passRetained(BackdropBufferLifetime(onRelease))
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, bytes, width * 4,
            { refCon, address in
                UnsafeMutableRawPointer(mutating: address)?.deallocate()
                if let refCon {
                    Unmanaged<BackdropBufferLifetime>.fromOpaque(refCon).takeRetainedValue()
                        .release()
                }
            }, lifetime.toOpaque(), nil, &buffer)
        guard status == kCVReturnSuccess else {
            bytes.deallocate()
            lifetime.release()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try XCTUnwrap(buffer)
    }

    private func makeSnapshot() throws -> MonitorBackdropSnapshot {
        let rect = CGRect(x: 0, y: 0, width: 8, height: 8)
        let image = try XCTUnwrap(CIContext().createCGImage(CIImage(color: .black), from: rect))
        return try XCTUnwrap(
            MonitorBackdropRenderer().render(
                canvasSize: rect.size, layers: [.init(image: image, frame: rect, clip: rect)]))
    }

    func testCancellationRemountAndThermalBackoffKeepOneOccupiedSlotAndRejectOldResults()
        async throws
    {
        let clock = InspectorPreviewTestClock()
        let started = expectation(description: "Native work began")
        let release = DispatchSemaphore(value: 0)
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now }, minimumInterval: { 1 },
            operation: { _, _ in
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
                return nil
            })
        let first = UUID()
        renderer.activate(first)
        let pending = Task {
            await renderer.render(owner: first, canvasSize: CGSize(width: 900, height: 600)) { [] }
        }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel()
        let second = UUID()
        renderer.activate(second)
        clock.now = 2_000_000_000
        var prepared = false
        let overlap = await renderer.render(
            owner: second, canvasSize: CGSize(width: 900, height: 600)
        ) {
            prepared = true
            return []
        }
        XCTAssertNil(overlap)
        XCTAssertFalse(prepared, "Rejected jobs must not fetch/retain source buffers")
        renderer.deactivate(first)
        release.signal()
        let stale = await pending.value
        XCTAssertNil(stale, "An old source must not publish after cancellation/remount")

        // A separate completed-job case verifies the retained thermal deadline,
        // independent of task sleeps or rapidly replaced view owners.
        clock.now = 0
        let thermal = MonitorVideoBackdropRenderer(
            clock: { clock.now }, minimumInterval: { 1 }, operation: { _, _ in nil })
        thermal.activate(first)
        let firstResult = await thermal.render(
            owner: first, canvasSize: CGSize(width: 9, height: 6)
        ) { [] }
        let admitted = try XCTUnwrap(firstResult)
        XCTAssertTrue(thermal.isCurrent(admitted))
        thermal.deactivate(first)
        for timestamp in [UInt64(200_000_000), 600_000_000, 999_999_999] {
            clock.now = timestamp
            let owner = UUID()
            thermal.activate(owner)
            let tooEarly = await thermal.render(
                owner: owner, canvasSize: CGSize(width: 9, height: 6)
            ) { [] }
            XCTAssertNil(tooEarly)
        }
        clock.now = 1_000_000_000
        thermal.activate(second)
        let next = await thermal.render(owner: second, canvasSize: CGSize(width: 9, height: 6)) {
            []
        }
        XCTAssertNotNil(next)
        XCTAssertFalse(thermal.isCurrent(admitted))
    }

    func testFitFillZoomAndOffsetPreserveSourceCoordinates() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 300)
        let fit = MonitorVideoBackdropSource.fittedFrame(aspect: 2, in: rect)
        XCTAssertEqual(fit, CGRect(x: 100, y: 275, width: 300, height: 150))
        let fill = MonitorVideoBackdropSource.fittedFrame(aspect: 2, in: rect, fill: true)
        XCTAssertEqual(fill, CGRect(x: -50, y: 200, width: 600, height: 300))
        let zoom = MonitorVideoBackdropSource.fittedFrame(
            aspect: 2, in: rect, zoom: 2, offset: CGSize(width: 20, height: -10))
        XCTAssertEqual(zoom, CGRect(x: -30, y: 190, width: 600, height: 300))
        var effects = LiveImageEffects()
        effects.desqueezeFactor = 2
        let stretched = MonitorVideoBackdropSource.displayedFrame(
            sourceAspect: 2, effects: effects, in: rect, fill: true)
        XCTAssertEqual(
            stretched, CGRect(x: -50, y: 275, width: 600, height: 150),
            "De-squeeze fits inside the existing native host after its source fill")
        let unstretchedHost = MonitorVideoBackdropSource.displayedFrame(
            sourceAspect: 2, effects: effects, in: rect)
        XCTAssertEqual(unstretchedHost, CGRect(x: 100, y: 312.5, width: 300, height: 75))
    }
}

private final class BackdropTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class BackdropBufferLifetime: @unchecked Sendable {
    let release: @Sendable () -> Void

    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
}
