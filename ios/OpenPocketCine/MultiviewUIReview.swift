#if DEBUG
    import MonitorUI
    import OpenPocketViewCore
    import SwiftUI

    /// An explicit development-only route to the production stage. It bypasses app
    /// startup, camera discovery and persistence, including on a physical review device.
    @MainActor enum MultiviewUIReview {
        static var isActive: Bool {
            ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MULTIVIEW"] == "1"
        }

        static func prepareIfRequested() {
            guard isActive,
                let defaults = UserDefaults(suiteName: "opc.multiview.presentation.review")
            else { return }
            ReliabilityReportingConsent.defaults = defaults
            ReliabilityReportingConsent.setOptedIn(false)
        }

        static func sessionFromEnvironment() -> MultiviewSession? {
            guard isActive else { return nil }
            let environment = ProcessInfo.processInfo.environment
            let count = Int(environment["OPV_UI_REVIEW_MULTIVIEW_COUNT"] ?? "3") ?? 3
            return makeSession(
                count: count,
                layout: environment["OPV_UI_REVIEW_MULTIVIEW_LAYOUT"] == "grid"
                    ? .grid : .centerStage,
                recovering: environment["OPV_UI_REVIEW_MULTIVIEW_RECOVERY"] == "1")
        }

        static func makeSession(
            count: Int = 3, layout: MultiviewLayout = .centerStage, recovering: Bool = false
        ) -> MultiviewSession {
            let session = MultiviewSession(
                resetCamera: { _ in true }, saveStage: { _ in true }, loadNetwork: { _, _ in nil })
            session.networkConfigured = true
            session.ssid = "Review network"
            session.layout = layout
            let names = ["Wide", "Close-up", "Side angle", "Overhead"]
            let models = [0x22, 0x20, 0x19, 0x21]
            for index in 0..<min(4, max(0, count)) {
                let tile = session.tiles[index]
                tile.camera = FoundCamera(
                    id: UUID(), name: names[index],
                    model: .resolve(modelId: models[index], name: names[index]),
                    modelId: models[index])
                tile.hasPicture = true
                tile.networkVerified = true
                tile.status = "Live · Video mode"
                tile.settings.iso = [400, 800, 200, 1600][index]
                tile.settings.shutterDenom = 50
                tile.settings.shootingMode = Int(ShootingMode.video.rawValue)
            tile.settings.whiteBalance = .custom(kelvin: 5600, tint: 0)
            tile.settings.whiteBalanceKelvin = 5600
            tile.settings.whiteBalanceTint = 0
                tile.settings.focusMode = index == 2 ? nil : .continuous
                tile.settings.timecode = index == 2 ? nil : "14:32:08:12"
                tile.settings.batteryPercent = [87, 72, 64, 91][index]
                tile.settings.storageTotalMb = 128 * 1024
                tile.settings.storageFreeMb = [96, 73, 52, 110][index] * 1024
                tile.settings.videoResolution = VideoResolution(rawValue: 0x10)
                tile.settings.fps = 25
                tile.settings.colorMode = index == 2 ? .dLogM : .dLog2
                tile.recordingObservation = (index == 0, Date())
                tile.settings.recordElapsedSec = index == 0 ? 24 : 0
                tile.latestSettings = tile.settings
                // No driver or control host: hardware actions stay unavailable.
                tile.recordingAvailable = false
            }
            if recovering, count > 1 {
                session.tiles[1].recovering = true
                session.tiles[1].status = "Restoring picture…"
            }
            return session
        }
    }

    struct MultiviewUIReviewRoot: View {
        @State private var model = AppModel()
        var body: some View { MultiviewView().environment(model) }
    }

    /// Static artwork checks picture framing without opening a file or a second
    /// decoder. The real display-layer host remains mounted beneath this fixture.
    struct MultiviewUIReviewPicture: View {
        let index: Int
        let fill: Bool

        var body: some View {
            GeometryReader { geometry in
                let width =
                    fill
                    ? max(geometry.size.width, geometry.size.height * 16 / 9)
                    : min(geometry.size.width, geometry.size.height * 16 / 9)
                Canvas { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .linearGradient(
                            Gradient(colors: [Color(red: 0.23, green: 0.36, blue: 0.41), .black]),
                            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    for column in 0..<7 {
                        let height = size.height * (0.18 + Double((column + index) % 4) * 0.1)
                        let rect = CGRect(
                            x: CGFloat(column) * size.width / 7, y: size.height * 0.8 - height,
                            width: size.width / 8, height: height)
                        context.fill(Path(rect), with: .color(.white.opacity(0.16)))
                    }
                    let subject = CGRect(
                        x: size.width * (0.4 + Double(index) * 0.07), y: size.height * 0.37,
                        width: size.width * 0.11, height: size.height * 0.45)
                    context.fill(
                        Path(roundedRect: subject, cornerRadius: size.height * 0.05),
                        with: .color(Color(red: 0.72, green: 0.39, blue: 0.2)))
                }
                .frame(width: width, height: width * 9 / 16)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .background(.black)
            .accessibilityHidden(true)
        }
    }
#endif
