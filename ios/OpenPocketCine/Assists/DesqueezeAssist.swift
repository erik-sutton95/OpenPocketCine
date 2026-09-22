import MonitorUI
import OpenPocketViewCore
import SwiftUI

enum DesqueezeRatio: String, CaseIterable, Codable {
    case x11 = "1.1×"
    case x12 = "1.2×"
    case x133 = "1.33×"
    case x15 = "1.5×"
    case x16 = "1.6×"
    case x18 = "1.8×"
    case x2 = "2.0×"

    var factor: Double { Double(rawValue.dropLast()) ?? 1.33 }

    static func matching(_ factor: Double) -> DesqueezeRatio? {
        allCases.first { abs($0.factor - factor) < 0.005 }
    }
}

/// Local optical correction, following the same factor range as the reference monitor.
enum DesqueezeAssist {
    static let factorRange = 1.0...2.0
    static let factorStep = 0.01
    static let help =
        "Match your anamorphic lens or adapter. Horizontal widens the picture; Vertical "
        + "corrects a rotated adapter. The full picture fits on screen. Recordings, exports "
        + "and scope measurements stay unchanged."

    static func snap(_ value: Double) -> Double {
        guard value.isFinite else { return 1.33 }
        return (min(2, max(1, value)) * 100 + 0.000_000_1).rounded() / 100
    }

    static func presentationRect(
        sourceSize: CGSize, in container: CGRect, effects: LiveImageEffects
    ) -> CGRect {
        let factor = snap(effects.desqueezeFactor)
        let corrected = CGSize(
            width: sourceSize.width * (effects.desqueezeHorizontal ? factor : 1),
            height: sourceSize.height * (effects.desqueezeHorizontal ? 1 : factor))
        return PlaybackVideoLayout.aspectFitRect(videoSize: corrected, in: container)
    }

    static func longPressMenu(assist: LiveAssistState) -> some View {
        DesqueezeLongPressMenu(assist: assist)
    }
}

extension LiveAssistState {
    func selectDesqueezePreset(_ preset: DesqueezeRatio) {
        desqueezeCustom = false
        desqueezeFactor = preset.factor
        persist()
    }

    func selectDesqueezeCustom() {
        desqueezeCustom = true
        desqueezeFactor = DesqueezeAssist.snap(desqueezeCustomFactor)
        persist()
    }

    func updateDesqueezeCustom(_ value: Double) {
        desqueezeCustom = true
        desqueezeCustomFactor = DesqueezeAssist.snap(value)
        desqueezeFactor = desqueezeCustomFactor
    }
}

struct DesqueezeLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    private var selected: String {
        assist.desqueezeCustom
            ? "Custom" : DesqueezeRatio.matching(assist.desqueezeFactor)?.rawValue ?? "Custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: "Squeeze factor", help: DesqueezeAssist.help,
                showTopDivider: false, stacked: true
            ) {
                VStack(spacing: 6) {
                    choices(Array(DesqueezeRatio.allCases.prefix(4)).map(\.rawValue))
                    choices(Array(DesqueezeRatio.allCases.suffix(3)).map(\.rawValue) + ["Custom"])
                }
            }
            if assist.desqueezeCustom {
                SettingsInlineRow(
                    title: "Custom", help: "Adjust from 1.00× to 2.00× in 0.01 steps.",
                    stacked: true
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(String(format: "%.2f×", assist.desqueezeFactor))
                            .font(LiveType.ui(size: 13, weight: .semibold, design: .monospaced))
                            .accessibilityIdentifier("desqueeze.factor")
                        Slider(
                            value: Binding(
                                get: { assist.desqueezeFactor },
                                set: { assist.updateDesqueezeCustom($0) }),
                            in: DesqueezeAssist.factorRange, step: DesqueezeAssist.factorStep
                        ) { editing in
                            if !editing { assist.persist() }
                        }
                        .tint(LiveDesign.accent)
                        .accessibilityLabel("Custom squeeze factor")
                        .accessibilityValue(String(format: "%.2f×", assist.desqueezeFactor))
                    }
                }
            }
            SettingsInlineRow(
                title: "Direction", help: "Choose the squeeze direction of your lens or adapter.",
                stacked: true
            ) {
                SettingsSegmented(
                    options: ["Horizontal", "Vertical"],
                    selected: assist.desqueezeHorizontal ? "Horizontal" : "Vertical", stacked: true
                ) {
                    assist.desqueezeHorizontal = $0 == "Horizontal"
                    assist.persist()
                }
            }
        }
        .onDisappear { assist.persist() }
    }

    private func choices(_ options: [String]) -> some View {
        SettingsSegmented(options: options, selected: selected, stacked: true) { value in
            if let preset = DesqueezeRatio(rawValue: value) {
                assist.selectDesqueezePreset(preset)
            } else {
                assist.selectDesqueezeCustom()
            }
        }
    }
}
