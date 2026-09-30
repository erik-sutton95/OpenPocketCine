import AppKit
import OpenPocketCineMacCore
import SwiftUI

struct PreviewHost: NSViewRepresentable {
    let decoder: MacPreviewDecoder

    func makeNSView(context: Context) -> PreviewPictureView {
        let view = PreviewPictureView()
        decoder.onPicture = { [weak view] buffer in
            view?.show(buffer)
        }
        return view
    }

    func updateNSView(_ view: PreviewPictureView, context: Context) {
        decoder.onPicture = { [weak view] buffer in
            view?.show(buffer)
        }
    }
}

final class PreviewPictureView: NSView {
    private let picture = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor.black
        picture.contentsGravity = .resizeAspect
        layer?.addSublayer(picture)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        picture.frame = bounds
    }

    func show(_ buffer: CVPixelBuffer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = buffer
        CATransaction.commit()
    }
}

struct MacRootView: View {
    @Bindable var session: MacMultiviewSession

    var body: some View {
        Group {
            if session.networkAccepted {
                MultiviewStageView(session: session)
            } else {
                NetworkSetupView(session: session)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { session.refreshLAN() }
        .onDisappear { session.clearPassword() }
    }
}

struct NetworkSetupView: View {
    @Bindable var session: MacMultiviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Multiview")
                .font(.largeTitle.weight(.semibold))
            Text(
                "Cameras join the Wi-Fi this Mac is already using. Nano needs WPA2; a WPA3-only network refuses the join."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            LabeledContent("This Mac") {
                Text(session.cameraHotspotAddress ?? session.lanAddress ?? "No shared IPv4 address")
                    .foregroundStyle(session.lanAddress == nil ? .red : .primary)
            }
            if session.cameraHotspotAddress != nil {
                Text(
                    "This Mac is on a camera's own Wi-Fi. Only that camera can answer here. Join the room Wi-Fi, the network several cameras can share, then come back."
                )
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }
            if session.ssid.isEmpty {
                Text(
                    session.wifiNameDenied
                        ? "macOS is hiding the Wi-Fi name. Allow Location for OpenPocketCine in System Settings, or type the network below."
                        : "Reading the Wi-Fi this Mac is using…"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                TextField("Network name", text: $session.ssid)
                    .textFieldStyle(.roundedBorder)
            } else {
                LabeledContent("Wi-Fi") {
                    Text(session.ssid)
                }
            }
            SecureField("Password", text: $session.password)
                .textFieldStyle(.roundedBorder)
            Button("Continue") { session.acceptNetwork() }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    session.lanAddress == nil || session.cameraHotspotAddress != nil
                        || session.ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Refresh address") { session.refreshLAN() }
                .buttonStyle(.borderless)
        }
        .padding(32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct MultiviewStageView: View {
    @Bindable var session: MacMultiviewSession
    @State private var adding = false

    private var groupDecision: MacRecordGate.Group {
        MacRecordGate.group(session.assignedRecordCameras, stop: session.groupStop)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.ssid).font(.headline)
                    Text(session.cameraHotspotAddress ?? session.lanAddress ?? "No LAN address")
                        .font(.caption)
                        .foregroundStyle(session.cameraHotspotAddress == nil ? Color.secondary : Color.red)
                    if session.cameraHotspotAddress != nil {
                        Text("Camera Wi-Fi. Join the room network.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Text(session.groupNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(session.groupStop ? "Stop all" : "Record all") {
                    Task { await session.toggleGroupRecording() }
                }
                .disabled(groupDecision.refused || session.groupBusy || session.busy)
            }
            GeometryReader { geo in
                let gap: CGFloat = 12
                let width = max(0, (geo.size.width - gap) / 2)
                let height = max(0, (geo.size.height - gap) / 2)
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        tile(0, width: width, height: height)
                        tile(1, width: width, height: height)
                    }
                    HStack(spacing: gap) {
                        tile(2, width: width, height: height)
                        tile(3, width: width, height: height)
                    }
                }
            }
            Text(session.scanNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.black)
        .onAppear { session.startScanning() }
        .sheet(isPresented: $adding) {
            CameraPicker(session: session) { adding = false }
        }
    }

    private func tile(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        let tile = session.tiles[index]
        return MultiviewTileView(session: session, tile: tile, canAdd: canAdd(tile)) {
            adding = true
        }
        .frame(width: width, height: height)
    }

    private func canAdd(_ tile: MacTile) -> Bool {
        tile.camera == nil && session.board.firstEmptyIndex == session.tiles.firstIndex { $0.id == tile.id }
    }
}

struct MultiviewTileView: View {
    @Bindable var session: MacMultiviewSession
    var tile: MacTile
    var canAdd: Bool
    var add: () -> Void

    private var recordAction: MacRecordAction {
        MacRecordGate.toggle(tile.recordCamera)
    }

    var body: some View {
        picture
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { tileBorder }
    }

    private var picture: some View {
        ZStack(alignment: .bottomLeading) {
            PreviewHost(decoder: tile.decoder)
            if tile.camera == nil {
                emptySlot
            } else {
                chrome
            }
        }
    }

    private var emptySlot: some View {
        VStack {
            if canAdd {
                Button("Add camera", action: add)
            } else {
                Text("Empty").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tile.camera?.name ?? " ")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if tile.camera != nil {
                    Button("Remove") { session.remove(tile) }
                        .disabled(session.busy || tile.connecting || tile.recordingBusy)
                }
            }
            Text(tile.failure ?? tile.status)
                .font(.caption)
                .foregroundStyle(tile.failure == nil ? Color.secondary : Color.red)
                .lineLimit(2)
            if tile.camera != nil {
                recordRow
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55))
    }

    private var recordRow: some View {
        HStack {
            Text(tile.recordingNote ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(tile.recording == true ? "Stop" : "Record") {
                Task { await session.toggleRecording(tile) }
            }
            .disabled(recordAction == .refuse || session.groupBusy)
        }
    }

    private var tileBorder: some View {
        let recording = tile.recording == true
        return RoundedRectangle(cornerRadius: 8)
            .stroke(recording ? Color.red : Color.white.opacity(0.12), lineWidth: recording ? 3 : 1)
    }
}

struct CameraPicker: View {
    @Bindable var session: MacMultiviewSession
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add camera").font(.title2.weight(.semibold))
            Text(session.scanNote).font(.caption).foregroundStyle(.secondary)
            if session.discovered.isEmpty {
                Text("Power on a Pocket or Nano and keep it nearby.")
                    .foregroundStyle(.secondary)
            } else {
                List(session.discovered) { camera in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(camera.name)
                            Text(camera.model.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.board.cameraIDs.contains(camera.id) {
                            Text("On stage").foregroundStyle(.secondary)
                        } else if camera.hasMultiviewPreview {
                            Button("Add") {
                                close()
                                Task { await session.add(camera) }
                            }
                        } else {
                            Text("No preview").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
    }
}
