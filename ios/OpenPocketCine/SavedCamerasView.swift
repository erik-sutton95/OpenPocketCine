import OpenPocketViewCore
import SwiftUI

/// Returning-user home. OpenZCine `StartupSavedCamerasView` chrome, Pocket-only (no setups).
struct SavedCamerasView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let twoColumn = proxy.size.width >= 640
            Group {
                if twoColumn {
                    HStack(alignment: .top, spacing: 16) {
                        introCard(hugsContent: false)
                            .frame(width: max(288, proxy.size.width * 0.36))
                            .frame(maxHeight: .infinity)
                        cameraListCard
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        introCard(hugsContent: true)
                        cameraListCard
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func introCard(hugsContent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your cameras.")
                .font(LiveType.ui(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Tap a saved camera to reconnect.")
                .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if hugsContent {
                Color.clear.frame(height: 16)
            } else {
                Spacer(minLength: 12)
            }

            VStack(spacing: 10) {
                if model.isBusy {
                    Text(model.session.phase.label)
                        .font(LiveType.ui(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StartupColors.muted)
                    Button {
                        model.cancelPairing()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StartupFilledButtonStyle())
                }

                Button {
                    model.pairNewCamera()
                } label: {
                    Text("Pair new camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartupFilledButtonStyle())
                .disabled(model.isBusy)

                Button {
                    model.homePanel = .media
                } label: {
                    Text("Media library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartupQuietButtonStyle())

                Button {
                    model.homePanel = .settings
                } label: {
                    Text("Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartupQuietButtonStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private var cameraListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CAMERA LIST")
                .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(StartupColors.muted)
            Text("Tap a camera to connect")
                .font(LiveType.ui(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(model.savedCameras) { camera in
                        SavedCameraRow(
                            camera: camera,
                            nearby: nearbyMatch(for: camera),
                            isBusy: model.isBusy
                        )
                    }
                    if model.savedCameras.isEmpty {
                        Text("No cameras saved yet — Pair new camera walks you through it.")
                            .font(LiveType.ui(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(StartupColors.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 4)
            }
            .fadeOverflowBottom()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private func nearbyMatch(for camera: SavedCamera) -> FoundCamera? {
        model.session.found.first { $0.id == camera.id }
    }
}

private struct SavedCameraRow: View {
    @Environment(AppModel.self) private var model
    @State private var isDeleteConfirmationPresented = false
    @State private var isRenamePresented = false
    @State private var renameText = ""
    let camera: SavedCamera
    let nearby: FoundCamera?
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.reconnect(camera)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(camera.displayName)
                            .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(StartupColors.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statusPill
                        connectChrome
                    }
                    Text(subtitle)
                        .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(StartupColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isConnectLocked)
            .accessibilityLabel("Connect \(camera.displayName)")

            optionsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StartupColors.tile.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
                StartupColors.border.opacity(0.10), lineWidth: 1)
        )
        .contextMenu { menuActions }
        .alert("Remove camera?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.forget(camera) }
        } message: {
            Text("This removes \(camera.displayName) from this phone. You can pair it again later.")
        }
        .alert("Rename camera", isPresented: $isRenamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.rename(camera, to: renameText) }
        } message: {
            Text("Give this camera a name you'll recognize.")
        }
    }

    /// Retap during pairing / GetSSID cancels the previous `run` and starts a clean one.
    /// Lock only once we're joining Wi-Fi or already live.
    private var isConnectLocked: Bool {
        switch model.session.phase {
        case .joiningWifi, .openingDatalink, .live: true
        default: false
        }
    }

    private var subtitle: String {
        let ssid = camera.lastSSID.map { " · \($0)" } ?? ""
        return camera.modelName + ssid
    }

    private var statusPill: some View {
        let online = nearby != nil
        return Text(online ? "Online" : "Offline")
            .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(online ? StartupColors.ready : StartupColors.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                Capsule().stroke(
                    (online ? StartupColors.ready : StartupColors.muted).opacity(0.5), lineWidth: 1)
            )
    }

    /// Visual Connect / Reconnect chrome inside the row button (OpenZCine filled vs outline).
    /// The whole row is the hit target — nested Buttons would steal taps from the row.
    @ViewBuilder private var connectChrome: some View {
        let online = nearby != nil
        Text(online ? "Connect" : "Reconnect")
            .fixedSize()
            .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(online ? StartupColors.darkText : StartupColors.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                online ? StartupColors.accent : StartupColors.control.opacity(0.82),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            )
            .overlay {
                if !online {
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                        .stroke(StartupColors.border.opacity(0.12), lineWidth: 1)
                }
            }
            .opacity(isBusy ? 0.4 : 1)
    }

    private var optionsMenu: some View {
        Menu {
            menuActions
        } label: {
            OpcIcon.ellipsis
                .frame(width: 15, height: 15)
                .foregroundStyle(StartupColors.muted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Camera options")
        .disabled(isBusy)
    }

    @ViewBuilder private var menuActions: some View {
        Button {
            renameText = camera.customName ?? ""
            isRenamePresented = true
        } label: {
            Label {
                Text("Rename")
            } icon: {
                OpcIcon.pencil
            }
        }
        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label {
                Text("Remove")
            } icon: {
                OpcIcon.trash
            }
        }
    }
}
