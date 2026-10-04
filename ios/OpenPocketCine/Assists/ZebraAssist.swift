import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `AssistConfiguration.Zebra` + long-press rows (`AssistQuickSettingsContent.zebraRows`).
///
/// OpenZCine exposes exactly these operator controls - there is no fill-vs-stripe / pattern picker
/// (stripes always paint the zone colour) and no extra bands beyond dual zebra:
/// * Units - 0-255 / IRE (`Zebra.Unit`; stored thresholds stay on the 0–100 monitoring axis)
/// * Highlight - enable, threshold, fill colour White / Amber / Red
/// * Midtone - enable, threshold, fill colour Amber / Cyan / Green
///
/// Defaults follow `AssistConfiguration.Zebra` (IRE, white / amber, midtone 55) except highlight:
/// 99, one IRE under the live-tap ceiling so the typical D-Log2 243–247 shelf paints (#136).
/// The GPU compositor reads ``overlay(from:)``.
enum ZebraAssist {
    static let unitDefaultsKey = "OpenPocketCine.zebraUnit"

    /// OpenZCine `zebraRows` / `SettingsSegmented` labels.
    static let unitOptions = ["0-255", "IRE"]
    static let unitsTitle = "Units"
    static let unitsHelp =
        "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale."
    static let highlightTitle = "Highlight"
    static let highlightHelp =
        "High zebra warns when bright detail approaches clipping after the active log curve is compensated."
    static let midtoneTitle = "Midtone"
    static let midtoneHelp =
        "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure."

    /// OpenZCine `ImageEffectsCompositor.blendStripedZebra` - `CIStripesGenerator`.
    enum StripeLook {
        static let width: CGFloat = 5
        static let sharpness: CGFloat = 1
        static let rotation: CGFloat = .pi / 4
    }

