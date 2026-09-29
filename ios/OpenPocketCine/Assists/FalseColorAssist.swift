import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `AssistQuickSettingsContent.falseColorRows` + `FalseColorReference`.
///
/// Long-press options:
/// * Scale: CineStop / Video / IRE / Limits
/// * Reference Display — compact color key over live view; turning it on arms False Color
enum FalseColorAssist {
    /// OpenZCine Scale help, Pocket curves in the first sentence.
    static let scaleHelp =
        "The camera color mode selects D-Log, D-Log2, D-Log M, Rec.709, or HLG automatically. "
        + "CineStop paints five stops around 18% gray, read through the "
        + "camera's log curve: dark green −2, yellow-green −1, gray at 18%, light pink +1 "
        + "(skin), soft yellow +2 (upper skin limit). Red is clipped and violet is crushed; "
        + "other shadows are flat dark gray and other highlights flat light gray. "
        + "Video paints video-level IRE stripes (green 41–48, pink 61–70, red clip) "
        + "over luminance grayscale. IRE paints six video-level zones over "
        + "luminance grayscale: purple crush, blue near-black, green 18% gray, pink one "
        + "stop over, yellow near clip, red clip. On log, Video and IRE read the camera's "
        + "Rec.709 look (709) or the raw signal (LOG), set under Read. Limits paints only shadow and highlight warnings, leaving other colors untouched."
        + " D-Log M uses a direct 0–100 signal scale. Its gray guide and CineStop "
        + "stops are Pocket 3 estimates, not calibrated sensor limits. Use IRE for signal "
        + "measurements on other D-Log M cameras."

    /// LOG / 709 row: how Video and IRE read log curves.
    static let readOptions = ["LOG", "709"]
    static let readHelp =
        "How false color reads log footage. 709 reads the camera's official Rec.709 look, "
        + "the way RED, ARRI and most monitors apply false color, so clip means clipped in "
        + "the Rec.709 image. LOG reads the raw signal like WAVE, with the full highlight "
        + "range and the camera's own clip."

    /// OpenZCine `falseColorRows` Reference Display help.
    static let referenceHelp =
        "Show a compact color key over live view while False Color is active."

    /// OpenZCine `AssistQuickSettingsContent` Scale segments.
    static let scaleOptions = ["CineStop", "Video", "IRE", "Limits"]

    struct Options: Equatable, Codable, Sendable {
        var scale: FalseColorScaleKind
        var referenceEnabled: Bool

        static let `default` = Options(scale: .sceneStops, referenceEnabled: true)
    }

    static func scale(forMenuLabel label: String) -> FalseColorScaleKind {
        switch label {
        case "Video", "PStops", "ZC Stops": .stops
        case "IRE": .ire
        case "Limits": .limits
        default: .sceneStops
        }
    }

    /// OpenZCine `falseColorScaleLabel`.
    static func menuLabel(for scale: FalseColorScaleKind) -> String {
        scale.referenceScaleLabel
    }

    /// WAVE-axis legend copy. CineStop labels come from core (see `legendStops`).
    static func legendLabels(scale: FalseColorScaleKind) -> [String] {
        switch scale {
        case .sceneStops:
            []
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
        rec709: Binding<Bool>? = nil,
        onReferenceEnabled: (() -> Void)? = nil
    ) -> FalseColorLongPressMenu {
        FalseColorLongPressMenu(
            options: options,
            compact: compact,
            transfer: transfer,
            rec709: rec709,
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
            rec709: Binding(
                get: { assist.falseColorRec709 },
                set: {
                    assist.falseColorRec709 = $0
                    assist.persist()
                }
            ),
            onReferenceEnabled: { assist.falseColor = true }
        )
    }
}

struct FalseColorLongPressMenu: View {
    @Binding var options: FalseColorAssist.Options
    var compact: Bool = false
    var transfer: MonitorTransfer = .rec709
    var rec709: Binding<Bool>? = nil
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

            if let rec709 {
                SettingsInlineRow(title: "Read", help: FalseColorAssist.readHelp, stacked: true) {
                    SettingsSegmented(
                        options: FalseColorAssist.readOptions,
                        selected: rec709.wrappedValue ? "709" : "LOG",
                        compact: compact,
                        stacked: true
                    ) { label in
                        FalseColorAssistHaptics.selection()
                        rec709.wrappedValue = label == "709"
                    }
                }
            }

