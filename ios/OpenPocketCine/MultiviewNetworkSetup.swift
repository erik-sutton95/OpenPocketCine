import SwiftUI

/// A bounded modal card: iPhone landscape sheets otherwise expand full width.
struct MultiviewNetworkSetup: View {
    @Bindable var session: MultiviewSession
    @Binding var passwordPrompt: Bool
    var cancel: () -> Void
    var complete: () -> Void
    @State private var step = 0
    @State private var draftPassword = ""
    @State private var otherNetwork = false
    @State private var networkName = ""
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var hotspotActive = false
    @Environment(\.scenePhase) private var scenePhase

    private var locked: Bool { session.tiles.contains { $0.camera != nil } }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button(step == 0 ? "Cancel" : "Back") {
                            cancelScan()
                            if step == 0 { cancel() } else { step = 0 }
                        }.frame(minWidth: 64, minHeight: 44)
                            .contentShape(Rectangle())
                            .disabled(session.configuringNetwork)
                        Spacer()
                        Text("Step \(step + 1) of 2").font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(
                                step == 0
                                    ? "Connect your cameras"
                                    : (session.usePhoneHotspot
                                        ? "Personal Hotspot" : "Choose Wi-Fi")
                            )
                            .font(LiveType.display(22, weight: .semibold))
                            if step == 0 { sourcePage } else { networkPage }
                            if let error = session.networkSetupError {
                                Text(error).font(.footnote).foregroundStyle(.red)
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 20)
                    }
                }
                .frame(
                    width: min(460, max(0, geometry.size.width - 32)),
                    height: min(510, max(0, geometry.size.height - 24))
                )
                .liveChromeGlass(in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius))
                .shadow(radius: 24)
                .accessibilityIdentifier("multiview.networkSetup")
            }
        }
        .font(LiveType.text(16))
        .tint(LiveDesign.accent)
        .buttonStyle(.zcTapTarget)
        .ignoresSafeArea(passwordPrompt ? .keyboard : [])
        .alert("Wi-Fi password", isPresented: $passwordPrompt) {
            SecureField("Password", text: $draftPassword).textContentType(.password)
            Button("Cancel", role: .cancel) { draftPassword = "" }
            Button("Join") {
                session.password = draftPassword
                draftPassword = ""
                Task { if await session.configureNetwork() { complete() } }
            }
        } message: {
            Text(
                "Saved securely for all cameras."
            )
        }
        .alert("Other Wi-Fi network", isPresented: $otherNetwork) {
            TextField("Network name", text: $networkName).textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {}
            Button("Next") { choose(networkName) }
        }
        .task {
            while !Task.isCancelled {
                refreshHotspot()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshHotspot() }
        }
        .onDisappear {
            cancelScan()
            passwordPrompt = false
            session.releaseNetworkCamera()
        }
    }
    private var sourcePage: some View {
        VStack(spacing: 12) {
            Text("How will this device and your cameras connect?")
                .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.secondary)
            sourceButton("Local Wi-Fi", icon: .wifi, hotspot: false)
            sourceButton("Personal Hotspot", icon: .radio, hotspot: true)
        }
    }
    private func sourceButton(_ title: String, icon: OpcIcon, hotspot: Bool) -> some View {
        Button {
            session.selectNetworkSource(hotspot: hotspot)
            step = 1
            if !hotspot && !locked { startScan() }
        } label: {
            HStack {
                icon.frame(width: 20, height: 20)
                Text(title)
                Spacer()
                OpcIcon.chevronRight.frame(width: 16, height: 16)
            }
            .padding(16).frame(minHeight: 56)
            .background(
                LiveDesign.glassBright, in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
            .contentShape(Rectangle())
        }.buttonStyle(.zcTapTarget).disabled(locked && session.usePhoneHotspot != hotspot)
    }
    @ViewBuilder private var networkPage: some View {
        if locked {
            Text(session.ssid)
            Text("Cameras are using this network. Remove them before changing it.").font(.footnote)
            Button("Done", action: complete).buttonStyle(.borderedProminent).controlSize(.large)
        } else if session.usePhoneHotspot {
            Label {
                Text(
                    hotspotActive
                        ? "Personal Hotspot is active" : "Personal Hotspot is not detected")
            } icon: {
                (hotspotActive ? OpcIcon.radio : OpcIcon.triangleAlert).frame(width: 20, height: 20)
            }
            .foregroundStyle(hotspotActive ? Color.green : Color.orange)
            .accessibilityIdentifier("multiview.hotspotStatus")
            Text(
                "In Settings → Personal Hotspot, turn on Allow Others to Join and Maximize Compatibility. Detection may start only after a camera joins."
            )
            .font(.footnote).foregroundStyle(.secondary)
            TextField(
                "Hotspot name from Settings",
                text: Binding(get: { session.ssid }, set: { session.selectNetwork($0) })
            )
            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button("Continue") { askPassword() }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(session.ssid.isEmpty || session.configuringNetwork)
        } else {
            VStack(spacing: 0) {
                ForEach(
                    Array(Set(session.networks + (session.ssid.isEmpty ? [] : [session.ssid])))
                        .sorted(), id: \.self
                ) { name in
                    Button {
                        choose(name)
                    } label: {
                        HStack {
                            OpcIcon.wifi.frame(width: 20, height: 20)
                            Text(name)
                            Spacer()
                            OpcIcon.chevronRight.frame(width: 16, height: 16)
                        }.padding(.vertical, 12).frame(minHeight: 48).contentShape(Rectangle())
                    }.disabled(session.busy || session.configuringNetwork)
                    Divider()
                }
            }
            if scanning || session.networkScanning {
                HStack {
                    ProgressView()
                    Text("Looking for networks…").font(.footnote)
                }
            } else {
                Button("Scan again") { startScan() }.disabled(session.busy)
                if session.networks.isEmpty {
                    Text("Turn on a nearby camera to scan for Wi-Fi.").font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Other network…") { otherNetwork = true }.disabled(session.busy)
            Text("This device will join the selected Wi-Fi before cameras are added.").font(
                .footnote
            ).foregroundStyle(.secondary)
        }
        if session.configuringNetwork { ProgressView("Connecting…") }
    }
    private func choose(_ name: String) {
        guard !name.isEmpty else { return }
        session.selectNetwork(name)
        askPassword()
    }
    private func askPassword() {
        draftPassword = session.password
        passwordPrompt = true
    }
    private func refreshHotspot() {
        hotspotActive = SharedWiFiPath.address(hotspot: true) != nil
    }
    private func startScan() {
        let previous = scanTask
        scanTask = Task {
            // Let cancellation cleanup finish before sharing the BLE link again.
            await previous?.value
            guard !Task.isCancelled else { return }
            await scanNetworks()
        }
    }
    private func cancelScan() {
        scanTask?.cancel()
        session.cancelNetworkScan()
    }
    private func scanNetworks() async {
        guard !Task.isCancelled, !scanning, !session.busy else { return }
        scanning = true
        defer { scanning = false }
        for _ in 0..<10 {
            if let camera = session.found.first(where: { $0.hasMultiviewPreview }) {
                await session.prepareNetworks(camera)
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
    }
}
