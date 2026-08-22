import OpenPocketViewCore
import SwiftUI

/// Recovery card over a held live-view frame after an established session dropped.
/// OpenZCine `MonitorRecoveryOverlay`. A camera power cycle must not throw the
/// operator back to the connect screen.
struct MonitorRecoveryOverlay: View {
    @Environment(AppModel.self) private var model

    private func showsCard(_ state: SessionRecoveryState) -> Bool {
        guard state.isRecovering else { return false }
        if case .retrying(let attempt, _) = state, attempt <= 1 {
            return model.session.sessionRecoveryCardGraceElapsed
        }
        return true
    }

    var body: some View {
        recoveryBody(model.session.sessionRecovery)
    }

    @ViewBuilder private func recoveryBody(_ state: SessionRecoveryState) -> some View {
        if showsCard(state) {
            ZStack {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                card(state: state)
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 24)
            }
            .transition(.opacity)
        }
    }

    private func card(state: SessionRecoveryState) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                statusIcon(state: state)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(SessionRecoveryCopy.title(state))
                        .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiveDesign.text)
                    Text(
                        SessionRecoveryCopy.detail(
                            state, deviceName: model.session.recoveryDeviceName)
                    )
                    .font(LiveType.ui(size: 12, weight: .medium))
                    .foregroundStyle(LiveDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                actionButton(
                    title: "Retry connection",
                    icon: .refreshCw,
                    tint: LiveDesign.accent
                ) {
                    model.session.retrySessionRecovery()
                }
                actionButton(
                    title: "Operator menu",
                    icon: .chevronLeft,
                    tint: nil
                ) {
                    model.exitMonitorToOperatorMenu()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }

    @ViewBuilder private func statusIcon(state: SessionRecoveryState) -> some View {
        switch state {
        case .retrying:
            ProgressView()
                .controlSize(.small)
                .tint(LiveDesign.accent)
        case .waitingForOperator, .pausedAfterRepeatedDrops, .idle:
            OpcIcon.unplug
                .frame(width: 20, height: 20)
                .foregroundStyle(LiveDesign.accent)
        }
    }

    private func actionButton(
        title: String,
        icon: OpcIcon,
        tint: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                icon.frame(width: 13, height: 13)
            }
            .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint == nil ? LiveDesign.text : Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .liquidGlass(in: Capsule(), tint: tint, interactive: true)
            .minTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