            SettingsInlineRow(title: "Reference key", stacked: true) {
                FalseColorReference(
                    scale: options.scale, transfer: transfer, inspector: true,
                    rec709: rec709?.wrappedValue ?? FalseColorLogReading.rec709)
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

    struct AxisMarker: Equatable, Identifiable {
        let id: Int
        let label: String
        let fraction: Double
    }

    static let panelSize = CGSize(width: 264, height: 52)

    var scale: FalseColorScaleKind
    var transfer: MonitorTransfer
    /// Read: 709 / LOG. A view input so flipping it redraws the key.
    var rec709 = FalseColorLogReading.rec709

    init(scale: FalseColorScaleKind, colorMode: ColorMode = .normal) {
        self.scale = scale
        self.transfer = MonitorTransfer(colorMode)
    }

    init(
        scale: FalseColorScaleKind, transfer: MonitorTransfer, inspector: Bool = false,
        rec709: Bool = FalseColorLogReading.rec709
    ) {
        self.scale = scale
        self.transfer = transfer
        self.inspector = inspector
        self.rec709 = rec709
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
        case .sceneStops: []
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
                    Text(
                        "\(scale.referenceScaleLabel) · \(Self.curveKeyLabel(LiveColorScience.readsThroughLook(transfer: transfer, rec709: rec709) ? .rec709 : transfer))"
                    )
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
                    MonitorSnapshotRows(Self.segments(scale: scale, transfer: transfer, rec709: rec709)) {
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
        scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool = FalseColorLogReading.rec709
    ) -> [Segment] {
        PocketFalseColorMap.bands(scale: scale, transfer: transfer, rec709: rec709).enumerated().map {
            index, band in
            Segment(
                id: index,
                lowerFraction: fraction(
                    band.lowerBound, scale: scale, transfer: transfer, rec709: rec709,
                    infiniteFallback: 0),
                upperFraction: fraction(
                    band.upperBound, scale: scale, transfer: transfer, rec709: rec709,
                    infiniteFallback: 1),
                band: band)
        }
    }

    /// Scene stops at this curve's clip shelf, where CineStop's clip band starts.
    static func sceneStopClip(
        transfer: MonitorTransfer, rec709: Bool = FalseColorLogReading.rec709
    ) -> Double {
        let clip = LiveColorScience.falseColorClip(
            scale: .sceneStops, transfer: transfer, rec709: rec709)
        let ceiling = LiveColorScience.stops(
            encoded: LiveColorScience.clipShelf(ceiling: clip.ceiling), transfer: clip.transfer)
        return ceiling.isFinite ? ceiling : LiveColorScience.sceneStopDefaultClip
    }

    /// CineStop ruler span in scene stops: crush on the left, one stop past this
    /// curve's clip on the right, so every stop the camera records gets room.
    static func sceneStopDomain(
        transfer: MonitorTransfer, rec709: Bool = FalseColorLogReading.rec709
    ) -> ClosedRange<Double> {
        -8.5...(max(2.5, sceneStopClip(transfer: transfer, rec709: rec709)) + 1)
    }

    /// CineStop axis: every second stop from −6, stopping 1½ stops short of this
    /// curve's clip so no label collides with the clip mark, then clip.
    static func sceneStopMarkers(
        transfer: MonitorTransfer, rec709: Bool = FalseColorLogReading.rec709
    ) -> [AxisMarker] {
        let clip = sceneStopClip(transfer: transfer, rec709: rec709)
        var marks: [(String, Double)] = []
        for stop in stride(from: -6, to: clip - 1.5, by: 2) {
            marks.append((stopLabel(Int(stop)), stop))
        }
        marks.append(("clip", clip))
        return marks.enumerated().map { index, mark in
            AxisMarker(
                id: index, label: mark.0,
                fraction: fraction(
                    mark.1, scale: .sceneStops, transfer: transfer, rec709: rec709,
                    infiniteFallback: 1))
        }
    }

    private static func stopLabel(_ stop: Int) -> String {
        if stop == 0 { return "18%" }
        return stop < 0 ? "−\(-stop)" : "+\(stop)"
    }

    private static func fraction(
        _ value: Double, scale: FalseColorScaleKind, transfer: MonitorTransfer,
        rec709: Bool = FalseColorLogReading.rec709, infiniteFallback: Double
    ) -> Double {
        guard value.isFinite else { return infiniteFallback }
        guard scale.liveScale.usesSceneStops else { return min(1, max(0, value / 100)) }
        let domain = sceneStopDomain(transfer: transfer, rec709: rec709)
        return min(
            1, max(0, (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)))
    }

    @ViewBuilder private var axisView: some View {
        if scale.liveScale.usesSceneStops {
            GeometryReader { geometry in
                MonitorSnapshotRows(Self.sceneStopMarkers(transfer: transfer, rec709: rec709)) {
                    marker in
                    Text(marker.label)
                        .font(
                            inspector
                                ? MonitorTheme.font(7, weight: .medium)
                                : .system(size: 5.5, weight: .medium, design: .monospaced)
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(
                            x: min(
                                geometry.size.width - 8,
                                max(8, geometry.size.width * marker.fraction)),
                            y: inspector ? 4.5 : 3.5)
                }
            }
            .frame(height: inspector ? 9 : 7)
        } else {
            waveAxisView
        }
    }

    private var waveAxisView: some View {
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
