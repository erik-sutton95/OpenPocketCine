import MonitorUI
import OpenPocketViewCore
import SwiftUI

private enum GimbalSettingsTab: String, CaseIterable {
    case mode = "Mode"
    case speed = "Speed"
    case ramp = "Ramp"
}

/// Trailing gimbal pane: Mode / Speed / Ramp tabs, one drum per tab, motion
/// control footer. Actions stay on the session; this file is presentation only.
struct LiveGimbalSheetHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.scenePhase) private var scenePhase
    var layout: LiveMonitorLayout
    var cluster: GimbalCluster
    @State private var tab = GimbalSettingsTab.mode
    @State private var appeared = false
    @State private var interactionRevision: UInt64 = 0

    private struct Context: Hashable {
        let cameraID: UUID?
        let phase: String
        let tab: GimbalSettingsTab
        let revision: UInt64
        let enabled: Bool
    }

    /// Opening the floating editor is presentation only. Mode / speed / ramp
    /// drums still require a SET-capable live datalink, matching Android's sheet.
    private var canPresentEditor: Bool {
        appeared && scenePhase == .active && model.liveGimbalPanel == .sheet
            && !interfaceLocked && !model.isEditingChrome && model.liveChromeInteractive
    }

    private var canApply: Bool {
        canPresentEditor && model.session.canSetGimbalConfiguration
    }

    private var interactionContext: Context {
        Context(
            cameraID: model.session.connectedCamera?.id, phase: model.session.phase.label,
            tab: tab, revision: interactionRevision, enabled: canApply)
    }

    var body: some View {
        let _ = cluster
        MonitorInspector(
            title: LiveGimbalCopy.title, viewport: layout.viewport,
            safeArea: layout.safeArea, trailing: true, hasNavigation: false,
            preferredWidth: .assist
        ) {
            model.liveGimbalPanel = .none
        } navigation: {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                MonitorSegmentedControl(
                    options: GimbalSettingsTab.allCases,
                    selection: $tab,
                    title: { $0.rawValue },
                    onSelectionFeedback: {
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                    }
                )
                .environment(\.monitorSegmentedAppearance, .inspector)

                MonitorInspectorCard {
                    switch tab {
                    case .mode:
                        drum(
                            GimbalMode.pickerOrder, selected: model.session.gimbalMode,
                            title: { $0.label }, select: model.setGimbalMode)
                    case .speed:
                        drum(
                            GimbalSpeed.pickerOrder, selected: model.session.gimbalSpeed,
                            title: { $0.label }, select: model.session.setGimbalSpeed)
                    case .ramp:
                        drum(
                            GimbalRamp.pickerOrder, selected: model.gimbalRamp,
                            title: { $0.label }, select: { model.gimbalRamp = $0 })
                    }
                }
            }
        } footer: {
            Button {
                guard canPresentEditor else { return }
                model.liveGimbalPanel = .editor
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LiveGimbalCopy.programmedMove).font(
                            MonitorTheme.font(11, weight: .semibold))
                        Text("Experimental").font(MonitorTheme.font(9)).foregroundStyle(
                            MonitorTheme.muted)
                    }
                    Spacer(minLength: 2)
                    MonitorIcon.chevronRight.frame(width: 11, height: 11)
                }
                .foregroundStyle(MonitorTheme.secondary).padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(MonitorButtonStyle())
                .accessibilityIdentifier("motion.openEditor")
        }
        .onAppear { appeared = true }
        .onDisappear {
            appeared = false
            interactionRevision &+= 1
        }
        .onChange(of: tab) { _, _ in interactionRevision &+= 1 }
        .onChange(of: model.session.connectedCamera?.id) { _, _ in interactionRevision &+= 1 }
        .onChange(of: model.session.phase.label) { _, _ in interactionRevision &+= 1 }
        .onChange(of: canApply) { _, _ in interactionRevision &+= 1 }
    }

    private func drum<T: Equatable>(
        _ options: [T], selected: T,
        title: @escaping (T) -> String, select: @escaping (T) -> Void
    ) -> some View {
        let context = interactionContext
        return MonitorValueDrum(
            options: options.map(title),
            selection: Binding(
                get: { title(selected) },
                set: { value in
                    guard canApply, context == interactionContext else { return }
                    if let item = options.first(where: { title($0) == value }) { select(item) }
                }),
            isInteractive: canApply, haptics: model.hapticsEnabled,
            interactionIdentity: { AnyHashable(interactionContext) })
    }
}
