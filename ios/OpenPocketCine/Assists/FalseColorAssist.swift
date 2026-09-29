import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `AssistQuickSettingsContent.falseColorRows` + `FalseColorReference`.
///
/// Long-press options:
/// * Scale — CineStop / IRE / Limits
/// * Reference Display — compact color key over live view; turning it on arms False Color
enum FalseColorAssist {
    /// OpenZCine Scale help, Pocket curves in the first sentence.
    static let scaleHelp =
        "The camera color mode selects D-Log, D-Log2, D-Log M, Rec.709, or HLG automatically. "
        + "CineStop paints video-level IRE stripes (green 41–48, pink 61–70, red clip) "
        + "over luminance grayscale. IRE paints six video-level zones over "
        + "luminance grayscale: purple crush, blue near-black, green 18% gray, pink one "
        + "stop over, yellow near clip, red clip. Limits paints only shadow and "
        + "highlight warnings, leaving other colors untouched."
        + " D-Log M uses a direct 0–100 signal scale. Its gray guide is a "
        + "Pocket 3 estimate, not a calibrated sensor limit. Use IRE for signal "
        + "measurements on other D-Log M cameras."

    /// OpenZCine `falseColorRows` Reference Display help.
    static let referenceHelp =
        "Show a compact color key over live view while False Color is active."

    /// OpenZCine `AssistQuickSettingsContent` Scale segments.
    static let scaleOptions = ["CineStop", "IRE", "Limits"]

    struct Options: Equatable, Codable, Sendable {
        var scale: FalseColorScaleKind
        var referenceEnabled: Bool

        static let `default` = Options(scale: .stops, referenceEnabled: true)
    }

    static func scale(forMenuLabel label: String) -> FalseColorScaleKind {
        switch label {
        case "IRE": .ire
        case "Limits": .limits
        default: .stops
        }
    }

    /// OpenZCine `falseColorScaleLabel`.
    static func menuLabel(for scale: FalseColorScaleKind) -> String {
        scale.referenceScaleLabel
    }

    static func legendLabels(scale: FalseColorScaleKind) -> [String] {
        switch scale {
        case .stops:
            [
                "0–4", "5", "10–12", "41–48", "61–70", "92–93", "94–95",
                "96–98", "99–100",
            ]
        case .ire:
            ["BDL", "NBDL", "18%MG", "MG+1", "80%WC", "95%WC"]
        case .limits:
            ["0–4", "5–9", "94–98", "99–100"]
        }
    }

    static func legendBands(
        scale: FalseColorScaleKind, transfer: MonitorTransfer
    ) -> [LiveFalseColorBand] {
        scale.legendStops(transfer: transfer)
    }

    /// OpenZCine `AssistQuickSettingsContent.falseColorRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false,
        transfer: MonitorTransfer = .rec709,
        onReferenceEnabled: (() -> Void)? = nil
    ) -> FalseColorLongPressMenu {
        FalseColorLongPressMenu(
            options: options,
            compact: compact,
            transfer: transfer,
            onReferenceEnabled: onReferenceEnabled
        )
    }

    /// Binds ``LiveAssistState`` scale / reference and persists on change.
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> some View {
        FalseColorAssistMenuHost(assist: assist, compact: compact)
    }

    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        longPressMenu(assist: assist)
    }

    /// OpenZCine `FalseColorReference` — 264×52 glass ruler with sparse zone chips.
    static func referenceDisplay(
        scale: FalseColorScaleKind, colorMode: ColorMode = .normal
    ) -> FalseColorReference {
        FalseColorReference(scale: scale, colorMode: colorMode)
    }

    @MainActor
    static func selectScale(_ label: String, assist: LiveAssistState) {
        assist.falseColorScale = scale(forMenuLabel: label)
        assist.persist()
        if assist.falseColor {
            PocketFalseColorMap.warm(
                scale: assist.falseColorScale,
                mode: assist.monitorColorMode ?? .normal,
                hasLUT: assist.effects.lutDimension >= 2)
        }
    }

    /// OpenZCine: turning Reference Display on also arms False Color.
    @MainActor
    static func toggleReference(assist: LiveAssistState) {
        assist.falseColorReference.toggle()
        if assist.falseColorReference {
            assist.falseColor = true
        }
        assist.persist()
    }
}

extension LiveAssistState {
    var falseColorOptions: FalseColorAssist.Options {
        get {
            FalseColorAssist.Options(
                scale: falseColorScale, referenceEnabled: falseColorReference)
        }
        set {
            falseColorScale = newValue.scale
            falseColorReference = newValue.referenceEnabled
        }
    }
}

extension LiveImageEffects {
    var falseColorOptions: FalseColorAssist.Options {
        get {
            FalseColorAssist.Options(scale: falseColorScale, referenceEnabled: false)
        }
        set { falseColorScale = newValue.scale }
    }
}

// MARK: - Long-press rows

private struct FalseColorAssistMenuHost: View {
    @Bindable var assist: LiveAssistState
    var compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        FalseColorAssist.longPressMenu(
            options: Binding(
                get: { assist.falseColorOptions },
                set: {
                    assist.falseColorOptions = $0
                    assist.persist()
                }
            ),
            compact: compact,
            transfer: model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init)
                ?? .rec709,
            onReferenceEnabled: { assist.falseColor = true }
        )
    }
}

