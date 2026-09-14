import CoreImage
import CoreVideo
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

struct MonitorVideoBackdropConfiguration: Equatable {
    var source: ObjectIdentifier
    var generation: Int
    var effects: LiveImageEffects
    var geometry: [CGFloat] = []
}

/// VT / AVPlayer source buffers stay immutable while retained. The working
/// raster's shared mutable outputs are explicitly excluded from identity caching.
/// Future producers must preserve this contract or also opt out of caching.
struct MonitorVideoBackdropSource: Equatable, @unchecked Sendable {
    var buffer: CVPixelBuffer
    var effects: LiveImageEffects
    var frame: CGRect
    var clip: CGRect

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.buffer === rhs.buffer && lhs.effects == rhs.effects
            && lhs.frame == rhs.frame && lhs.clip == rhs.clip
    }
}

/// One admission includes source selection, low-resolution display-look work,
/// four shared blur products, and pending delivery. Retained by the app owner,
/// so cancelling or remounting a view cannot overlap an unfinished job.
final class MonitorVideoBackdropRenderer: @unchecked Sendable {
    struct Result {
        let snapshot: MonitorBackdropSnapshot?
        let ticket: MonitorPreviewAdmission.Ticket
        let isUnchanged: Bool
    }

    private struct Input: Equatable {
        let canvasSize: CGSize
        let surroundRGB: UInt32
        // Retain the objects, not just their addresses: a released native
        // buffer's identity may be recycled for a different frame.
        let sources: [MonitorVideoBackdropSource]
    }

    private struct CachedResult {
        let owner: UUID
        let input: Input
        let snapshot: MonitorBackdropSnapshot
    }

    typealias Operation =
        @Sendable (CGSize, [MonitorVideoBackdropSource]) -> MonitorBackdropSnapshot?
    private let queue = DispatchQueue(label: "opv.monitor-backdrop", qos: .utility)
    private let lock = NSLock()
    private var admission = MonitorPreviewAdmission()
    private var nextAdmission: UInt64 = 0
    private var cached: CachedResult?  // lock-protected, one successful input only
    private lazy var imageRenderer = AssistInspectorImageRenderer()
    private lazy var backdropRenderer = MonitorBackdropRenderer()
    private let operation: Operation?
    private let clock: @Sendable () -> UInt64
    private let minimumInterval: @Sendable () -> Double

    init(
        clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        minimumInterval: @escaping @Sendable () -> Double = {
            MonitorBackdropPolicy.minimumInterval
        },
        operation: Operation? = nil
    ) {
        self.clock = clock
        self.operation = operation
        self.minimumInterval = minimumInterval
    }

    func activate(_ owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        admission.activate(owner: owner)
        cached = nil
    }

    func deactivate(_ owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        admission.deactivate(owner: owner)
        if cached?.owner == owner { cached = nil }
    }

    func isCurrent(_ result: Result) -> Bool { isCurrent(result.ticket) }

    private func isCurrent(_ ticket: MonitorPreviewAdmission.Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return admission.isCurrent(ticket)
    }

    private func reserve(_ owner: UUID) -> MonitorPreviewAdmission.Ticket? {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        guard now >= nextAdmission,
            let ticket = admission.acquire(
                owner: owner, nowNanoseconds: now, minimumIntervalNanoseconds: 0)
        else { return nil }
        let seconds = max(MonitorBackdropPolicy.minimumInterval, minimumInterval())
        nextAdmission =
            now &+ max(
                MonitorBackdropPolicy.minimumIntervalNanoseconds,
                UInt64((seconds * 1_000_000_000).rounded(.up)))
        return ticket
    }

    private func complete(_ ticket: MonitorPreviewAdmission.Ticket) {
        lock.lock()
        defer { lock.unlock() }
        admission.complete(ticket)
    }

