import OpenPocketViewCore
import SwiftUI

enum StartupColors {
    /// DJI Black / Titan pairing chrome — Sky Blue accent, no Nikon gold.
    static let background = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let tile = Color(red: 36 / 255, green: 36 / 255, blue: 36 / 255)
    static let control = Color(red: 94 / 255, green: 98 / 255, blue: 98 / 255)
    static let ink = Color.white
    static let muted = Color(red: 160 / 255, green: 165 / 255, blue: 165 / 255)
    static let dim = Color(red: 94 / 255, green: 98 / 255, blue: 98 / 255)
    static let border = Color.white
    static let card = surface.opacity(0.58)
    static let accent = Color(red: 0, green: 163 / 255, blue: 230 / 255)
    static let ready = Color(red: 0.247, green: 0.710, blue: 0.416)
    static let destructive = Color(red: 0.930, green: 0.267, blue: 0.267)
    static let darkText = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)

    static var backdrop: some View {
        ZStack {
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
            RadialGradient(
                colors: [
                    Color(red: 0, green: 163 / 255, blue: 230 / 255).opacity(0.10),
                    Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(0),
                ],
                center: UnitPoint(x: 0.5, y: 0.24),
                startRadius: 8,
                endRadius: 760
            )
        }
    }
}

enum LiveDesign {
    /// DJI Black `#141414`.
    private static let djiBlack = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    /// DJI Titan `#5E6262` — hairlines and low-opacity inactive fills only.
    private static let djiTitan = Color(red: 94 / 255, green: 98 / 255, blue: 98 / 255)
    /// DJI Silver `#A0A5A5`.
    private static let djiSilver = Color(red: 160 / 255, green: 165 / 255, blue: 165 / 255)
    /// DJI Sky Blue `#00A3E0`.
    private static let djiSky = Color(red: 0, green: 163 / 255, blue: 230 / 255)

    static let background = djiBlack
    /// Slightly lifted black for cards — stays dark, not a Titan slab.
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let glass = djiBlack.opacity(0.24)
    static let glassOpaque = djiBlack.opacity(0.38)
    /// Plate *behind* Liquid Glass. Dense charcoal, not Titan — a gray mix
    /// desaturates refraction and reads as weaker glass, not a darker HUD.
    static let chromePlate = djiBlack.opacity(0.34)
    /// Black ND on `Glass.regular`. Titan here turned the bars gray.
    static let chromeTint = djiBlack.opacity(0.42)
    /// Inactive pills: Titan at low opacity so chrome stays light-on-dark.
    static let glassBright = djiTitan.opacity(0.18)
    static let hairline = djiTitan.opacity(0.45)
    static let hairlineStrong = djiTitan.opacity(0.70)
    static let text = Color.white
    static let muted = djiSilver
    static let faint = djiTitan
    static let accent = djiSky
    static let accentDim = djiSky.opacity(0.16)
    /// Zebra amber swatch — scientific gold, not chrome accent.
    static let amber = Color(red: 0.914, green: 0.674, blue: 0.208)
    static let good = Color(red: 0.18, green: 0.78, blue: 0.42)
    static let rec = Color(red: 0.82, green: 0.20, blue: 0.23)
    static let info = Color(red: 0.10, green: 0.58, blue: 0.98)
    static let cornerRadius = DesignTokens.cornerRadius
    /// Assist toolbar + capture strip (OpenZCine `LiveDesign.controlHeight`).
    static let controlHeight: CGFloat = 58
}

extension View {
    /// Field-monitor HUD: frosted glass over a dark plate so the feed cannot
    /// bleach one bar and leave the other charcoal.
    func liveChromeGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        self
            .liquidGlass(in: shape, tint: LiveDesign.chromeTint, interactive: interactive)
            .background(LiveDesign.chromePlate, in: shape)
            .environment(\.colorScheme, .dark)
    }

    func liveChromeCapsule(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Capsule(), interactive: interactive)
    }

    func liveChromeCircle(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Circle(), interactive: interactive)
    }
}

enum StartupConnectionCopy {
    static func statusTitle(for phase: ConnectionPhase, isDiscovering: Bool) -> String {
        switch phase {
        case .idle:
            return isDiscovering ? "Looking" : "Ready"
        case .scanning:
            return "Looking"
        case .connectingGatt:
            return "Connecting"
        case .pairing, .awaitingApproval:
            return "Pairing"
        case .readingWifiCreds:
            return "Reading"
        case .joiningWifi:
            return "Joining"
        case .openingDatalink:
            return "Connecting"
        case .live:
            return "Connected"
        case .failed:
            return "Ready"
        }
    }

