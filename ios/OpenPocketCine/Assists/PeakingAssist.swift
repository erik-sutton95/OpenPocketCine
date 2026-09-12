import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine `Peaking` operator options + long-press rows (`AssistQuickSettingsContent.peakingRows`).
///
/// OpenZCine exposes exactly two peaking controls — there is no type / style / thickness picker:
/// * Sensitivity — Low / Med / High (`Peaking.Sensitivity`)
/// * Color — White / Blue / Red / Green (`Peaking.Color`)
///
/// Defaults match `AssistConfiguration`: red, medium. The GPU compositor reads ``overlay(from:)``.
enum PeakingAssist {
    /// Popup width OpenZCine uses for peaking (`assistPanelWidth` — 400, not guides' 472).
    static let longPressPanelWidth: CGFloat = 400
    static let panelWidth: CGFloat = longPressPanelWidth

    /// OpenZCine `peakingRows` Sensitivity help.
    static let sensitivityHelp =
        "Higher sensitivity catches finer edges but can get noisy on detailed scenes."
    /// OpenZCine `peakingRows` Color help.
    static let colorHelp =
        "Choose the edge color that stays readable over your typical scene."

    /// OpenZCine `Peaking.Color` — GPU paint + long-press dots (`SettingsPalette.peaking`).
    enum Color: String, CaseIterable, Codable, Sendable, Identifiable {
        case white = "White"
        case blue = "Blue"
        case red = "Red"
        case green = "Green"

        var id: String { rawValue }

        /// Overlay RGB OpenZCine `Peaking.Color.rgb` paints on focused edges.
        var rgb: (Double, Double, Double) {
            switch self {
            case .white: (246.0 / 255, 241.0 / 255, 226.0 / 255)
            case .blue: (64.0 / 255, 142.0 / 255, 255.0 / 255)
            case .red: (255.0 / 255, 72.0 / 255, 64.0 / 255)
            case .green: (74.0 / 255, 220.0 / 255, 132.0 / 255)
            }
        }

        /// OpenZCine `SettingsPalette.peaking` tokens — not the overlay RGB.
        var swatch: SwiftUI.Color {
            switch self {
            case .white: LiveDesign.text
            case .blue: LiveDesign.info
            case .red: LiveDesign.rec
            case .green: LiveDesign.good
            }
        }
    }

    /// OpenZCine `Peaking.Sensitivity` — Low / Med / High detector steps.
    enum Sensitivity: String, CaseIterable, Codable, Sendable, Identifiable {
        case low = "Low"
        case medium = "Med"
        case high = "High"

        var id: String { rawValue }

        /// Two-scale ratio bar. Higher = stricter (OpenZCine `Peaking.Sensitivity.ratioThreshold`).
        var ratioThreshold: Double {
            switch self {
            case .low: 2.30
            case .medium: 2.10
            case .high: 1.90
            }
        }

        /// Coarse-operator floor in `robertsSquared` units (OpenZCine `noiseGate`).
        var noiseGate: Double {
            switch self {
            case .low: 0.00522
            case .medium: 0.00174
            case .high: 0.00058
            }
        }
    }

    /// OpenZCine `SettingsPalette.peaking` order — White / Blue / Red / Green.
    static let palette: [Color] = Color.allCases
    /// Segmented-control copy in `peakingRows`.
    static let sensitivityOptions = Sensitivity.allCases.map(\.rawValue)

    struct Options: Equatable, Codable, Sendable {
        var color: Color
        var sensitivity: Sensitivity

        static let `default` = Options(color: .red, sensitivity: .medium)

        var overlay: OverlaySpec { OverlaySpec(color: color, sensitivity: sensitivity) }
    }

    /// Detector + paint values the GPU peaking pass reads (OpenZCine `PeakingSettings`).
    struct OverlaySpec: Equatable, Sendable {
        var color: Color
        var sensitivity: Sensitivity

        var rgb: (Double, Double, Double) { color.rgb }
        var ratioThreshold: Double { sensitivity.ratioThreshold }
        var noiseGate: Double { sensitivity.noiseGate }
    }

    static func overlay(from options: Options) -> OverlaySpec { options.overlay }

    static func overlay(from effects: LiveImageEffects) -> OverlaySpec {
        OverlaySpec(color: effects.peakingColor, sensitivity: effects.peakingSensitivity)
    }

    static func overlay(color: Color, sensitivity: Sensitivity) -> OverlaySpec {
        OverlaySpec(color: color, sensitivity: sensitivity)
    }

    /// OpenZCine `AssistQuickSettingsContent.peakingRows` — Sensitivity segmented + Color dots.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> PeakingLongPressMenu {
        PeakingLongPressMenu(options: options, compact: compact)
    }

    /// Binds ``LiveAssistState`` color / sensitivity and persists on change.
    static func longPressMenu(
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

    static func longPressMenu(_ assist: LiveAssistState) -> PeakingLongPressMenu {
        longPressMenu(assist: assist)
    }

    /// OpenZCine `peakingRows` Sensitivity tap — same-value is a no-op (`SettingsSegmented`).
    @MainActor
    static func selectSensitivity(_ raw: String, assist: LiveAssistState) {
        guard let level = Sensitivity(rawValue: raw),
            level != assist.peakingSensitivity
        else { return }
        assist.peakingSensitivity = level
        assist.persist()
    }

    /// OpenZCine `peakingRows` Color tap — same-value is a no-op (`SettingsColorDots`).
    @MainActor
    static func selectColor(_ raw: String, assist: LiveAssistState) {
        guard let color = Color(rawValue: raw),
            color != assist.peakingColor
        else { return }
        assist.peakingColor = color
        assist.persist()
    }

    /// OpenZCine `resetPeaking` — red / medium.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: "Sensitivity",
                help: PeakingAssist.sensitivityHelp,
                showTopDivider: false,
                stacked: true
            ) {
                SettingsSegmented(
                    options: PeakingAssist.sensitivityOptions,
                    selected: options.sensitivity.rawValue,
                    compact: compact,
                    stacked: true
                ) {
                    guard let level = PeakingAssist.Sensitivity(rawValue: $0),
                        level != options.sensitivity
                    else { return }
                    options.sensitivity = level
                }
            }
            SettingsInlineRow(
                title: "Color",
                help: PeakingAssist.colorHelp,
                stacked: compact
            ) {
                PeakingColorDots(
                    selected: options.color,
                    compact: compact
                ) { color in
                    guard color != options.color else { return }
                    PeakingAssistHaptics.selection()
                    options.color = color
                }
            }
        }
    }
}

/// OpenZCine `SettingsColorDots` + `SettingsPalette.peaking` (token swatches, not overlay RGB).
private struct PeakingColorDots: View {
    let selected: PeakingAssist.Color
    var compact: Bool = false
    let onSelect: (PeakingAssist.Color) -> Void

    private var dotDiameter: CGFloat { compact ? 15 : 13 }
    private var hitTarget: CGFloat { 44 }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            MonitorSnapshotRows(PeakingAssist.palette) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: dotDiameter, height: dotDiameter)
                        .frame(width: 36, height: 36)
                        .background(LiveDesign.background.opacity(0.5), in: Circle())
                        .overlay(
                            Circle().stroke(
                                color == selected ? color.swatch : LiveDesign.hairline,
                                lineWidth: color == selected ? 2 : 1)
                        )
                        .frame(width: hitTarget, height: hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel(color.rawValue)
            }
        }
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection` (light tap; Pocket has no haptics preference yet).
private enum PeakingAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