    static var persistedUnit: Unit {
        get { Unit(rawValue: UserDefaults.standard.string(forKey: unitDefaultsKey) ?? "") ?? .ire }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: unitDefaultsKey) }
    }

    /// OpenZCine `AssistConfiguration.Zebra.Unit`. Editor labels are `0-255` / `IRE`.
    enum Unit: String, CaseIterable, Codable, Sendable, Identifiable {
        case native = "Native"
        case ire = "IRE"

        var id: String { rawValue }

        /// Segmented-control copy in `zebraRows`.
        var editorLabel: String {
            switch self {
            case .native: "0-255"
            case .ire: "IRE"
            }
        }

        static func fromEditorLabel(_ label: String) -> Unit {
            label == "0-255" ? .native : .ire
        }
    }

    /// OpenZCine `AssistConfiguration.Zebra.StripeColor` - GPU fill lives on ``ZebraPaint``.
    typealias StripeColor = ZebraPaint

    /// OpenZCine `SettingsPalette.highlight`.
    static let highlightPalette: [StripeColor] = [.white, .amber, .red]
    /// OpenZCine `SettingsPalette.midtone`.
    static let midtonePalette: [StripeColor] = [.amber, .cyan, .green]

    struct Options: Equatable, Codable, Sendable {
        var unit: Unit
        var highlightEnabled: Bool
        var highlightIRE: Double
        var highlightColor: StripeColor
        var midtoneEnabled: Bool
        var midtoneIRE: Double
        var midtoneColor: StripeColor

        static let `default` = Options(
            unit: .ire,
            highlightEnabled: true,
            highlightIRE: LiveZebra.highlightIRE,
            highlightColor: .white,
            midtoneEnabled: true,
            midtoneIRE: LiveZebra.midtoneIRE,
            midtoneColor: .amber
        )

        init(
            unit: Unit = .ire,
            highlightEnabled: Bool = true,
            highlightIRE: Double = LiveZebra.highlightIRE,
            highlightColor: StripeColor = .white,
            midtoneEnabled: Bool = true,
            midtoneIRE: Double = LiveZebra.midtoneIRE,
            midtoneColor: StripeColor = .amber
        ) {
            self.unit = unit
            self.highlightEnabled = highlightEnabled
            self.highlightIRE = highlightIRE
            self.highlightColor = highlightColor
            self.midtoneEnabled = midtoneEnabled
            self.midtoneIRE = midtoneIRE
            self.midtoneColor = midtoneColor
        }

        var overlay: OverlaySpec {
            OverlaySpec(
                highlightEnabled: highlightEnabled,
                highlightIRE: highlightIRE,
                highlightColor: highlightColor,
                midtoneEnabled: midtoneEnabled,
                midtoneIRE: midtoneIRE,
                midtoneColor: midtoneColor
            )
        }

        /// Operator-facing threshold, honouring ``unit`` (OpenZCine `Zebra.displayValue`).
        /// `clipByte` is the monitored source's live ceiling for `transfer`.
        func displayValue(for ire: Double, transfer: MonitorTransfer, clipByte: Int) -> Int {
            switch unit {
            case .ire: Int(ire.rounded())
            case .native:
                Int(
                    (ScopeDisplayScale.signalNative(
                        monitorPercent: ire, transfer: transfer, clipByte: clipByte) * 255)
                        .rounded())
            }
        }

        mutating func setHighlight(fromDisplay value: Int, transfer: MonitorTransfer, clipByte: Int)
        {
            highlightIRE = Self.ire(
                fromDisplay: value, unit: unit, transfer: transfer, clipByte: clipByte)
        }

        mutating func setMidtone(fromDisplay value: Int, transfer: MonitorTransfer, clipByte: Int) {
            midtoneIRE = Self.ire(
                fromDisplay: value, unit: unit, transfer: transfer, clipByte: clipByte)
        }

        var editorMaximum: Int { unit == .native ? 255 : 100 }

        static func ire(
            fromDisplay value: Int, unit: Unit, transfer: MonitorTransfer, clipByte: Int
        ) -> Double {
            switch unit {
            case .ire:
                min(100, max(0, Double(value)))
            case .native:
                ScopeDisplayScale.monitorPercent(
                    Double(min(max(value, 0), 255)) / 255,
                    transfer: transfer, clipByte: clipByte)
            }
        }
    }

    /// Zone flags + IRE + stripe fill the GPU zebra pass reads (OpenZCine `ZebraSettings` minus unit).
    /// Unit is editor-only - stored thresholds stay on the 0–100 monitoring axis.
    struct OverlaySpec: Equatable, Sendable {
        var highlightEnabled: Bool
        var highlightIRE: Double
        var highlightColor: StripeColor
        var midtoneEnabled: Bool
        var midtoneIRE: Double
        var midtoneColor: StripeColor
    }

    static func overlay(from options: Options) -> OverlaySpec { options.overlay }

    static func overlay(from effects: LiveImageEffects) -> OverlaySpec {
        OverlaySpec(
            highlightEnabled: effects.zebraHighlight,
            highlightIRE: effects.zebraHighlightIRE,
            highlightColor: effects.zebraHighlightColor,
            midtoneEnabled: effects.zebraMidtone,
            midtoneIRE: effects.zebraMidtoneIRE,
            midtoneColor: effects.zebraMidtoneColor
        )
    }

    /// OpenZCine `AssistQuickSettingsContent.zebraRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> ZebraLongPressMenu {
        ZebraLongPressMenu(options: options, compact: compact)
    }

    /// Binds ``LiveAssistState`` dual-zebra options and persists on change.
    @MainActor static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> ZebraLongPressMenu {
        longPressMenu(
            options: Binding(
                get: { assist.zebraOptions },
                set: {
                    assist.zebraOptions = $0
                    assist.persist()
                }
            ),
            compact: compact
        )
    }

    @MainActor static func longPressMenu(_ assist: LiveAssistState) -> ZebraLongPressMenu {
        longPressMenu(assist: assist)
    }
}

extension ZebraPaint {
    /// OpenZCine `SettingsPalette` token (not overlay RGB).
    var swatch: Color {
        switch self {
        case .white: LiveDesign.text
        case .amber: LiveDesign.amber
        case .red: LiveDesign.rec
        case .cyan: LiveHDRDisplay.chromeColor(red: 0, green: 0.85, blue: 0.9)
        case .green: LiveDesign.good
        }
    }
}

