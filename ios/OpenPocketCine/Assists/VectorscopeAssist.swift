import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine vectorscope operator options + `MovablePanel` (id `"vector"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.vectorscopeRows`):
/// * Trace Zoom - 1x / 2x / 4x (graticule stays at unity)
/// * Brightness - 0…200% (default 100; unity baseline, unlike WAVE/PARADE’s /400)
///
/// Always-on plot (no popup toggle in OpenZCine): 75% graticule, 123° I-phase
/// skin line, colour density rendering (log alpha + `traceTint` + 1.1-bin blur
/// + 0.35 crisp core + 0.35 trail).
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum VectorscopeAssist {
    static let panelID = "vector"
    static let baseSize = ScopePanelSize.vectorscope
    static let brightnessRange: ClosedRange<Int> = 0...200

    /// OpenZCine `AssistConfiguration.Scopes.VectorscopeZoom`.
    typealias Zoom = MonitorVectorscopeZoom

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorVectorscopeOptions

    /// OpenZCine `Scopes.brightnessMultiplier` - vectorscope keeps the unity baseline.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

    static func panelSize(scale: Double) -> CGSize {
        MonitorScopePanelCentering.panelSize(baseSize, scale: Options.clampedScale(scale))
    }

    /// OpenZCine `ScopeMini` vectorscope chip - `MON · 1X`.
    static func chip(zoom: Zoom) -> String {
        "MON · \(zoom.rawValue.uppercased())"
    }

    @MainActor
    static var store: VectorscopeAssistStore { VectorscopeAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        VectorscopeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared vectorscope store. `assist` is unused - options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> VectorscopeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    @MainActor
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> MonitorScopeStoredPanel<Options, Content> {
        MonitorScopeStoredPanel(
            store: store, baseSize: baseSize, canvas: canvas, chromeClearance: chromeClearance,
            resizeLabel: "Resize vectorscope", content: content)
    }
}

typealias VectorscopeAssistStore = MonitorScopePanelStore<MonitorVectorscopeOptions>

/// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
struct VectorscopeLongPressMenu: View {
    @Binding var options: VectorscopeAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu.buttonStyle(.monitorTapTarget) }

    var assistMenu: MonitorVectorscopeMenu {
        MonitorVectorscopeMenu(
            zoom: Binding(
                get: { options.zoom },
                set: {
                    guard $0 != options.zoom else { return }
                    VectorscopeAssistHaptics.selection(); options.zoom = $0
                }),
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = VectorscopeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    VectorscopeAssistHaptics.selection(); options.brightness = next
                }),
            zoomHelp:
                "Magnifies only the chroma trace; the graticule stays at unity. The vectorscope reads the monitor image (your active LUT, or the built-in display tone map), where chroma is meaningful.",
            brightnessHelp: "Raise trace intensity when the chroma plot is hard to read.",
            brightnessRange: VectorscopeAssist.brightnessRange, compact: compact,
            zoomFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            })
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum VectorscopeAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
