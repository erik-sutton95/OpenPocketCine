import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine histogram operator options + `MovablePanel` (id `"histo"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.histogramRows`):
/// * Traffic Lights - RGB crush/clip edge blocks
/// * Crush/Clip Compensation - 0…1 stop, shared with the goal-post meter
///
/// Plot geometry is WAVE’s `WaveformAxis` - IRE 0 / 100 on the plot edges,
/// same paper-black / live-tap clip mapping as WAVE / PARADE. Crush / clip
/// lamps sit outside those strokes. No 0 / 50 / 100 labels. On the panel:
/// 0.3s long-press then drag to reposition (4pt snap,
/// 22pt haptic grid); L-corner grip long-press-drags to scale 0.6…1.6.
/// Position persists as a normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum HistogramAssist {
    static let panelID = "histo"
    static let baseSize = ScopePanelSize.histogram
    /// OpenZCine `ScopeMini` title / chip (`"Histo"` → HISTO, `"RGBL"`).
    static let panelTitle = "Histo"
    static let chip = "RGBL"
    static let plotTop: CGFloat = WaveformAxis.titleHeight
    /// OpenZCine `histogramReferenceX(95)` clip band - on WAVE’s IRE axis.
    static let clipZoneIRE = MonitorUI.MonitorHistogramGeometry.clipZoneIRE
    /// Crush / clip lamp size - must match ``HistogramScopePlot`` blocks.
    static let trafficLampWidth: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLampWidth
    static let trafficLampHeight: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLampHeight
    /// Inset from the panel edge so the top lamp clears the rounded corner.
    static let trafficOuterPad: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficOuterPad
    /// Gap between a lamp column and the 0 / 100 stroke.
    static let trafficLineGap: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLineGap

    static let trafficLightsTitle = "Traffic Lights"
    static let trafficLightsHelp =
        "Show small RGB edge blocks for crushed and clipped channels. Clip lights from about a third of a stop under the camera's clip, the same point zebra 100% and CineStop use."
    static let compensationTitle = "Crush/Clip Compensation"
    static let compensationHelp =
        "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."

    /// Side gutter that holds a lamp column outside the 0 / 100 strokes.
    static var trafficGutter: CGFloat {
        trafficOuterPad + trafficLampWidth + trafficLineGap
    }

    /// WAVE title / floor, with extra side chrome so crush sits left of 0
    /// and clip sits right of 100. IRE mapping inside the plot is ``WaveformAxis``.
    static func plotRect(in size: CGSize) -> CGRect {
        MonitorUI.MonitorHistogramGeometry.plotRect(in: size)
    }

    /// Left-to-right twin of ``WaveformAxis.plotY``.
    static func plotX(_ ire: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(ire, rect)
    }

    static func ireX(_ scaleIRE: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(scaleIRE, rect)
    }

    /// Panel-edge inset for the crush / clip columns (outside 0 / 100).
    static var trafficHorizontalInset: CGFloat { trafficOuterPad }

    typealias CrushClipCompensation = MonitorCrushClipCompensation

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorHistogramOptions

    static func panelSize(scale: Double) -> CGSize {
        MonitorScopePanelCentering.panelSize(baseSize, scale: Options.clampedScale(scale))
    }

    @MainActor
    static var store: HistogramAssistStore { HistogramAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.histogramRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        HistogramLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared histogram store. Crush/clip compensation is also written to
    /// `LiveAssistState` so LIGHTS stays on the same OpenZCine value.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        longPressMenu(
            options: Binding(
                get: { store.options },
                set: { next in
                    store.options = next
                    if let shared = TrafficLightsAssist.CrushClipCompensation(
                        rawValue: next.crushClipCompensation.rawValue)
                    {
                        assist.crushClipCompensation = shared
                    }
                }
            ),
            compact: compact
        )
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> HistogramLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> HistogramLongPressMenu {
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
            resizeLabel: "Resize histogram", content: content)
    }
}

typealias HistogramAssistStore = MonitorScopePanelStore<MonitorHistogramOptions>

/// OpenZCine `AssistQuickSettingsContent.histogramRows`.
struct HistogramLongPressMenu: View {
    @Binding var options: HistogramAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu }

    var assistMenu: MonitorHistogramMenu {
        MonitorHistogramMenu(
            trafficLights: $options.trafficLights,
            compensation: Binding(
                get: { options.crushClipCompensation },
                set: {
                    guard $0 != options.crushClipCompensation else { return }
                    HistogramAssistHaptics.selection(); options.crushClipCompensation = $0
                }), trafficHelp: HistogramAssist.trafficLightsHelp,
            compensationHelp: HistogramAssist.compensationHelp, compact: compact,
            trafficFeedback: { HistogramAssistHaptics.selection() })
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum HistogramAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
