import OpenPocketViewCore
import SwiftUI

/// Returning-user home. OpenZCine `StartupSavedCamerasView` chrome, Pocket-only (no setups).
struct SavedCamerasView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool
    @State private var showMultiview = false

    var body: some View {
        GeometryReader { proxy in
            let twoColumn = proxy.size.width >= 640 || proxy.size.width > proxy.size.height
            let tight = proxy.size.height < 300
            Group {
                if twoColumn {
                    HStack(alignment: .top, spacing: 16) {
                        introCard(hugsContent: false, tight: tight)
                            .frame(width: max(proxy.size.width >= 640 ? 288 : 240, proxy.size.width * 0.36))
                            .frame(maxHeight: .infinity)
                        cameraListCard(tight: tight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        introCard(hugsContent: true, tight: tight)
                        cameraListCard(tight: tight)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .fullScreenCover(isPresented: $showMultiview, onDismiss: { model.session.startScan() }) {
            MultiviewView()
        }
    }

    private func introCard(hugsContent: Bool, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your cameras.")
                .font(LiveType.ui(size: tight ? 24 : 30, weight: .bold, design: .rounded))
                .foregroundStyle(StartupColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Tap a saved camera to reconnect.")
                .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, tight ? 6 : 10)

            if hugsContent {
                Color.clear.frame(height: 16)
            } else {
                Spacer(minLength: tight ? 8 : 12)
            }

            VStack(spacing: tight ? 8 : 10) {
                Button {
                    model.pairNewCamera()
                } label: {
                    Text("Pair new camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartupFilledButtonStyle())
                .disabled(connectionBusy)

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
        .padding(tight ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private func cameraListCard(tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAMERA LIST")
                        .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.4).foregroundStyle(StartupColors.muted)
                    if !tight {
                        Text("Tap a camera to connect")
                            .font(LiveType.ui(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(StartupColors.ink)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Button {
                        model.openWatcherBrowse()
                    } label: {
                        listActionIcon(.eye)
                    }
                    .accessibilityLabel(SettingsHelpCopy.watchAFeed)
                    .accessibilityIdentifier("cameras.watchFeed")
                    .help(SettingsHelpCopy.watchAFeed)

                    Button {
                        model.session.disconnect()
                        showMultiview = true
                    } label: {
                        listActionIcon(.layoutGrid)
                    }
                    .accessibilityLabel("Open Multiview")
                    .accessibilityIdentifier("cameras.multiview")
                    .help("Open Multiview")
                }
                .buttonStyle(.plain)
                .foregroundStyle(StartupColors.ink)
                .disabled(connectionBusy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(model.savedCameras) { camera in
                        SavedCameraRow(
                            camera: camera,
                            nearby: nearbyMatch(for: camera),
                            isBusy: connectionBusy,
                            connectionLabel: connectionLabel(for: camera)
                        )
                    }
                    if model.savedCameras.isEmpty {
                        Text("No cameras saved yet — Pair new camera walks you through it.")
                            .font(LiveType.ui(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(StartupColors.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, tight ? 12 : 16)
                .padding(.bottom, 4)
            }
            .fadeOverflowBottom()
        }
        .padding(tight ? 16 : 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StartupCardBackground())
    }

    private var connectionBusy: Bool { model.isBusy || model.session.isReconnecting }

    private func connectionLabel(for camera: SavedCamera) -> String? {
        guard connectionBusy, model.session.connectionTargetID == camera.id else { return nil }
        if model.session.isReconnecting, model.isScanning { return "Looking for camera…" }
        return model.session.phase.label
    }

    private func listActionIcon(_ icon: OpcIcon) -> some View {
        icon.frame(width: 22, height: 22)
            .frame(width: 44, height: 44)
            .background(StartupColors.tile, in: RoundedRectangle(cornerRadius: 12))
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
    let connectionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    model.reconnect(camera)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(camera.displayName)
                            .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(StartupColors.ink)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(subtitle)
                            .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(StartupColors.muted)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || isConnectLocked)
                .accessibilityLabel("Connect \(camera.displayName)")
                optionsMenu
            }

            HStack(spacing: 12) {
                if let connectionLabel {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(StartupColors.accent)
                        Text(connectionLabel)
                            .font(LiveType.ui(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StartupColors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    statusPill
                }
                Spacer(minLength: 0)
                if connectionLabel != nil {
                    Button { model.cancelPairing() } label: {
                        Text("Cancel").frame(minHeight: 24)
                    }
                    .buttonStyle(StartupQuietButtonStyle())
                    .accessibilityLabel("Cancel connecting to \(camera.displayName)")
                } else {
                    Button { model.reconnect(camera) } label: { connectChrome }
                        .buttonStyle(.plain)
                        .disabled(isBusy || isConnectLocked)
                        .accessibilityLabel("Connect \(camera.displayName)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StartupColors.tile.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
                StartupColors.border.opacity(0.10), lineWidth: 1)
        )
        .contextMenu { if !isBusy { menuActions } }
        .alert("Remove camera?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                guard !isBusy else { return }
                model.forget(camera)
            }
            .disabled(isBusy)
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

    /// Separate action row keeps long camera names clear of the connection button.
    @ViewBuilder private var connectChrome: some View {
        let online = nearby != nil
        Text(online ? "Connect" : "Reconnect")
            .fixedSize()
            .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(online ? StartupColors.darkText : StartupColors.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
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
                .frame(width: 44, height: 44)
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