extension LiveImageEffects {
    var zebraOptions: ZebraAssist.Options {
        get {
            ZebraAssist.Options(
                highlightEnabled: zebraHighlight,
                highlightIRE: zebraHighlightIRE,
                highlightColor: zebraHighlightColor,
                midtoneEnabled: zebraMidtone,
                midtoneIRE: zebraMidtoneIRE,
                midtoneColor: zebraMidtoneColor
            )
        }
        set {
            zebraHighlight = newValue.highlightEnabled
            zebraHighlightIRE = newValue.highlightIRE
            zebraHighlightColor = newValue.highlightColor
            zebraMidtone = newValue.midtoneEnabled
            zebraMidtoneIRE = newValue.midtoneIRE
            zebraMidtoneColor = newValue.midtoneColor
        }
    }
}

extension LiveAssistState {
    /// Editor-only; stored beside the assist snapshot so concurrent LiveAssists edits cannot drop it.
    var zebraUnit: ZebraAssist.Unit {
        get { ZebraAssist.persistedUnit }
        set { ZebraAssist.persistedUnit = newValue }
    }

    var zebraOptions: ZebraAssist.Options {
        get {
            ZebraAssist.Options(
                unit: zebraUnit,
                highlightEnabled: zebraHighlight,
                highlightIRE: zebraHighlightIRE,
                highlightColor: zebraHighlightColor,
                midtoneEnabled: zebraMidtone,
                midtoneIRE: zebraMidtoneIRE,
                midtoneColor: zebraMidtoneColor
            )
        }
        set {
            zebraUnit = newValue.unit
            zebraHighlight = newValue.highlightEnabled
            zebraHighlightIRE = newValue.highlightIRE
            zebraHighlightColor = newValue.highlightColor
            zebraMidtone = newValue.midtoneEnabled
            zebraMidtoneIRE = newValue.midtoneIRE
            zebraMidtoneColor = newValue.midtoneColor
        }
    }
}

struct ZebraLongPressMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var options: ZebraAssist.Options
    var compact: Bool = false

    private var transfer: MonitorTransfer {
        return model.monitorTransfer
            ?? model.monitorColorMode.map(MonitorTransfer.init)
            ?? .rec709
    }

    /// The monitored source's own live ceiling (STATE-01: never a process-wide one).
    private var clipByte: Int {
        model.monitorSamples.exposureCeiling.clipByte(transfer: transfer)
    }

    var body: some View { assistMenu(transfer: transfer, clipByte: clipByte) }

    func assistMenu(transfer: MonitorTransfer, clipByte: Int) -> MonitorZebraMenu<
        ZebraAssist.Unit, ZebraAssist.StripeColor
    > {
        MonitorZebraMenu(
            units: ZebraAssist.Unit.allCases, unit: $options.unit, title: { $0.editorLabel },
            unitsTitle: ZebraAssist.unitsTitle, unitsHelp: ZebraAssist.unitsHelp,
            highlightHelp: ZebraAssist.highlightHelp, midtoneHelp: ZebraAssist.midtoneHelp,
            highlight: zone(
                enabled: $options.highlightEnabled, threshold: $options.highlightIRE,
                colors: ZebraAssist.highlightPalette, paint: $options.highlightColor,
                transfer: transfer, clipByte: clipByte),
            midtone: zone(
                enabled: $options.midtoneEnabled, threshold: $options.midtoneIRE,
                colors: ZebraAssist.midtonePalette, paint: $options.midtoneColor,
                transfer: transfer, clipByte: clipByte), compact: compact,
            selectionFeedback: { ZebraAssistHaptics.selection() },
            toggleFeedback: {
                ZebraAssistHaptics.selection(); ZebraAssistHaptics.selection()
            })
    }
    private func zone(
        enabled: Binding<Bool>, threshold: Binding<Double>, colors: [ZebraAssist.StripeColor],
        paint: Binding<ZebraAssist.StripeColor>, transfer: MonitorTransfer, clipByte: Int
    ) -> MonitorZebraZone<ZebraAssist.StripeColor> {
        MonitorZebraZone(
            enabled: enabled,
            threshold: Binding(
                get: { threshold.wrappedValue },
                set: {
                    threshold.wrappedValue = min(100, max(0, $0))
                }),
            displayValue: options.displayValue(
                for: threshold.wrappedValue, transfer: transfer, clipByte: clipByte),
            colors: colors.map { .init(value: $0, title: $0.rawValue, color: $0.swatch) },
            paint: paint)
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection` (light tap; Pocket has no haptics preference yet).
private enum ZebraAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
