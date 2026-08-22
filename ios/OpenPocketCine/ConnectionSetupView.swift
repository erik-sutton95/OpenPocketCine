import OpenPocketViewCore
import SwiftUI

/// OSMO first-pair wizard: BLE scan → tap camera → Approve on Pocket → join Wi-Fi → datalink.
/// Visual clone of OpenZCine `StartupFirstPairWizardView`, Pocket steps only.
struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    private var phase: ConnectionPhase { model.session.phase }
    private var step: Int { phase.pocketWizardStep }
    private var tight: Bool { compact }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 640 {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView(showsIndicators: false) {
                        introCard
                            .frame(minHeight: geo.size.height)
                    }
                    .fadeOverflowBottom()
                    .frame(width: max(236, geo.size.width * 0.28))
                    .frame(maxHeight: .infinity)
                    stepCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    portraitIntroHeader
                    StartupWizardProgress(
                        currentStep: step,
                        totalSteps: ConnectionPhase.pocketWizardStepCount,
                        compact: true
                    )
                    stepCard
                        .frame(maxHeight: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FIRST RUN")
                .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(StartupColors.muted)
            Text("Pair your camera.")
                .font(LiveType.ui(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("We'll walk you through it — your camera is connected in about a minute.")
                .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 16)

            StartupWizardProgress(
                currentStep: step,
                totalSteps: ConnectionPhase.pocketWizardStepCount,
                compact: true
            )

            if !model.savedCameras.isEmpty {
                StartupYourCamerasButton(action: { model.cancelPairing() })
                    .padding(.top, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private var portraitIntroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("FIRST RUN")
                        .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(StartupColors.muted)
                    Text("Pair your camera.")
                        .font(LiveType.ui(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StartupColors.ink)
                        .padding(.top, 4)
                }
                Spacer(minLength: 12)
                if !model.savedCameras.isEmpty {
                    StartupYourCamerasButton(action: { model.cancelPairing() })
                }
            }
            Text("We'll walk you through it — your camera is connected in about a minute.")
                .font(LiveType.ui(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STEP \(step) OF \(ConnectionPhase.pocketWizardStepCount)")
                .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(StartupColors.muted)
            Text(stepTitle)
                .font(LiveType.ui(size: tight ? 22 : 25, weight: .bold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                stepBody
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }
            .fadeOverflowBottom()

            if showsFooter {
                footer
                    .padding(.top, 10)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private var stepTitle: String {
        switch step {
        case 2: "Approve on Pocket"
        case 3: "Join camera Wi-Fi"
        case 4: "Open datalink"
        default: "Find your camera"
        }
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 2:
            approveStep
        case 3:
            joinWifiStep
        case 4:
            datalinkStep
        default:
            scanStep
        }
    }

    private var scanStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let why) = phase {
                StartupWizardInfoBanner(
                    text: StartupConnectionCopy.friendly(why),
                    tight: tight
                )
            }

            if model.session.found.isEmpty {
                StartupEmptyDiscoveryCard(
                    title: model.isScanning ? "Looking for cameras" : "No cameras yet",
                    hint:
                        "Turn the camera on and keep the phone nearby. Pocket and Nano both appear — tap the one you want.",
                    compact: tight
                )
                StartupIndeterminateBar()
                    .padding(.top, 2)
            } else {
                ForEach(model.session.found) { camera in
                    Button {
                        model.session.connect(camera)
                    } label: {
                        StartupDiscoveredCameraCard(camera: camera, compact: tight)
                    }
                    .buttonStyle(.zcTapTarget)
                    .contentShape(Rectangle())
                    .disabled(model.isBusy)
                }
            }

            StartupWizardPrepareCards(steps: Self.prepareSteps, tight: tight)
        }
    }

    private var approveStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StartupWizardInfoBanner(
                text:
                    "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
                tight: tight
            )
            StartupWizardDeviceInstructionCard(
                section: StartupWizardDeviceSection(
                    id: "approve-pocket",
                    title: "On the camera",
                    icon: .aperture,
                    steps: [
                        "Look for an Approve / pairing prompt",
                        "Tap it on the camera screen",
                    ]
                ),
                tight: tight
            )
            StartupWizardDeviceInstructionCard(
                section: StartupWizardDeviceSection(
                    id: "approve-iphone",
                    title: "On iPhone",
                    icon: .smartphone,
                    steps: [
                        "Wait here — we keep the Bluetooth link alive",
                        "Don't force-quit the app",
                    ]
                ),
                tight: tight
            )
            HStack(spacing: 10) {
                ProgressView()
                    .tint(StartupColors.accent)
                Text(phase.label)
                    .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.ink)
            }
        }
    }

    private var joinWifiStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "We read the camera's SSID and password over Bluetooth, then join its Wi-Fi for you."
            )
            .font(LiveType.ui(size: tight ? 12 : 13, weight: .regular, design: .rounded))
            .foregroundStyle(StartupColors.muted)
            .fixedSize(horizontal: false, vertical: true)

            StartupWizardDeviceInstructionCard(
                section: StartupWizardDeviceSection(
                    id: "wifi-pocket",
                    title: "On the camera",
                    icon: .aperture,
                    steps: [
                        "Leave the camera on — it brings up its own Wi-Fi",
                        "No menu tap needed on this path",
                    ]
                ),
                tight: tight
            )
            StartupWizardDeviceInstructionCard(
                section: StartupWizardDeviceSection(
                    id: "wifi-iphone",
                    title: "On iPhone",
                    icon: .smartphone,
                    steps: [
                        "Tap Join when iOS asks to join the camera network",
                        "Stay on this screen until we open the datalink",
                    ]
                ),
                tight: tight
            )
            HStack(spacing: 10) {
                ProgressView()
                    .tint(StartupColors.accent)
                Text(phase.label)
                    .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.ink)
            }
        }
    }

    private var datalinkStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(StartupColors.accent)
                StartupIconSquare(icon: .aperture, size: 48)
            }
            Text("Opening the video link…")
                .font(LiveType.ui(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
            Text(phase.label)
                .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
        }
    }

    private var showsFooter: Bool {
        if case .failed = phase { return true }
        if case .idle = phase { return !model.savedCameras.isEmpty }
        if case .scanning = phase { return !model.savedCameras.isEmpty }
        return model.isBusy  // pairing / creds / Wi-Fi — always allow cancel
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !model.savedCameras.isEmpty || model.isBusy {
                Button {
                    model.cancelPairing()
                } label: {
                    Text(model.isBusy ? "Cancel" : "Back")
                }
                .buttonStyle(StartupWizardOutlineButtonStyle())
            }
            if case .failed = phase {
                Button {
                    model.session.startScan()
                } label: {
                    Text("Try again")
                }
                .buttonStyle(StartupWizardFilledButtonStyle())
            }
        }
    }

    private static let prepareSteps = [
        "Turn the camera on and wait until Bluetooth is up.",
        "Tap the camera in the list when it appears.",
        "If the Pocket asks you to Approve, tap it on the camera screen.",
        "Join the camera Wi-Fi when iOS prompts, then we open the datalink.",
    ]
}