struct FalseColorLongPressMenu: View {
    @Binding var options: FalseColorAssist.Options
    var compact: Bool = false
    var transfer: MonitorTransfer = .rec709
    var onReferenceEnabled: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: "Scale",
                help: FalseColorAssist.scaleHelp,
                showTopDivider: false,
                stacked: true
            ) {
                SettingsSegmented(
                    options: FalseColorAssist.scaleOptions,
                    selected: FalseColorAssist.menuLabel(for: options.scale),
                    compact: compact,
                    stacked: true
                ) { label in
                    let scale = FalseColorAssist.scale(forMenuLabel: label)
                    guard scale != options.scale else { return }
                    options.scale = scale
                }
            }

            SettingsInlineRow(title: "Reference key", stacked: true) {
                FalseColorReference(scale: options.scale, transfer: transfer, inspector: true)
                    .accessibilityLabel("False color reference key")
            }

            SettingsSwitchInlineRow(
                title: "Reference Display",
                help: FalseColorAssist.referenceHelp,
                stacked: compact,
                isOn: options.referenceEnabled
            ) {
                FalseColorAssistHaptics.selection()
                options.referenceEnabled.toggle()
                if options.referenceEnabled {
                    onReferenceEnabled?()
                }
            }
        }
    }
}

private enum FalseColorAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}

// MARK: - On-feed reference ruler (OpenZCine `FalseColorReference`)

/// OpenZCine `FalseColorReference` — 264×52 glass ruler with proportional zone chips.
struct FalseColorReference: View {
    struct Segment: Equatable, Identifiable {
        let id: Int
        let lowerFraction: Double
        let upperFraction: Double
        let band: LiveFalseColorBand
    }

    static let panelSize = CGSize(width: 264, height: 52)

    var scale: FalseColorScaleKind
    var transfer: MonitorTransfer

    init(scale: FalseColorScaleKind, colorMode: ColorMode = .normal) {
        self.scale = scale
        self.transfer = MonitorTransfer(colorMode)
    }

    init(scale: FalseColorScaleKind, transfer: MonitorTransfer, inspector: Bool = false) {
        self.scale = scale
        self.transfer = transfer
        self.inspector = inspector
    }

    /// OpenZCine `FalseColorReference.curveKeyLabel` — Pocket transfers, compact keys.
    static func curveKeyLabel(_ transfer: MonitorTransfer) -> String {
        switch transfer {
        case .rec709: "709"
        case .hdr: "HLG"
        case .dlog: "D-Log"
        case .dlogm: "DLM ≈"
        case .dlog2: "D-Log2"
        }
    }

    /// OpenZCine `FalseColorReference.axisLabels`.
    static func axisLabels(scale: FalseColorScaleKind) -> [String] {
        switch scale {
        case .stops, .ire: ["crush", "18%", "skin", "clip"]
        case .limits: ["crushed", "midtones untouched", "clipped"]
        }
    }

    var inspector = false

    var body: some View {
        Group {
            if inspector {
                referenceContent.frame(height: 26)
            } else {
                referenceContent
                    .padding(7)
                    .frame(
                        width: Self.panelSize.width, height: Self.panelSize.height,
                        alignment: .topLeading
                    )
                    .liveChromeGlass(
                        in: RoundedRectangle(
                            cornerRadius: LiveDesign.cornerRadius, style: .continuous))
            }
        }
    }

    private var referenceContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !inspector {
                HStack {
                    Text("False Color")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    Spacer()
                    Text("\(scale.referenceScaleLabel) · \(Self.curveKeyLabel(transfer))")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: neutralGradientColors,
                        startPoint: .leading,
                        endPoint: .trailing)
                    MonitorSnapshotRows(Self.segments(scale: scale, transfer: transfer)) {
                        segment in
                        Rectangle()
                            .fill(
                                Color(
                                    red: segment.band.red,
                                    green: segment.band.green,
                                    blue: segment.band.blue)
                            )
                            .frame(
                                width: max(
                                    1,
                                    geometry.size.width
                                        * (segment.upperFraction - segment.lowerFraction))
                            )
                            .offset(x: geometry.size.width * segment.lowerFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .frame(height: inspector ? 14 : 8)
            axisView
        }
    }

    static func segments(
        scale: FalseColorScaleKind, transfer: MonitorTransfer
    ) -> [Segment] {
        PocketFalseColorMap.bands(scale: scale, transfer: transfer).enumerated().map {
            index, band in
            Segment(
                id: index,
                lowerFraction: min(1, max(0, band.lowerBound / 100)),
                upperFraction: band.upperBound.isFinite
                    ? min(1, max(0, band.upperBound / 100)) : 1,
                band: band)
        }
    }

    private var axisView: some View {
        HStack(spacing: 4) {
            MonitorSnapshotRows(Array(Self.axisLabels(scale: scale).enumerated()), id: \.offset)
            {
                index, label in
                if index > 0 { Spacer(minLength: 0) }
                Text(label)
                    .font(
                        inspector
                            ? MonitorTheme.font(7, weight: .medium)
                            : .system(size: 5.5, weight: .medium, design: .monospaced)
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var neutralGradientColors: [Color] {
        [Color(white: 0.54), Color(white: 0.75)]
    }
}
