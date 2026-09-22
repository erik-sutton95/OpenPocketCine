import MonitorUI
import OpenPocketViewCore
import SwiftUI

enum EVMeterAssist {
    static let baseSize = CGSize(width: 220, height: 64)
    static let helpCopy =
        "Measures median picture brightness in stops relative to middle gray. Positive is brighter; negative is darker. Works in Auto and Manual without changing camera settings. D-Log M is an estimate."

    static func clampedScale(_ scale: Double) -> Double {
        scale.isFinite ? min(1.6, max(0.6, scale)) : 1
    }

    @MainActor
    static func reading(from samples: LiveFrameSampleBus) -> ExposureMeterReading {
        // An opening clip must not borrow the retained live camera histogram.
        let bundle = samples.usesPlaybackSource ? samples.playbackBundle ?? .empty : samples.bundle
        return ExposureMeterReading(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
    }

    struct Center: Codable, Equatable {
        var x: Double
        var y: Double

        init(_ point: CGPoint, in bounds: CGRect) {
            x = (point.x - bounds.minX) / max(1, bounds.width)
            y = (point.y - bounds.minY) / max(1, bounds.height)
        }

        func point(in bounds: CGRect) -> CGPoint {
            CGPoint(
                x: bounds.minX + (x.isFinite ? x : 0.5) * bounds.width,
                y: bounds.minY + (y.isFinite ? y : 0.5) * bounds.height)
        }
    }

    struct Options: Codable, Equatable {
        var scale = 1.0
        var landscapeCenter: Center?
        var portraitCenter: Center?
    }
}

@MainActor
@Observable
final class EVMeterStore {
    static let shared = EVMeterStore()
    private let defaults: UserDefaults
    private let key = "OpenPocketCine.Assist.evMeter.v1"
    var options: EVMeterAssist.Options

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        options =
            defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(EVMeterAssist.Options.self, from: $0) }
            ?? EVMeterAssist.Options()
        options.scale = EVMeterAssist.clampedScale(options.scale)
    }

    func center(in bounds: CGRect) -> CGPoint {
        ScopeCanvasSlot.pick(options.landscapeCenter, options.portraitCenter, in: bounds)?
            .point(in: bounds) ?? CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func setCenter(_ center: CGPoint, in bounds: CGRect) {
        let stored = EVMeterAssist.Center(center, in: bounds)
        if bounds.height > bounds.width {
            options.portraitCenter = stored
        } else {
            options.landscapeCenter = stored
        }
        persist()
    }

    func setScale(_ scale: Double) {
        options.scale = EVMeterAssist.clampedScale(scale)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: key)
    }
}

struct EVMeterGauge: View {
    let reading: ExposureMeterReading

    var body: some View {
        MonitorExposureGauge(
            value: reading.label, needleFraction: reading.needleFraction,
            estimated: reading.isEstimated
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EV meter")
        .accessibilityValue(reading.accessibilityValue)
    }
}

/// Position and resize work stays local to the gesture; preferences change on release.
struct EVMeterOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.scenePhase) private var scenePhase
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @GestureState private var pointerActive = false
    @State private var origin: CGPoint?
    @State private var dragCenter: CGPoint?
    @State private var resizeScale: Double?
    @State private var gestureBounds: CGRect?
    @State private var cancelled = false
    private var store: EVMeterStore { .shared }

    var body: some View {
        let movement = ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        let scale = resizeScale ?? store.options.scale
        let preferred = CGSize(
            width: EVMeterAssist.baseSize.width * scale,
            height: EVMeterAssist.baseSize.height * scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: movement)
        let center = ScopePanelPlacement.clamp(
            dragCenter ?? store.center(in: bounds), size: size, in: movement)
        let usable = ScopePanelPlacement.isUsable(movement)
        EVMeterGauge(reading: EVMeterAssist.reading(from: model.monitorSamples))
            .frame(width: size.width, height: size.height)
            .accessibilityIdentifier("monitor.ev.meter")
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center, size: size, movement: movement))
            .overlay(alignment: .bottomTrailing) {
                resizeHandle
                    .offset(x: 44, y: ScopePanelPlacement.gripBottomExtent)
            }
            .position(center)
            .opacity(usable ? 1 : 0)
            .allowsHitTesting(!interfaceLocked && usable)
            .onChange(of: pointerActive) { _, active in if !active { resetGesture() } }
            .onChange(of: bounds) { _, _ in cancelGesture() }
            .onChange(of: chromeClearance) { _, _ in cancelGesture() }
            .onChange(of: interfaceLocked) { _, locked in if locked { cancelGesture() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { cancelGesture() } }
            .onDisappear(perform: resetGesture)
    }

    private var resizeHandle: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 14, y: 14))
            path.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(resizeScale == nil ? MonitorTheme.muted : MonitorTheme.accent, lineWidth: 1.5)
        .frame(width: 14, height: 14)
        .offset(y: ScopePanelPlacement.gripTopInterior - 12)
        .frame(width: 56, height: 56, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($pointerActive) { _, active, _ in active = true }
                .onChanged { value in
                    guard canChange else { return }
                    if gestureBounds == nil { gestureBounds = bounds }
                    guard gestureBounds == bounds else { return }
                    let reach = EVMeterAssist.baseSize.width + EVMeterAssist.baseSize.height
                    resizeScale = EVMeterAssist.clampedScale(
                        store.options.scale + (value.translation.width + value.translation.height)
                            / reach)
                }
                .onEnded { _ in
                    defer { resetGesture() }
                    guard canChange, gestureBounds == bounds, let resizeScale else { return }
                    store.setScale(resizeScale)
                }
        )
        .accessibilityLabel("Resize EV meter")
        .accessibilityIdentifier("monitor.ev.resize")
    }

    private var canChange: Bool { !cancelled && !interfaceLocked && scenePhase == .active }

    private func dragGesture(center: CGPoint, size: CGSize, movement: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($pointerActive) { _, active, _ in active = true }
            .onChanged { value in
                guard canChange, resizeScale == nil else { return }
                if origin == nil {
                    origin = center
                    gestureBounds = bounds
                }
                guard gestureBounds == bounds, let origin else { return }
                let proposed = CGPoint(
                    x: ((origin.x + value.translation.width) / 4).rounded() * 4,
                    y: ((origin.y + value.translation.height) / 4).rounded() * 4)
                dragCenter = ScopePanelPlacement.clamp(proposed, size: size, in: movement)
            }
            .onEnded { _ in
                defer { resetGesture() }
                guard canChange, gestureBounds == bounds, let dragCenter else { return }
                store.setCenter(dragCenter, in: bounds)
            }
    }

    private func cancelGesture() {
        cancelled = pointerActive
        origin = nil
        dragCenter = nil
        resizeScale = nil
        gestureBounds = nil
    }

    private func resetGesture() {
        cancelGesture()
        cancelled = false
    }
}
