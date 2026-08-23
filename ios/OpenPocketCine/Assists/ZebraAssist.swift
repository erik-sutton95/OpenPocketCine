import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `AssistConfiguration.Zebra` + long-press rows (`AssistQuickSettingsContent.zebraRows`).
///
/// OpenZCine exposes exactly these operator controls — there is no fill-vs-stripe / pattern picker
/// (stripes always paint the zone colour) and no extra bands beyond dual zebra:
/// * Units — 0-255 / IRE (`Zebra.Unit`; stored thresholds stay on the 0–100 monitoring axis)
/// * Highlight — enable, threshold, fill colour White / Amber / Red
/// * Midtone — enable, threshold, fill colour Amber / Cyan / Green
///
/// Defaults match `AssistConfiguration.Zebra`: IRE, highlight 100 / white, midtone 55 / amber.
/// The GPU compositor reads ``overlay(from:)``.
enum ZebraAssist {
    /// Popup width OpenZCine uses for zebra (`assistPanelWidth` — 400, not guides' 472).
    static let longPressPanelWidth: CGFloat = 400
    static let panelWidth: CGFloat = longPressPanelWidth
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

    /// OpenZCine `ImageEffectsCompositor.blendStripedZebra` — `CIStripesGenerator`.
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

    /// OpenZCine `AssistConfiguration.Zebra.StripeColor` — GPU fill lives on ``ZebraPaint``.
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
        func displayValue(for ire: Double, transfer: MonitorTransfer) -> Int {
            switch unit {
            case .ire: Int(ire.rounded())
            case .native:
                Int(
                    (ScopeDisplayScale.signalNative(monitorPercent: ire, transfer: transfer) * 255)
                        .rounded())
            }
        }

        mutating func setHighlight(fromDisplay value: Int, transfer: MonitorTransfer) {
            highlightIRE = Self.ire(fromDisplay: value, unit: unit, transfer: transfer)
        }

        mutating func setMidtone(fromDisplay value: Int, transfer: MonitorTransfer) {
            midtoneIRE = Self.ire(fromDisplay: value, unit: unit, transfer: transfer)
        }

        var editorMaximum: Int { unit == .native ? 255 : 100 }

        static func ire(fromDisplay value: Int, unit: Unit, transfer: MonitorTransfer) -> Double {
            switch unit {
            case .ire:
                min(100, max(0, Double(value)))
            case .native:
                ScopeDisplayScale.monitorPercent(
                    Double(min(max(value, 0), 255)) / 255,
                    transfer: transfer)
            }
        }
    }

    /// Zone flags + IRE + stripe fill the GPU zebra pass reads (OpenZCine `ZebraSettings` minus unit).
    /// Unit is editor-only — stored thresholds stay on the 0–100 monitoring axis.
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
    static func longPressMenu(
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

    static func longPressMenu(_ assist: LiveAssistState) -> ZebraLongPressMenu {
        longPressMenu(assist: assist)
    }
}

extension ZebraPaint: Identifiable {
    var id: String { rawValue }

