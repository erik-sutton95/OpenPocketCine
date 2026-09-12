import OpenPocketViewCore
import SwiftUI

/// Reference placement is a presentation preference, separate from color math.
struct FalseColorReferencePositions: Codable, Equatable {
    struct Center: Codable, Equatable {
        let x: Double
        let y: Double

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

    var landscape: Center?
    var portrait: Center?

    func center(in bounds: CGRect, size: CGSize, movement: CGRect) -> CGPoint {
        let stored = ScopeCanvasSlot.pick(landscape, portrait, in: bounds)
        return ScopePanelPlacement.clamp(
            stored?.point(in: bounds) ?? CGPoint(x: bounds.midX, y: bounds.midY),
            size: size, in: movement)
    }
}

@MainActor
@Observable
final class FalseColorReferencePositionStore {
    static let shared = FalseColorReferencePositionStore()
    private let defaults: UserDefaults
    private let key = "OpenPocketCine.Assist.falseColorReference.positions.v1"
    var positions: FalseColorReferencePositions

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        positions =
            defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(FalseColorReferencePositions.self, from: $0) }
            ?? FalseColorReferencePositions()
    }

    func setCenter(_ center: CGPoint, in bounds: CGRect) {
        let stored = FalseColorReferencePositions.Center(center, in: bounds)
        if bounds.height > bounds.width {
            positions.portrait = stored
        } else {
            positions.landscape = stored
        }
        guard let data = try? JSONEncoder().encode(positions) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Reuses the existing reference drawing; this owner only moves its hit surface.
struct FalseColorReferenceOverlay: View {
    let scale: FalseColorScaleKind
    let transfer: MonitorTransfer
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    var hapticsEnabled = false
    var onConfigure: () -> Void = {}
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var pointerActive = false
    @State private var dragOrigin: CGPoint?
    @State private var dragCenter: CGPoint?
    @State private var dragBounds: CGRect?
    @State private var cancelled = false
    private var store: FalseColorReferencePositionStore { .shared }

    var body: some View {
        let movement = ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        let preferred = FalseColorReference.panelSize
        let fit = min(
            1, max(1, movement.width) / preferred.width, max(1, movement.height) / preferred.height)
        let size = CGSize(width: preferred.width * fit, height: preferred.height * fit)
        let center =
            dragCenter ?? store.positions.center(in: bounds, size: size, movement: movement)
        ZStack {
            Color.clear.contentShape(Rectangle())
            FalseColorReference(scale: scale, transfer: transfer).allowsHitTesting(false)
        }
        .scaleEffect(fit)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            interfaceLocked ? nil : dragGesture(center: center, size: size, movement: movement)
        )
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 4) {
            guard !interfaceLocked, dragOrigin == nil else { return }
            onConfigure()
        }
        .position(center)
        .opacity(ScopePanelPlacement.isUsable(movement) ? 1 : 0)
        .allowsHitTesting(!interfaceLocked && ScopePanelPlacement.isUsable(movement))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("False color reference")
        .accessibilityIdentifier("monitor.falseColor.reference")
        .accessibilityAction(named: "False color options") {
            guard !interfaceLocked else { return }
            onConfigure()
        }
        .sensoryFeedback(trigger: dragOrigin != nil) { _, dragging in
            dragging && hapticsEnabled ? .impact(flexibility: .rigid, intensity: 0.5) : nil
        }
        .onChange(of: pointerActive) { _, active in if !active { resetDrag() } }
        .onChange(of: bounds) { _, _ in cancelDrag() }
        .onChange(of: chromeClearance) { _, _ in cancelDrag() }
        .onChange(of: interfaceLocked) { _, locked in if locked { cancelDrag() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelDrag() } }
        .onDisappear(perform: resetDrag)
    }

    private func dragGesture(center: CGPoint, size: CGSize, movement: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($pointerActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !cancelled, !interfaceLocked else { return }
                if dragOrigin == nil {
                    dragOrigin = center
                    dragBounds = bounds
                }
                guard dragBounds == bounds, let origin = dragOrigin else { return }
                dragCenter = ScopePanelPlacement.clamp(
                    CGPoint(
                        x: origin.x + value.translation.width,
                        y: origin.y + value.translation.height),
                    size: size, in: movement)
            }
            .onEnded { _ in
                defer { resetDrag() }
                guard !cancelled, !interfaceLocked, scenePhase == .active,
                    dragBounds == bounds, let dragCenter
                else { return }
                store.setCenter(dragCenter, in: bounds)
            }
    }

    private func cancelDrag() {
        cancelled = pointerActive
        dragOrigin = nil
        dragCenter = nil
        dragBounds = nil
    }

    private func resetDrag() {
        cancelDrag()
        cancelled = false
    }
}