    private func cachedSnapshot(
        for input: Input, ticket: MonitorPreviewAdmission.Ticket
    ) -> MonitorBackdropSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard admission.isCurrent(ticket) else { return nil }
        if cached?.input == input { return cached?.snapshot }
        // A different input must retire the old entry even if rendering fails.
        cached = nil
        return nil
    }

    private func cache(
        _ snapshot: MonitorBackdropSnapshot, input: Input, owner: UUID,
        ticket: MonitorPreviewAdmission.Ticket
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard admission.isCurrent(ticket) else { return }
        cached = CachedResult(owner: owner, input: input, snapshot: snapshot)
    }

    @MainActor
    func render(
        owner: UUID, canvasSize: CGSize, surroundRGB: UInt32 = 0x08090A,
        prepare: @MainActor () -> [MonitorVideoBackdropSource]
    ) async -> Result? {
        guard !Task.isCancelled, let ticket = reserve(owner) else { return nil }
        defer { complete(ticket) }
        let sources = prepare()
        let input = Input(canvasSize: canvasSize, surroundRGB: surroundRGB, sources: sources)
        let result: Result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    var isUnchanged = false
                    let snapshot: MonitorBackdropSnapshot? = autoreleasepool {
                        guard isCurrent(ticket) else { return nil }
                        var canCache =
                            !sources.isEmpty
                            && sources.allSatisfy {
                                // False-color maps warm asynchronously; both
                                // FALSE and ZEBRA also read external exposure
                                // state absent from LiveImageEffects.
                                !$0.effects.falseColor && !$0.effects.zebra
                                    && !FeedWorkingRaster.isReusableOutput($0.buffer)
                            }
                        if let previous = cachedSnapshot(for: input, ticket: ticket), canCache {
                            isUnchanged = true
                            return previous
                        }
                        guard isCurrent(ticket) else { return nil }
                        let snapshot: MonitorBackdropSnapshot?
                        if let operation {
                            snapshot = operation(canvasSize, sources)
                        } else {
                            guard !sources.isEmpty else { return nil }
                            let layers = sources.compactMap { source -> MonitorBackdropLayer? in
                                guard isCurrent(ticket),
                                    let image = imageRenderer.renderImage(
                                        source: source.buffer, effects: source.effects)
                                else { return nil }
                                return MonitorBackdropLayer(
                                    image: image, frame: source.frame, clip: source.clip)
                            }
                            // Preserve partial-source fallback, but retry failed
                            // source renders instead of caching an incomplete stage.
                            canCache = canCache && layers.count == sources.count
                            guard isCurrent(ticket) else { return nil }
                            snapshot = backdropRenderer.render(
                                canvasSize: canvasSize, layers: layers, surroundRGB: surroundRGB)
                        }
                        if let snapshot, canCache {
                            cache(snapshot, input: input, owner: owner, ticket: ticket)
                        }
                        guard isCurrent(ticket) else { return nil }
                        return snapshot
                    }
                    continuation.resume(
                        returning: Result(
                            snapshot: snapshot, ticket: ticket, isUnchanged: isUnchanged))
                }
            }
        } onCancel: {
            self.deactivate(owner)
        }
        guard !Task.isCancelled, isCurrent(ticket) else { return nil }
        return result
    }
}

private struct MonitorVideoBackdrop: ViewModifier {
    let renderer: MonitorVideoBackdropRenderer
    let configuration: [MonitorVideoBackdropConfiguration]
    let enabled: Bool
    let surroundRGB: UInt32
    let sources: @MainActor (CGSize) -> [MonitorVideoBackdropSource]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var applicationActive = true
    @State private var globalFrame: CGRect = .zero
    @State private var snapshot: MonitorBackdropSnapshot?
    @State private var renderedKey: WorkKey?
    @State private var owner: UUID?

    private struct WorkKey: Equatable {
        var configuration: [MonitorVideoBackdropConfiguration]
        var frame: CGRect
        var active: Bool
        var surroundRGB: UInt32
    }

