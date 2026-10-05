import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine RGB Parade operator options + `MovablePanel` (id `"parade"`).
///
/// Sources: `OperatorPreferences.Scopes.ParadeMode`,
/// `MonitorPanels.AssistQuickSettingsContent.paradeRows`,
/// `MonitorOverlays.LiveParadeScopePanel` / `ParadeScopePlot` / `ScopeMini` chip,
/// `MonitorScopeTraceMetal.Mode.parade`.
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.paradeRows`):
/// * Mode - RGB / YRGB
/// * Brightness - 0…200% (default 100)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Parade Y is the WAVE IRE axis: 0 / 100 on the plot edges, dotted 5 / 95
/// safe borders, middle gray at paper IRE. No 0 / 50 / 100 labels.
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum ParadeAssist {
    static let panelID = "parade"
    static let baseSize = ScopePanelSize.parade
    static let brightnessRange: ClosedRange<Int> = 0...200

    typealias Mode = MonitorParadeMode

    static let brightnessHelp =
        "Raise trace intensity when channel separation is hard to see."

    /// OpenZCine `ScopeMini` chip - mode only (`RGB` / `YRGB`), never the transfer.
    static func chip(_ mode: Mode) -> String { mode.rawValue.uppercased() }

    static func accessibilityLabel(_ mode: Mode) -> String {
        mode == .yrgb ? "YRGB parade" : "RGB parade"
    }

    /// Lane letters in draw order - YRGB prepends luma (OpenZCine `ParadeScopePlot`).
    static func laneLabels(_ mode: Mode) -> [String] {
        mode == .yrgb ? ["Y", "R", "G", "B"] : ["R", "G", "B"]
    }

    /// OpenZCine `rect.width / lanes.count`.
    static func laneWidth(mode: Mode, plot: CGRect) -> CGFloat {
        plot.width / CGFloat(mode.laneCount)
    }

    /// OpenZCine `originX + xRatio * (laneWidth - 1)`.
    static func laneX(xRatio: Double, lane: Int, mode: Mode, plot: CGRect) -> CGFloat {
        let width = laneWidth(mode: mode, plot: plot)
        let originX = plot.minX + CGFloat(lane) * width
        return originX + CGFloat(xRatio) * (width - 1)
    }

    typealias Options = MonitorParadeOptions

    /// Trace opacity at the given brightness. OpenZCine uses `/400` after a calibration
    /// pass; Pocket's shipped parade already reads at unity at 100%, so 100% stays 1.0.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

    static func panelSize(scale: Double) -> CGSize {
        MonitorScopePanelCentering.panelSize(baseSize, scale: Options.clampedScale(scale))
    }

    @MainActor
    static var store: MonitorScopePanelStore<MonitorParadeOptions> {
        MonitorScopePanelStore<MonitorParadeOptions>.shared
    }

    /// OpenZCine `AssistQuickSettingsContent.paradeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        ParadeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared parade store. `assist` is unused - parade options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> ParadeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel` id `"parade"`).
    @MainActor
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> MonitorScopeStoredPanel<Options, Content> {
        MonitorScopeStoredPanel(
            store: store, baseSize: baseSize, canvas: canvas, chromeClearance: chromeClearance,
            resizeLabel: "Resize parade", content: content)
    }
}

/// OpenZCine `AssistQuickSettingsContent.paradeRows`.
struct ParadeLongPressMenu: View {
    @Binding var options: ParadeAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu.buttonStyle(.monitorTapTarget) }

    var assistMenu: MonitorScopeTraceMenu<ParadeAssist.Mode> {
        MonitorScopeTraceMenu(
            modes: ParadeAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = ParadeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    ParadeAssistHaptics.selection(); options.brightness = next
                }), guides: $options.guides, title: { $0.rawValue },
            brightnessHelp: ParadeAssist.brightnessHelp,
            brightnessRange: ParadeAssist.brightnessRange,
            compact: compact,
            modeFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }, guideFeedback: { ParadeAssistHaptics.selection() })
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum ParadeAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
