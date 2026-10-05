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
    static let brightnessRange: ClosedRange<Int> = 0...200

    static let brightnessHelp =
        "Raise trace intensity when the waveform is hard to read in bright light."

    typealias Mode = MonitorWaveformMode

    typealias Options = MonitorWaveformOptions

    /// OpenZCine `waveformParadeBrightnessMultiplier` - 100% = former 25%.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 400
    }

    static func panelSize(scale: Double) -> CGSize {
        MonitorScopePanelCentering.panelSize(baseSize, scale: Options.clampedScale(scale))
    }

    @MainActor
    static var store: MonitorScopePanelStore<MonitorWaveformOptions> {
        MonitorScopePanelStore<MonitorWaveformOptions>.shared
    }

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
    @MainActor
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        onOpenOptions: ((CGRect) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> MonitorScopeStoredPanel<Options, Content> {
        MonitorScopeStoredPanel(
            store: store, baseSize: baseSize, canvas: canvas, chromeClearance: chromeClearance,
            resizeLabel: "Resize waveform",
            onOpenOptions: onOpenOptions, onConfirm: { WaveformAssistHaptics.confirm() }, content: content)
    }
}

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
