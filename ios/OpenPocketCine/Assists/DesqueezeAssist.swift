import MonitorUI
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI

typealias DesqueezeRatio = MonitorDesqueezePreset

/// Local optical correction, following the same factor range as the reference monitor.
enum DesqueezeAssist {
    static let factorRange = MonitorAnamorphicDesqueeze.factorRange
    static let factorStep = MonitorAnamorphicDesqueeze.factorStep
    static let help =
        "Match your anamorphic lens or adapter. Horizontal widens the picture; Vertical "
        + "corrects a rotated adapter. The full picture fits on screen. Recordings, exports "
        + "and scope measurements stay unchanged."

    static func snap(_ value: Double) -> Double { MonitorAnamorphicDesqueeze.snap(value) }

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
    var body: some View {
        MonitorDesqueezeMenu(
            selected: assist.desqueezeCustom
                ? nil : DesqueezeRatio.matching(assist.desqueezeFactor),
            custom: assist.desqueezeCustom,
            factor: Binding(
                get: { assist.desqueezeFactor },
                set: {
                    assist.updateDesqueezeCustom($0)
                }),
            horizontal: Binding(
                get: { assist.desqueezeHorizontal },
                set: {
                    assist.desqueezeHorizontal = $0; assist.persist()
                }), help: DesqueezeAssist.help,
            selectionFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            },
            onSelect: {
                if let preset = $0 {
                    assist.selectDesqueezePreset(preset)
                } else {
                    assist.selectDesqueezeCustom()
                }
            }, onFinish: { assist.persist() })
    }
}
