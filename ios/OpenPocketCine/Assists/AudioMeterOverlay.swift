import OpenPocketViewCore
import SwiftUI

private struct AudioInspectorLevelsKey: EnvironmentKey {
    static let defaultValue: AudioMeterLevels? = nil
}

extension EnvironmentValues {
    /// Playback injects levels from its existing meter owner. A nil value never
    /// substitutes camera audio while the inspector is grading a clip.
    var audioInspectorLevels: AudioMeterLevels? {
        get { self[AudioInspectorLevelsKey.self] }
        set { self[AudioInspectorLevelsKey.self] = newValue }
    }
}

/// Keeps frequent audio observations inside the meter, not the scope host.
struct LiveAudioMeterOverlay: View {
    @Environment(AppModel.self) private var model
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        AudioMeterOverlay(
            levels: model.session.status.audioMeters,
            sensitivity: model.session.status.audioChannel?.label,
            bounds: bounds, chromeClearance: chromeClearance,
            hapticsEnabled: model.hapticsEnabled,
            onConfigure: { model.assist.configureTool = .audioMeters })
    }
}

/// Pointer cancel/persist for the audio overlay. GestureState stays on the view.
struct AudioMeterDragLifecycle: Equatable {
    var origin: CGPoint?
    var center: CGPoint?
    var bounds: CGRect?
    var cancelled = false

    mutating func cancel(pointerActive: Bool) {
        cancelled = pointerActive
        origin = nil
        center = nil
        bounds = nil
    }

    mutating func reset(pointerActive: Bool) {
        cancel(pointerActive: pointerActive)
        cancelled = false
    }

    mutating func applyChanged(
        translation: CGSize, visualCenter: CGPoint, currentBounds: CGRect, size: CGSize,
        canvas: CGRect, movement: CGRect, locked: Bool, sceneActive: Bool, usable: Bool
    ) {
        guard !cancelled, !locked, sceneActive, usable else { return }
        if origin == nil {
            origin = visualCenter
            bounds = currentBounds
        }
        guard bounds == currentBounds, let origin else { return }
        let proposed = CGPoint(
            x: origin.x + translation.width, y: origin.y + translation.height)
        center = AudioAssist.center(
            stored: AudioAssist.StoredCenter(proposed, in: currentBounds),
            size: size, canvas: canvas, movement: movement)
    }

    func persistableCenter(
        locked: Bool, sceneActive: Bool, usable: Bool, currentBounds: CGRect
    ) -> CGPoint? {
        guard !cancelled, !locked, sceneActive, usable, bounds == currentBounds else { return nil }
        return center
    }
}

/// Live and playback inject their existing levels; this view owns no sampling.
struct AudioMeterOverlay: View {
    static let pointerSlop: CGFloat = 4

    static func allowsHits(locked: Bool, movement: CGRect) -> Bool {
        !locked && ScopePanelPlacement.isUsable(movement)
    }

    let levels: AudioMeterLevels
    let sensitivity: String?
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    var hapticsEnabled = false
    var onConfigure: () -> Void = {}
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var pointerActive = false
    @State private var drag = AudioMeterDragLifecycle()
    private var store: AudioAssistStore { AudioAssist.store }

    var body: some View {
        let options = store.options
        let movement = ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        let usable = ScopePanelPlacement.isUsable(movement)
        let hittable = Self.allowsHits(locked: interfaceLocked, movement: movement)
        let preferred = AudioAssist.panelSize(orientation: options.orientation)
        let scale = min(
            1, max(1, movement.width) / preferred.width, max(1, movement.height) / preferred.height)
        let size = CGSize(width: preferred.width * scale, height: preferred.height * scale)
        let center = AudioAssist.center(
            stored: drag.center.map { AudioAssist.StoredCenter($0, in: bounds) }
                ?? store.storedCenter(in: bounds),
            size: size, canvas: bounds, movement: movement)
        ZStack {
            Color.clear.contentShape(Rectangle())
            AudioMetersPanelMini(
                levels: levels, sensitivity: sensitivity,
                orientation: options.orientation, showsDB: options.showsDB
            )
        }
        .scaleEffect(scale)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            hittable ? dragGesture(center: center, size: size, movement: movement) : nil
        )
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: Self.pointerSlop) {
            guard hittable, drag.origin == nil else { return }
            onConfigure()
        }
        .position(center)
        .opacity(usable ? 1 : 0)
        .allowsHitTesting(hittable)
        .accessibilityIdentifier("monitor.audio.meter")
        .accessibilityAction(named: "Audio options") {
            guard hittable else { return }
            onConfigure()
        }
        .sensoryFeedback(trigger: drag.origin != nil) { _, dragging in
            dragging && hapticsEnabled ? .impact(flexibility: .rigid, intensity: 0.5) : nil
        }
        .onChange(of: pointerActive) { _, active in if !active { resetDrag() } }
        .onChange(of: bounds) { _, _ in cancelDrag() }
        .onChange(of: chromeClearance) { _, _ in cancelDrag() }
        .onChange(of: options.orientation) { _, _ in cancelDrag() }
        .onChange(of: usable) { _, isUsable in if !isUsable { cancelDrag() } }
        .onChange(of: interfaceLocked) { _, locked in if locked { cancelDrag() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelDrag() } }
        .onDisappear(perform: resetDrag)
    }

    private func dragGesture(center: CGPoint, size: CGSize, movement: CGRect) -> some Gesture {
        DragGesture(minimumDistance: Self.pointerSlop, coordinateSpace: .global)
            .updating($pointerActive) { _, active, _ in active = true }
            .onChanged { value in
                drag.applyChanged(
                    translation: value.translation, visualCenter: center, currentBounds: bounds,
                    size: size, canvas: bounds, movement: movement,
                    locked: interfaceLocked, sceneActive: scenePhase == .active,
                    usable: ScopePanelPlacement.isUsable(movement)
                )
            }
            .onEnded { _ in
                defer { resetDrag() }
                guard
                    let center = drag.persistableCenter(
                        locked: interfaceLocked, sceneActive: scenePhase == .active,
                        usable: ScopePanelPlacement.isUsable(movement), currentBounds: bounds)
                else { return }
                store.setCenter(center, in: bounds)
            }
    }

    private func cancelDrag() {
        drag.cancel(pointerActive: pointerActive)
    }

    private func resetDrag() {
        drag.reset(pointerActive: pointerActive)
    }
}
