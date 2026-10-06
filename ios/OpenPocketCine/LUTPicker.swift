import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// The shared LUT picker on this app's session, copy and palette; the sheet form pins this
/// app's exposure and 50/50 bar under the catalog.
struct LUTPicker: View {
    @Bindable var assist: LiveAssistState
    var embedded = false
    @Environment(AppModel.self) private var model

    var body: some View {
        LUTPickerView(
            assist: assist, embedded: embedded, context: context, copy: .app,
            palette: LiveDesign.self
        ) {
            LUTSplitComparisonBar(assist: assist)
        }
    }

    private var context: LUTPickerContext {
        LUTPickerContext(
            colorMode: model.session.status.colorMode,
            isPhoto: model.session.status.isPhoto,
            inPlayback: model.session.status.inPlayback,
            family: model.session.bodyFamily,
            cameraName: model.session.connectedCamera?.model.name,
            isWatching: model.isWatchingFeed)
    }
}

/// Input exposure still follows the native half-stop compensation path.
struct LUTExposureCompensationBar: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        SettingsInlineRow(
            title: LUTAssist.exposureTitle, help: LUTAssist.exposureHelp, showTopDivider: false,
            stacked: true
        ) {
            HStack(spacing: 9) {
                Slider(
                    value: Binding(
                        get: { assist.lutExposureStops },
                        set: { assist.nudgeLUTExposure($0 - assist.lutExposureStops) }),
                    in: -3...3, step: 0.5
                )
                .tint(MonitorTheme.accent)
                .accessibilityLabel(LUTAssist.exposureTitle)
                .accessibilityHint(LUTAssist.exposureHelp)
                Text(LUTExposureCompensation.label(assist.lutExposureStops) + " ST")
                    .font(MonitorTheme.font(11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(
                        assist.lutExposureStops == 0 ? MonitorTheme.text : MonitorTheme.accent
                    )
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .sensoryFeedback(trigger: assist.lutExposureStops) { _, _ in
            OperatorPrefs.hapticsEnabled ? .selection : nil
        }
    }
}

/// OpenZCine 50/50: off-by-default toggle; orientation chips only while armed.
/// Labels are `Left / Right` and `Top / Bottom`, not Vertical/Horizontal.
///
/// Exposure and split remain pinned beneath the catalog. Orientation choices
/// appear only while split is armed.
struct LUTSplitComparisonBar: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        MonitorInspectorCard {
            VStack(spacing: 0) {
                LUTExposureCompensationBar(assist: assist)
                SettingsSwitchInlineRow(title: "50 / 50 split", isOn: assist.splitComparison) {
                    OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                    assist.splitComparison.toggle()
                    if assist.splitComparison && !assist.lutArmed { assist.armLastLUT() }
                    assist.persist()
                }
                if assist.splitComparison {
                    SettingsSegmented(
                        options: LUTSplitOrientation.allCases.map(\.rawValue),
                        selected: LUTSplitOrientation.current(vertical: assist.splitVertical)
                            .rawValue
                    ) { raw in
                        guard let next = LUTSplitOrientation(rawValue: raw) else { return }
                        assist.splitVertical = next.isVertical
                        assist.persist()
                    }.padding(.bottom, 8)
                }
            }
        }
    }
}

/// OpenZCine `SplitComparisonOrientation` labels.
private enum LUTSplitOrientation: String, CaseIterable {
    case leftRight = "Left / Right"
    case topBottom = "Top / Bottom"

    var isVertical: Bool { self == .leftRight }

    static func current(vertical: Bool) -> LUTSplitOrientation {
        vertical ? .leftRight : .topBottom
    }
}