    /// OpenZCine `SettingsPalette` token (not overlay RGB).
    var swatch: Color {
        switch self {
        case .white: LiveDesign.text
        case .amber: LiveDesign.amber
        case .red: LiveDesign.rec
        case .cyan: LiveDesign.info
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
        return model.session.status.monitorTransfer
            ?? model.session.status.colorMode.map(MonitorTransfer.init)
            ?? .rec709
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: ZebraAssist.unitsTitle,
                help: ZebraAssist.unitsHelp,
                showTopDivider: false,
                stacked: compact
            ) {
                SettingsSegmented(
                    options: ZebraAssist.unitOptions,
                    selected: options.unit.editorLabel,
                    compact: compact,
                    stacked: compact
                ) {
                    let unit = ZebraAssist.Unit.fromEditorLabel($0)
                    guard unit != options.unit else { return }
                    ZebraAssistHaptics.selection()
                    options.unit = unit
                }
            }
            zebraZoneRow(
                title: ZebraAssist.highlightTitle,
                help: ZebraAssist.highlightHelp,
                enabled: options.highlightEnabled,
                onEnabledToggle: {
                    ZebraAssistHaptics.selection()
                    options.highlightEnabled.toggle()
                },
                value: Binding(
                    get: { options.displayValue(for: options.highlightIRE, transfer: transfer) },
                    set: { options.setHighlight(fromDisplay: $0, transfer: transfer) }),
                colors: ZebraAssist.highlightPalette,
                selectedColor: options.highlightColor
            ) { color in
                options.highlightColor = color
            }
            zebraZoneRow(
                title: ZebraAssist.midtoneTitle,
                help: ZebraAssist.midtoneHelp,
                enabled: options.midtoneEnabled,
                onEnabledToggle: {
                    ZebraAssistHaptics.selection()
                    options.midtoneEnabled.toggle()
                },
                value: Binding(
                    get: { options.displayValue(for: options.midtoneIRE, transfer: transfer) },
                    set: { options.setMidtone(fromDisplay: $0, transfer: transfer) }),
                colors: ZebraAssist.midtonePalette,
                selectedColor: options.midtoneColor
            ) { color in
                options.midtoneColor = color
            }
        }
    }

    private func zebraZoneRow(
        title: String,
        help: String,
        enabled: Bool,
        onEnabledToggle: @escaping () -> Void,
        value: Binding<Int>,
        colors: [ZebraAssist.StripeColor],
        selectedColor: ZebraAssist.StripeColor,
        onColor: @escaping (ZebraAssist.StripeColor) -> Void
    ) -> some View {
        SettingsInlineRow(title: title, help: help, stacked: compact) {
            if compact {
                HStack(spacing: 8) {
                    enableSwitch(enabled: enabled, action: onEnabledToggle)
                    ZebraNumberField(value: value, maximum: options.editorMaximum)
                    Spacer(minLength: 4)
                    ZebraColorDots(
                        colors: colors, selected: selectedColor, compact: true, onSelect: onColor)
                }
            } else {
                HStack(spacing: 8) {
                    enableSwitch(enabled: enabled, action: onEnabledToggle)
                    ZebraNumberField(value: value, maximum: options.editorMaximum)
                    ZebraColorDots(
                        colors: colors, selected: selectedColor, compact: false, onSelect: onColor)
                }
            }
        }
    }

    private func enableSwitch(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsSwitchGraphic(isOn: enabled)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(enabled ? "On" : "Off")
    }
}

/// OpenZCine `SettingsNumberField` (`settings-num`).
private struct ZebraNumberField: View {
    @Binding var value: Int
    var maximum: Int = 100

    var body: some View {
        TextField("", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(LiveDesign.text)
            .frame(width: 44, height: 30)
            .background(
                LiveDesign.background.opacity(0.5),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .stroke(LiveDesign.hairline, lineWidth: 1)
            )
            .onChange(of: value) { _, newValue in
                value = min(max(newValue, 0), maximum)
            }
    }
}

/// OpenZCine `SettingsColorDots` + highlight / midtone palettes (token swatches, not overlay RGB).
private struct ZebraColorDots: View {
    let colors: [ZebraAssist.StripeColor]
    let selected: ZebraAssist.StripeColor
    var compact: Bool = false
    let onSelect: (ZebraAssist.StripeColor) -> Void

    private var dotDiameter: CGFloat { compact ? 15 : 13 }
    private var hitTarget: CGFloat { 44 }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(colors) { color in
                Button {
                    guard color != selected else { return }
                    ZebraAssistHaptics.selection()
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: dotDiameter, height: dotDiameter)
                        .frame(width: hitTarget, height: hitTarget)
                        .background(LiveDesign.background.opacity(0.5), in: Circle())
                        .overlay(
                            Circle().stroke(
                                color == selected ? color.swatch : LiveDesign.hairline,
                                lineWidth: color == selected ? 2 : 1))
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel(color.rawValue)
            }
        }
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection` (light tap; Pocket has no haptics preference yet).
private enum ZebraAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
