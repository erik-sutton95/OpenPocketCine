import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `AssistQuickSettingsContent.falseColorRows` + `FalseColorReference`.
///
/// Long-press options (OpenZCine ships exactly these):
/// * Scale — PStops / IRE / Limits
/// * Reference Display — compact color key over live view; turning it on arms False Color
enum FalseColorAssist {
    /// OpenZCine `assistPanelWidth` for tools other than guides.
    static let longPressPanelWidth: CGFloat = 400
    static let panelWidth: CGFloat = longPressPanelWidth
    /// OpenZCine `FalseColorReference.panelSize`.
    static let referencePanelSize = FalseColorReference.panelSize

    /// OpenZCine `falseColorRows` titles, in order.
    static let popupTitles = ["Scale", "Reference Display"]

    /// OpenZCine Scale help, Pocket curves in the first sentence.
    static let scaleHelp =
        "The camera color mode selects D-Log, D-Log2, Rec.709, or HLG automatically. "
        + "PStops marks minimum exposure, −3, 18% gray, skin, +2, and three clip-relative "
        + "highlight levels over luminance grayscale. IRE uses RED Video Mode-style monitor "
        + "ranges on the WAVE axis: paper black at 0, D-Log2 18% grey at 30.50, live-tap EI "
        + "ceiling at 100. Limits paints only shadow and highlight warnings, leaving other "
        + "colors untouched."

    /// OpenZCine `falseColorRows` Reference Display help.
    static let referenceHelp =
        "Show a compact color key over live view while False Color is active."

    /// OpenZCine `AssistQuickSettingsContent` Scale segments.
    static let scaleOptions = ["PStops", "IRE", "Limits"]

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

