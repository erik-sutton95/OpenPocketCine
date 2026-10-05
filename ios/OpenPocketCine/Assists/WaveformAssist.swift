import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine waveform operator options + `MovablePanel` (id `"wave"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.waveformRows`):
/// * Mode - Luma / RGB
/// * Brightness - 0…200% (default 100; OpenZCine `/400`, so 100% = 0.25)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Size is the L-corner grip only (OpenZCine dropped Small/Medium/Large; no
/// Size slider in the popup). Scale is 0.6…1.6.
/// WAVE axis matches traffic lights: 0 = paper black, 100 = live-tap
/// ceiling, 18% gray at the log paper IRE (D-Log2 = 30.50). Dotted 5 / 95
/// are safe-border guides. Hold the panel (no drag) or long-press WAVE
/// on the assist bar to open options.
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid).
/// No pinch-resize - OpenZCine scales only from the L-corner grip.
enum WaveformAssist {
    static let panelID = "wave"
    static let baseSize = ScopePanelSize.waveform
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let brightnessRange: ClosedRange<Int> = 0...200
    static let defaultBrightness = 100
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    static let brightnessHelp =
        "Raise trace intensity when the waveform is hard to read in bright light."

    typealias Mode = MonitorWaveformMode

    typealias GuideLines = MonitorScopeGuides

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorWaveformOptions

    /// OpenZCine `waveformParadeBrightnessMultiplier` - 100% = former 25%.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 400
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// Unplaced tools start at the canvas center; saved/session centers win later.
    static func defaultCenter(
        feed _: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance _: EdgeInsets = EdgeInsets(),
        gap _: CGFloat = 10
    ) -> CGPoint {
        clamp(
            CGPoint(x: bounds.midX, y: bounds.midY), size: size, bounds: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(bounds.minX + halfWidth, point.x), bounds.maxX - halfWidth),
            y: min(max(bounds.minY + halfHeight, point.y), bounds.maxY - halfHeight))
    }

    static func snap(_ point: CGPoint, grid: CGFloat = positionGrid) -> CGPoint {
        CGPoint(
            x: (point.x / grid).rounded() * grid,
            y: (point.y / grid).rounded() * grid)
    }

    static func hapticCell(_ point: CGPoint, grid: CGFloat = hapticGrid) -> Int {
        Int((point.x / grid).rounded()) &* 100_000
            &+ Int((point.y / grid).rounded())
    }

    static func resolvedCenter(
        session: CGPoint?,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, bounds: bounds) }
        if let stored { return clamp(stored.center(in: bounds), size: size, bounds: bounds) }
        return clamp(defaultCenter, size: size, bounds: bounds)
    }

    @MainActor
    static var store: WaveformAssistStore { WaveformAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.waveformRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        WaveformLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared waveform store. Options live off `LiveAssistState` so
    /// parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> WaveformLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Hold-without-drag on the WAVE panel, or long-press the WAVE chip.
    @MainActor
    static func presentOptions(anchor: CGRect, assist: LiveAssistState) {
        assist.longPressAnchor = anchor
        assist.configureTool = .waveform
    }

    static func shouldPresentOptions(translation: CGSize) -> Bool {
        WaveformAxis.shouldPresentOptions(translation: translation)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    /// A hold that does not drag opens ``presentOptions``.
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        onOpenOptions: ((CGRect) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> WaveformMovablePanel<Content> {
        WaveformMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance,
            onOpenOptions: onOpenOptions, content: content)
    }
}

typealias WaveformAssistStore = MonitorScopePanelStore<MonitorWaveformOptions>

/// OpenZCine `AssistQuickSettingsContent.waveformRows`.
struct WaveformLongPressMenu: View {
    @Binding var options: WaveformAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu.buttonStyle(.monitorTapTarget) }

    var assistMenu: MonitorScopeTraceMenu<WaveformAssist.Mode> {
        MonitorScopeTraceMenu(
            modes: WaveformAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = WaveformAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    WaveformAssistHaptics.selection(); options.brightness = next
                }), guides: $options.guides, title: { $0.rawValue },
            brightnessHelp: WaveformAssist.brightnessHelp,
            brightnessRange: WaveformAssist.brightnessRange,
            compact: compact,
            modeFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }, guideFeedback: { WaveformAssistHaptics.selection() })
    }
}

struct WaveformMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    var onOpenOptions: ((CGRect) -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: WaveformAssistStore { WaveformAssist.store }
    var body: some View {
        let bounds = ScopePanelPlacement.bounds(in: canvas, clearance: chromeClearance)
        let scale = store.presentationScale(in: canvas)
        let preferred = WaveformAssist.panelSize(scale: scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: bounds)
        let fallback = WaveformAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = WaveformAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas), defaultCenter: fallback, size: size,
            bounds: canvas)
        MonitorMovableScopePanel(
            layout: MonitorScopePanelLayout(
                baseSize: WaveformAssist.baseSize,
                preferredSize: preferred, center: center, scale: scale, canvas: canvas,
                movementBounds: bounds),
            enabled: !interfaceLocked, resizeLabel: "Resize waveform",
            onMove: { event in
                switch event {
                case .began(let center): store.beginDrag(center: center, in: canvas)
                case .changed(let center): store.drag(to: center, in: canvas)
                case .ended: store.endDrag(bounds: canvas)
                case .cancelled(let retiredCanvas): store.cancelDrag(bounds: retiredCanvas)
                }
            }, onResize: { store.setScale($0) },
            onOpenOptions: onOpenOptions, onConfirm: { WaveformAssistHaptics.confirm() },
            content: content)
    }
}



/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum WaveformAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }

    @MainActor
    static func confirm() {
        guard OperatorPrefs.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }
}
