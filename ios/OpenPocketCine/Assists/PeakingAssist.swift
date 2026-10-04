import MonitorUI
import OpenCineMedia
import SwiftUI
import UIKit

/// OpenZCine `Peaking` operator options + long-press rows (`AssistQuickSettingsContent.peakingRows`).
///
/// OpenZCine exposes exactly two peaking controls - there is no type / style / thickness picker:
/// * Sensitivity - Low / Med / High (`Peaking.Sensitivity`)
/// * Color - White / Blue / Red / Green (`Peaking.Color`)
///
/// Defaults match `AssistConfiguration`: red, medium. The GPU compositor reads ``overlay(from:)``.
enum PeakingAssist {
    /// OpenZCine `peakingRows` Sensitivity help.
    static let sensitivityHelp =
        "Higher sensitivity catches finer edges but can get noisy on detailed scenes."
    /// OpenZCine `peakingRows` Color help.
    static let colorHelp =
        "Choose the edge color that stays readable over your typical scene."

    typealias Color = MonitorPeakingColor
    typealias Sensitivity = MonitorPeakingSense

    /// OpenZCine `SettingsPalette.peaking` order - White / Blue / Red / Green.
    static let palette: [Color] = Color.allCases
    /// Segmented-control copy in `peakingRows`.
    static let sensitivityOptions = Sensitivity.allCases.map(\.rawValue)

    typealias Options = MonitorPeakingOptions

    /// Detector + paint values the GPU peaking pass reads (OpenZCine `PeakingSettings`).
    typealias OverlaySpec = MonitorPeakingOverlaySpec

    static func overlay(from options: Options) -> OverlaySpec { options.overlay }

    static func overlay(from effects: LiveImageEffects) -> OverlaySpec {
        OverlaySpec(color: effects.peakingColor, sensitivity: effects.peakingSensitivity)
    }

    static func overlay(color: Color, sensitivity: Sensitivity) -> OverlaySpec {
        OverlaySpec(color: color, sensitivity: sensitivity)
    }

    /// OpenZCine `AssistQuickSettingsContent.peakingRows` - Sensitivity segmented + Color dots.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> PeakingLongPressMenu {
        PeakingLongPressMenu(options: options, compact: compact)
    }

    /// Binds ``LiveAssistState`` color / sensitivity and persists on change.
    @MainActor static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> PeakingLongPressMenu {
        longPressMenu(
            options: Binding(
                get: { assist.peakingOptions },
                set: {
                    assist.peakingOptions = $0
                    assist.persist()
                }
            ),
            compact: compact
        )
    }

    @MainActor static func longPressMenu(_ assist: LiveAssistState) -> PeakingLongPressMenu {
        longPressMenu(assist: assist)
    }

    /// OpenZCine `peakingRows` Sensitivity tap - same-value is a no-op (`SettingsSegmented`).
    @MainActor
    static func selectSensitivity(_ raw: String, assist: LiveAssistState) {
        guard let level = Sensitivity(rawValue: raw),
            level != assist.peakingSensitivity
        else { return }
        assist.peakingSensitivity = level
        assist.persist()
    }

    /// OpenZCine `peakingRows` Color tap - same-value is a no-op (`SettingsColorDots`).
    @MainActor
    static func selectColor(_ raw: String, assist: LiveAssistState) {
        guard let color = Color(rawValue: raw),
            color != assist.peakingColor
        else { return }
        assist.peakingColor = color
        assist.persist()
    }

    /// OpenZCine `resetPeaking` - red / medium.
    @MainActor
    static func reset(_ assist: LiveAssistState) {
        assist.peakingOptions = .default
        assist.persist()
    }
}

extension LiveImageEffects {
    var peakingOptions: PeakingAssist.Options {
        get { PeakingAssist.Options(color: peakingColor, sensitivity: peakingSensitivity) }
        set {
            peakingColor = newValue.color
            peakingSensitivity = newValue.sensitivity
        }
    }
}

extension LiveAssistState {
    var peakingOptions: PeakingAssist.Options {
        get { PeakingAssist.Options(color: peakingColor, sensitivity: peakingSensitivity) }
        set {
            peakingColor = newValue.color
            peakingSensitivity = newValue.sensitivity
        }
    }
}

struct PeakingLongPressMenu: View {
    @Binding var options: PeakingAssist.Options
    var compact: Bool = false

    var body: some View { assistMenu }

    var assistMenu: MonitorPeakingMenu {
        MonitorPeakingMenu(
            options: $options,
            colors: PeakingAssist.palette.map {
                .init(value: $0, title: $0.rawValue, color: $0.swatch)
            }, sensitivityHelp: PeakingAssist.sensitivityHelp, colorHelp: PeakingAssist.colorHelp,
            compact: compact, feedback: { PeakingAssistHaptics.selection() })
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection` (light tap; Pocket has no haptics preference yet).
private enum PeakingAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}

// Display swatches follow this app's HDR theme; detector RGB stays portable.
extension MonitorPeakingColor {
    var swatch: SwiftUI.Color {
        switch self {
        case .white: LiveDesign.text
        case .blue: LiveHDRDisplay.chromeColor(red: 64.0 / 255, green: 142.0 / 255, blue: 1)
        case .red: LiveDesign.rec
        case .green: LiveDesign.good
        }
    }
}