    private var key: WorkKey {
        WorkKey(
            configuration: configuration, frame: globalFrame,
            active: enabled && scenePhase == .active && applicationActive && !reduceTransparency,
            surroundRGB: surroundRGB)
    }

    func body(content: Content) -> some View {
        content
            .monitorBackdrop(renderedKey == key && key.active ? snapshot : nil, in: globalFrame)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                globalFrame = $0
            }
            .task(id: key) { await refresh(key) }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification)
            ) {
                _ in
                applicationActive = false
                if let owner { renderer.deactivate(owner) }
                snapshot = nil
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) {
                _ in applicationActive = true
            }
            .onDisappear {
                if let owner { renderer.deactivate(owner) }
                snapshot = nil
            }
    }

    @MainActor
    private func refresh(_ expected: WorkKey) async {
        guard expected.active, expected.frame.width > 1, expected.frame.height > 1 else { return }
        let identity = UUID()
        owner = identity
        renderer.activate(identity)
        defer {
            renderer.deactivate(identity)
            if owner == identity { owner = nil }
        }
        while !Task.isCancelled {
            let thermal = ProcessInfo.processInfo.thermalState
            let intervalNs = MonitorBackdropPolicy.intervalNanoseconds(
                serious: thermal == .serious, critical: thermal == .critical)
            let started = DispatchTime.now().uptimeNanoseconds
            if let result = await renderer.render(
                owner: identity, canvasSize: expected.frame.size, surroundRGB: expected.surroundRGB,
                prepare: { sources(expected.frame.size) }),
                !Task.isCancelled, renderer.isCurrent(result)
            {
                if !result.isUnchanged {
                    snapshot = result.snapshot
                    renderedKey = expected
                }
            }
            let spent = DispatchTime.now().uptimeNanoseconds &- started
            if spent < intervalNs {
                do {
                    try await Task.sleep(for: .nanoseconds(Int64(intervalNs - spent)))
                } catch { return }
            }
        }
    }
}

extension View {
    func monitorVideoBackdrop(
        renderer: MonitorVideoBackdropRenderer,
        configuration: [MonitorVideoBackdropConfiguration], enabled: Bool,
        surroundRGB: UInt32 = 0x08090A,
        sources: @escaping @MainActor (CGSize) -> [MonitorVideoBackdropSource]
    ) -> some View {
        modifier(
            MonitorVideoBackdrop(
                renderer: renderer, configuration: configuration, enabled: enabled,
                surroundRGB: surroundRGB, sources: sources
            ))
    }
}

extension MonitorVideoBackdropSource {
    /// Fill sizes the native host using the source aspect first. De-squeeze
    /// subsequently fits its wider/taller output inside that same host; it must
    /// not enlarge or crop the host a second time.
    static func displayedFrame(
        sourceAspect: CGFloat, effects: LiveImageEffects, in rect: CGRect,
        fill: Bool = false, zoom: CGFloat = 1, offset: CGSize = .zero
    ) -> CGRect {
        let host = fill ? fittedFrame(aspect: sourceAspect, in: rect, fill: true) : rect
        let aspect =
            sourceAspect
            * (effects.desqueezeHorizontal ? effects.desqueezeFactor : 1 / effects.desqueezeFactor)
        return fittedFrame(aspect: aspect, in: host, zoom: zoom, offset: offset)
    }

    /// Fit/fill and zoom are applied in canvas coordinates before panel clipping.
    static func fittedFrame(
        aspect: CGFloat, in rect: CGRect, fill: Bool = false,
        zoom: CGFloat = 1, offset: CGSize = .zero
    ) -> CGRect {
        let ratio = max(0.001, aspect)
        let width =
            fill ? max(rect.width, rect.height * ratio) : min(rect.width, rect.height * ratio)
        let size = CGSize(width: width * zoom, height: width / ratio * zoom)
        return CGRect(
            x: rect.midX - size.width / 2 + offset.width,
            y: rect.midY - size.height / 2 + offset.height,
            width: size.width, height: size.height)
    }
}