    /// OpenZCine `FalseColorScale.legendStops` labels.
    ///
    /// IRE keeps Pocket WAVE copy (`18%`, `55–61`) instead of RED Video Mode
    /// `41–48` / `61–70` — those numbers are Reinhard-mapped 18% / skin on
    /// OpenZCine's 42-IRE grey axis. LiveColorScience paints the same semantic
    /// zones at 28–34 and 52–62 on the WAVE axis.
    static func legendLabels(scale: FalseColorScaleKind) -> [String] {
        switch scale {
        case .stops:
            [
                "Minimum", "−3", "18%", "Skin +1", "+2",
                "⅔ below max", "⅓ below max", "Maximum",
            ]
        case .ire:
            [
                "0–4", "5", "10–12", "18%", "55–61", "92–93", "94–95",
                "96–98", "99–100",
            ]
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
        onReferenceEnabled: (() -> Void)? = nil
    ) -> FalseColorLongPressMenu {
        FalseColorLongPressMenu(
            options: options,
            compact: compact,
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
            onReferenceEnabled: { assist.falseColor = true }
        )
    }
}

struct FalseColorLongPressMenu: View {
    @Binding var options: FalseColorAssist.Options
    var compact: Bool = false
    var onReferenceEnabled: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: "Scale",
                help: FalseColorAssist.scaleHelp,
                showTopDivider: false,
                stacked: compact
            ) {
                SettingsSegmented(
                    options: FalseColorAssist.scaleOptions,
                    selected: FalseColorAssist.menuLabel(for: options.scale),
                    compact: compact,
                    stacked: compact
                ) { label in
                    let scale = FalseColorAssist.scale(forMenuLabel: label)
                    guard scale != options.scale else { return }
                    FalseColorAssistHaptics.selection()
                    options.scale = scale
                }
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
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
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

    struct AxisMarker: Equatable, Identifiable {
        let id: Int
        let label: String
        let fraction: Double
    }

    static let panelSize = CGSize(width: 264, height: 52)

    var scale: FalseColorScaleKind
    var transfer: MonitorTransfer

    init(scale: FalseColorScaleKind, colorMode: ColorMode = .normal) {
        self.scale = scale
        self.transfer = MonitorTransfer(colorMode)
    }

    init(scale: FalseColorScaleKind, transfer: MonitorTransfer) {
        self.scale = scale
        self.transfer = transfer
    }

    /// OpenZCine `FalseColorReference.curveKeyLabel` — Pocket transfers, compact keys.
    static func curveKeyLabel(_ transfer: MonitorTransfer) -> String {
        switch transfer {
        case .rec709: "709"
        case .hdr: "HLG"
        case .dlog: "D-Log"
        case .dlog2: "D-Log2"
        }
    }

    /// OpenZCine `FalseColorReference.axisLabels`.
    static func axisLabels(scale: FalseColorScaleKind) -> [String] {
        switch scale {
        case .stops: []
        case .ire: ["clip / shadows", "18%", "skin hi", "highlights → clip"]
        case .limits: ["crushed", "midtones untouched", "clipped"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("False Color")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(scale.referenceScaleLabel) · \(Self.curveKeyLabel(transfer))")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: neutralGradientColors,
                        startPoint: .leading,
                        endPoint: .trailing)
                    ForEach(Self.segments(scale: scale, transfer: transfer)) { segment in
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
            .frame(height: 8)
            axisView
        }
        .padding(7)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .topLeading)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
    }

    static func segments(
        scale: FalseColorScaleKind, transfer: MonitorTransfer
    ) -> [Segment] {
        let bands = PocketFalseColorMap.bands(scale: scale, transfer: transfer)
        switch scale {
        case .stops:
            let domain = stopReferenceDomain(transfer: transfer)
            return bands.enumerated().map { index, band in
                Segment(
                    id: index,
                    lowerFraction: stopFraction(
                        band.lowerBound, in: domain, infiniteFallback: 0),
                    upperFraction: stopFraction(
                        band.upperBound, in: domain, infiniteFallback: 1),
                    band: band)
            }
        case .ire, .limits:
            return bands.enumerated().map { index, band in
                Segment(
                    id: index,
                    lowerFraction: min(1, max(0, band.lowerBound / 100)),
                    upperFraction: band.upperBound.isFinite
                        ? min(1, max(0, band.upperBound / 100)) : 1,
                    band: band)
            }
        }
    }

    static func stopAxisMarkers(transfer: MonitorTransfer) -> [AxisMarker] {
        let domain = stopReferenceDomain(transfer: transfer)
        let maximum = PocketFalseColorMap.maximumSceneStop(transfer: transfer)
        let markers: [(String, Double)] = [
            ("Min", PocketFalseColorMap.minimumSceneStop),
            ("−3", -3),
            ("18%", 0),
            ("Skin", 1),
            ("+2", 2),
            ("Max", maximum),
        ]
        return markers.enumerated().map { index, marker in
            AxisMarker(
                id: index, label: marker.0,
                fraction: stopFraction(marker.1, in: domain, infiniteFallback: 0))
        }
    }

    private static func stopReferenceDomain(
        transfer: MonitorTransfer
    ) -> ClosedRange<Double> {
        let lower = PocketFalseColorMap.minimumSceneStop - 1.0 / 6
        let upper = max(6, PocketFalseColorMap.maximumSceneStop(transfer: transfer) + 1.0 / 6)
        return lower...upper
    }

    private static func stopFraction(
        _ value: Double, in domain: ClosedRange<Double>, infiniteFallback: Double
    ) -> Double {
        guard value.isFinite else { return infiniteFallback }
        return min(1, max(0, (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)))
    }

    @ViewBuilder private var axisView: some View {
        if scale == .stops {
            GeometryReader { geometry in
                ForEach(Self.stopAxisMarkers(transfer: transfer)) { marker in
                    Text(marker.label)
                        .font(.system(size: 5.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(
                            x: min(
                                geometry.size.width - 8,
                                max(8, geometry.size.width * marker.fraction)),
                            y: 3.5)
                }
            }
            .frame(height: 7)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(Self.axisLabels(scale: scale).enumerated()), id: \.offset) {
                    index, label in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(label)
                        .font(.system(size: 5.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var neutralGradientColors: [Color] {
        switch scale {
        case .stops: [Color(white: 0.04), Color(white: 0.86)]
        case .ire, .limits: [Color(white: 0.54), Color(white: 0.75)]
        }
    }
}