    static func friendly(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") {
            return "The camera didn't respond in time. Check Bluetooth and try again."
        }
        if lower.contains("disconnected") {
            return "The camera ended the connection. Try again."
        }
        if lower.contains("approve") {
            return trimmed
        }
        return trimmed
    }
}

struct StartupHeader: View {
    var title: String = "Connection setup"
    let statusTitle: String
    let isBusy: Bool
    var onPrivacy: (() -> Void)? = nil
    var onTerms: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text("OPENPOCKETCINE")
                    .font(LiveType.ui(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(StartupColors.muted)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .font(LiveType.ui(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(StartupColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let onPrivacy {
                        Button("Privacy", action: onPrivacy)
                            .font(LiveType.ui(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(StartupColors.dim)
                            .buttonStyle(.zcTapTarget)
                    }
                    if let onTerms {
                        Button("Terms", action: onTerms)
                            .font(LiveType.ui(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(StartupColors.dim)
                            .buttonStyle(.zcTapTarget)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusTitle)
                    .font(LiveType.ui(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(StartupColors.surface.opacity(0.50), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.40), lineWidth: 1))
        }
    }

    private var statusColor: Color {
        if isBusy
            || [
                "Looking", "Pairing", "Reconnecting", "Starting", "Reading", "Discovering",
                "Preparing", "Joining", "Connecting",
            ]
            .contains(statusTitle)
        {
            return StartupColors.accent
        }
        return StartupColors.ready
    }
}

struct StartupCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(StartupColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(StartupColors.border.opacity(0.08), lineWidth: 1)
            )
    }
}

struct StartupIconSquare: View {
    let icon: OpcIcon
    var size: CGFloat = 56
    var cornerRadius: CGFloat = DesignTokens.cornerRadius
    var tint: Color = StartupColors.accent

    var body: some View {
        let glyph = max(16, size * 0.38)
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(StartupColors.tile)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius).stroke(
                    tint.opacity(0.46), lineWidth: 1)
            )
            .overlay {
                icon
                    .frame(width: glyph, height: glyph)
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
    }
}

struct StartupWizardProgress: View {
    let currentStep: Int
    let totalSteps: Int
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Text(compact ? "Setup" : "Set up your first camera")
                    .font(LiveType.ui(size: compact ? 10 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.muted)
                Spacer(minLength: 0)
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(LiveType.ui(size: compact ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(StartupColors.dim)
            }
            HStack(spacing: compact ? 4 : 8) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(
                            step <= currentStep
                                ? StartupColors.accent : StartupColors.control.opacity(0.55)
                        )
                        .frame(height: compact ? 3 : 4)
                        .overlay {
                            if step > currentStep {
                                Capsule().stroke(
                                    StartupColors.border.opacity(0.08), lineWidth: 1)
                            }
                        }
                }
            }
        }
    }
}

struct StartupWizardPrepareCards: View {
    let steps: [String]
    var tight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 6 : 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: tight ? 10 : 12) {
                    Text("\(index + 1)")
                        .font(LiveType.ui(size: tight ? 12 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(StartupColors.accent)
                        .frame(width: tight ? 24 : 30, height: tight ? 24 : 30)
                        .background(
                            StartupColors.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(StartupColors.accent.opacity(0.45), lineWidth: 1)
                        )

                    Text(step)
                        .font(LiveType.ui(size: tight ? 12 : 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StartupColors.ink)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, tight ? 12 : 16)
                .padding(.vertical, tight ? 9 : 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    StartupColors.card,
                    in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                        .stroke(StartupColors.border.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }
}

struct StartupWizardDeviceSection: Identifiable {
    let id: String
    let title: String
    let icon: OpcIcon
    let steps: [String]
}

struct StartupWizardDeviceInstructionCard: View {
    let section: StartupWizardDeviceSection
    var tight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 6 : 8) {
            HStack(spacing: 8) {
                section.icon
                    .frame(width: tight ? 13 : 15, height: tight ? 13 : 15)
                    .foregroundStyle(StartupColors.accent)
                Text(section.title)
                    .font(LiveType.ui(size: tight ? 11 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(StartupColors.ink)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: tight ? 4 : 6) {
                ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(LiveType.ui(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(StartupColors.muted)
                            .frame(width: 14, alignment: .trailing)
                            .padding(.top, 1)
                        Text(step)
                            .font(
                                LiveType.ui(
                                    size: tight ? 11 : 13, weight: .medium, design: .rounded)
                            )
                            .foregroundStyle(StartupColors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, tight ? 10 : 14)
        .padding(.vertical, tight ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            StartupColors.card, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(StartupColors.border.opacity(0.10), lineWidth: 1)
        )
    }
}

struct StartupWizardInfoBanner: View {
    let text: String
    var tight: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: tight ? 8 : 10) {
            OpcIcon.info
                .frame(width: tight ? 12 : 14, height: tight ? 12 : 14)
                .foregroundStyle(StartupColors.accent)
            Text(text)
                .font(LiveType.ui(size: tight ? 10 : 12, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, tight ? 10 : 12)
        .padding(.vertical, tight ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            StartupColors.surface.opacity(0.72),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(StartupColors.accent.opacity(0.28), lineWidth: 1)
        )
    }
}

struct StartupIndeterminateBar: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let segmentWidth = max(44, trackWidth * 0.32)
            Capsule()
                .fill(StartupColors.accent)
                .frame(width: segmentWidth, height: 3)
                .offset(x: animating ? trackWidth - segmentWidth : 0)
                .animation(
                    .easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: animating)
        }
        .frame(height: 3)
        .frame(maxWidth: .infinity)
        .background(StartupColors.control.opacity(0.45), in: Capsule())
        .onAppear { animating = true }
    }
}

struct StartupEmptyDiscoveryCard: View {
    var title: String = "Looking for cameras"
    var hint: String = "Turn the camera on — Pocket and Nano both appear over Bluetooth."
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            OpcIcon.radio
                .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                .foregroundStyle(StartupColors.accent)
            Text(title)
                .font(LiveType.ui(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
            Text(hint)
                .font(LiveType.ui(size: compact ? 10 : 12, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 3 : nil)
                .minimumScaleFactor(compact ? 0.85 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 12 : 24)
        .background(
            StartupColors.card, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(
                StartupColors.border.opacity(0.10), lineWidth: 1))
    }
}

struct StartupDiscoveredCameraCard: View {
    let camera: FoundCamera
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            StartupIconSquare(icon: .scan, size: compact ? 36 : 48)

            VStack(alignment: .leading, spacing: compact ? 3 : 7) {
                Text(
                    FoundCameraIdentity.listTitle(
                        advertisedName: camera.name, modelName: camera.model.name)
                )
                .font(LiveType.ui(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .lineLimit(1)
                Text(
                    FoundCameraIdentity.listSubtitle(
                        advertisedName: camera.name, modelName: camera.model.name)
                        + (camera.model.verified ? "" : " · unverified")
                )
                .font(LiveType.ui(size: compact ? 10 : 12, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineLimit(1)
            }

            Spacer()

            OpcIcon.signal
                .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
                .foregroundStyle(StartupColors.accent)
        }
        .padding(.horizontal, compact ? 12 : 16)
        .frame(height: compact ? 64 : 84)
        .background(
            StartupColors.card, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(StartupColors.border.opacity(0.10), lineWidth: 1)
        )
    }
}

struct StartupOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(StartupColors.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                StartupColors.control.opacity(configuration.isPressed ? 0.98 : 0.82),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(
                    StartupColors.border.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct StartupFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(StartupColors.darkText)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    StartupColors.accent.opacity(configuration.isPressed ? 0.80 : 1),
                    in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

struct StartupWizardFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(LiveType.ui(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? StartupColors.darkText : StartupColors.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isEnabled
                        ? StartupColors.accent.opacity(configuration.isPressed ? 0.80 : 1)
                        : StartupColors.control.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                )
                .opacity(isEnabled ? 1 : 0.55)
        }
    }
}

struct StartupWizardOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LiveType.ui(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(StartupColors.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                StartupColors.control.opacity(configuration.isPressed ? 0.98 : 0.82),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(
                    StartupColors.border.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct StartupQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(StartupColors.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                StartupColors.control.opacity(configuration.isPressed ? 0.98 : 0.66),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(
                    StartupColors.border.opacity(0.08), lineWidth: 1))
    }
}

/// Wizard-exit affordance matching OpenZCine `yourCamerasButton`.
struct StartupYourCamerasButton: View {
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                OpcIcon.chevronLeft
                    .frame(width: 12, height: 12)
                OpcIcon.camera
                    .frame(width: 13, height: 13)
                Text("Your cameras")
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
        }
        .buttonStyle(StartupWizardOutlineButtonStyle())
        .fixedSize()
        .disabled(disabled)
    }
}

struct StartupOverflowFade: ViewModifier {
    var fadeHeight: CGFloat
    @State private var canScrollFurther = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.containerSize.height
                        - geometry.contentOffset.y > 2
                } action: { _, more in
                    canScrollFurther = more
                }
                .mask(
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            colors: [.black, canScrollFurther ? .clear : .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                    }
                )
                .animation(.easeInOut(duration: 0.18), value: canScrollFurther)
        } else {
            content
        }
    }
}

extension View {
    func fadeOverflowBottom(height: CGFloat = 28) -> some View {
        modifier(StartupOverflowFade(fadeHeight: height))
    }
}
