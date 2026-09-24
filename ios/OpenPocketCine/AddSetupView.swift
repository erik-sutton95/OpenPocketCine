import MonitorUI
import NetworkExtension
import OpenPocketViewCore
import SwiftUI

/// "Add setup" on a saved camera (#406): Wi-Fi (a router) or Hotspot (this phone), in a
/// native sheet with push navigation. The camera scans for networks by itself, and
/// saving connects over the new setup at once; Camera Wi-Fi stays as the other chip.
struct AddSetupView: View {
    enum Page: Hashable {
        case choose, networks, hotspot
        case password(String)
    }

    let camera: SavedCamera
    /// Nil when the camera is not nearby over Bluetooth. Reports each network as it arrives.
    var scan: ((@escaping @MainActor (String) -> Void) async throws -> Void)?
    var save: (CameraConnectionSetup, String, String) -> Void
    var close: () -> Void
    @State var path: [Page] = []

    @State private var currentSSID: String?
    @State private var configured: [String] = []
    @State private var found: [String] = []
    @State private var scanTask: Task<Void, Never>?
    @State private var scanning = false
    @State private var scanFinished = false
    @State private var scanFailed = false
    @State private var otherNetwork = false
    @State private var otherName = ""
    @State private var password = ""
    @State private var hotspotName = ""
    @State private var hotspotPassword = ""
    @State private var hotspotNameTouched = false
    @State private var reveal = false
    @State private var hotspotActive = false
    @State private var locationHint: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var warning: Color { MonitorTheme.linkHealthColor(.watch) }
    private var good: Color { MonitorTheme.linkHealthColor(.stable) }

    var body: some View {
        NavigationStack(path: $path) {
            screen(.choose)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss)
                    }
                }
                .navigationDestination(for: Page.self) { screen($0) }
        }
        .font(MonitorTheme.font(15))
        .foregroundStyle(MonitorTheme.text)
        .tint(MonitorTheme.accent)
        .preferredColorScheme(.dark)
        .alert("Other network", isPresented: $otherNetwork) {
            TextField("Network name", text: $otherName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Next") {
                let name = otherName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { open(.password(name)) }
            }
        }
        .task {
            await refreshCurrentNetwork()
            // Networks this app configured before. iOS keeps other saved networks private.
            let ssids = await withCheckedContinuation { continuation in
                NEHotspotConfigurationManager.shared.getConfiguredSSIDs {
                    continuation.resume(returning: $0)
                }
            }
            configured = ssids.filter { !isCameraNetwork($0) }
        }
        .task {
            while !Task.isCancelled {
                hotspotActive = SharedWiFiPath.address(hotspot: true) != nil
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onAppear { path.forEach(prefill) }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings with Location or Precise Location changed.
            if phase == .active { Task { await refreshCurrentNetwork() } }
        }
        .onDisappear { scanTask?.cancel() }
    }

    private func screen(_ page: Page) -> some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ScrollView {
                content(page, landscape: landscape)
                    .padding(.horizontal, landscape ? 24 : 18).padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(MonitorTheme.background.opacity(0.001))
        .navigationTitle(title(page))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Wi-Fi scans the moment it opens; Hotspot only when it needs the name.
            if page == .networks || (page == .hotspot && hotspotName.isEmpty) { startScan() }
            if page == .networks {
                Task {
                    await WiFiNameAccess.shared.request()
                    await refreshCurrentNetwork()
                }
            }
        }
    }

    // MARK: Navigation

    private func title(_ page: Page) -> String {
        switch page {
        case .choose: "Add setup"
        case .networks, .password: "Wi-Fi"
        case .hotspot: "Hotspot"
        }
    }

    private func open(_ next: Page) {
        prefill(next)
        path.append(next)
    }

    private func dismiss() {
        scanTask?.cancel()
        close()
    }

    private func refreshCurrentNetwork() async {
        let current = await WiFiJoiner.currentSSID()
        currentSSID = current.flatMap { isCameraNetwork($0) ? nil : $0 }
        let access = WiFiNameAccess.shared
        if current != nil || access.undecided {
            locationHint = nil
        } else if access.denied {
            locationHint = "Allow Location to show this iPhone’s Wi-Fi"
        } else if access.approximateOnly {
            locationHint = "Turn on Precise Location to show this iPhone’s Wi-Fi"
        } else {
            locationHint = nil
        }
    }

    private func isCameraNetwork(_ ssid: String) -> Bool {
        ssid.lowercased().hasPrefix("osmo") || ssid == camera.lastSSID
    }

    private func prefill(_ next: Page) {
        reveal = false
        switch next {
        case .password(let ssid):
            password = MultiviewNetworkStore.load(ssid: ssid, hotspot: false)?.password ?? ""
        case .hotspot:
            guard hotspotName.isEmpty else { return }
            // A hotspot saved by Multiview or another camera is this same phone's.
            let known =
                camera.hotspotSSID.flatMap { MultiviewNetworkStore.load(ssid: $0, hotspot: true) }
                ?? MultiviewNetworkStore.savedNetworks().last { $0.hotspot == true }
            hotspotName = known?.ssid ?? camera.hotspotSSID ?? ""
            hotspotPassword = known?.password ?? ""
        case .choose, .networks: break
        }
    }

    // MARK: Camera scan

    private func startScan() {
        guard let scan, scanTask == nil, !scanFinished else { return }
        scanning = true
        scanFailed = false
        scanTask = Task {
            do {
                try await scan { name in
                    guard !found.contains(name), !isCameraNetwork(name) else { return }
                    withAnimation(.snappy) { found.append(name) }
                    suggestHotspot()
                }
            } catch {
                if !(error is CancellationError) { scanFailed = true }
            }
            scanning = false
            scanFinished = !scanFailed
            scanTask = nil
        }
    }

    private func rescan() {
        scanFinished = false
        startScan()
    }

    /// iOS hides this phone's name (its hotspot name) from apps, but the camera sees the
    /// hotspot. One phone-like network is taken as this phone's until the operator types.
    private var phoneNetworks: [String] {
        found.filter {
            let name = $0.lowercased()
            return name.contains("iphone") || name.contains("ipad")
        }
    }

    private func suggestHotspot() {
        guard !hotspotNameTouched, hotspotName.isEmpty, phoneNetworks.count == 1 else { return }
        hotspotName = phoneNetworks[0]
        hotspotPassword =
            MultiviewNetworkStore.load(ssid: phoneNetworks[0], hotspot: true)?.password
            ?? hotspotPassword
    }

    /// Saving starts a Bluetooth connect, so a running scan first returns the camera to
    /// its own Wi-Fi and releases its link.
    private func finish(_ action: @escaping () -> Void) {
        let running = scanTask
        running?.cancel()
        Task {
            await running?.value
            action()
            close()
        }
    }

    @ViewBuilder private func content(_ page: Page, landscape: Bool) -> some View {
        switch page {
        case .choose: choosePage(landscape)
        case .networks: networksPage(landscape)
        case .password(let ssid): passwordPage(ssid, landscape)
        case .hotspot: hotspotPage(landscape)
        }
    }

    // MARK: Choose

    private func choosePage(_ landscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: landscape ? 12 : 14) {
            if landscape {
                HStack(alignment: .firstTextBaseline) {
                    Text("How should this camera connect?")
                        .font(MonitorTheme.font(18, weight: .semibold))
                    Spacer()
                    Text(camera.modelName).font(MonitorTheme.font(11.5))
                        .foregroundStyle(MonitorTheme.muted)
                }
            } else {
                HStack(spacing: 10) {
                    MonitorIcon.camera.frame(width: 16, height: 16)
                    Text("\(camera.displayName) · \(camera.modelName)")
                        .font(MonitorTheme.font(12.5))
                }
                .foregroundStyle(MonitorTheme.muted)
                Text("How should this camera connect?")
                    .font(MonitorTheme.font(22, weight: .semibold))
            }
            let layout =
                landscape
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                : AnyLayout(VStackLayout(spacing: 14))
            layout {
                choice(
                    .wifi, icon: .wifi,
                    body:
                        "A router or venue network. The camera and this iPhone join the same Wi-Fi.",
                    tag: "Best for studios and several cameras", landscape: landscape)
                choice(
                    .phoneHotspot, icon: .radio,
                    body: "This iPhone’s Personal Hotspot. Works anywhere you have cellular.",
                    tag: "Best on the move", landscape: landscape)
            }
            // Equal-height tiles side by side.
            .fixedSize(horizontal: false, vertical: landscape)
            Text("Camera Wi-Fi stays available. Switch setups from the camera’s chips at any time.")
                .font(MonitorTheme.font(landscape ? 11.5 : 12)).foregroundStyle(MonitorTheme.muted)
        }
    }

    private func choice(
        _ setup: CameraConnectionSetup, icon: MonitorIcon, body: String, tag: String,
        landscape: Bool
    ) -> some View {
        Button {
            open(setup == .wifi ? .networks : .hotspot)
        } label: {
            let layout =
                landscape
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            layout {
                icon.frame(width: 22, height: 22).foregroundStyle(MonitorTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        MonitorTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(setup.title).font(MonitorTheme.font(17, weight: .semibold))
                        if let ssid = camera.ssid(for: setup) {
                            Text("Added · \(ssid)").font(MonitorTheme.font(10.5, weight: .semibold))
                                .foregroundStyle(good).lineLimit(1)
                        }
                    }
                    Text(body).font(MonitorTheme.font(12.5)).foregroundStyle(MonitorTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if landscape { Spacer(minLength: 0) }
                    Text(tag).font(MonitorTheme.font(10.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(MonitorTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 4)
                }
                .frame(maxHeight: landscape ? .infinity : nil, alignment: .top)
                if !landscape {
                    Spacer(minLength: 0)
                    MonitorIcon.chevronRight.frame(width: 18, height: 18)
                        .foregroundStyle(MonitorTheme.faint).frame(maxHeight: .infinity)
                }
            }
            .padding(16)
            .frame(
                maxWidth: .infinity, maxHeight: landscape ? .infinity : nil, alignment: .topLeading
            )
            .background(card).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addSetup.\(setup.rawValue)")
    }

    // MARK: Wi-Fi

    /// Saved in this app's Keychain (with passwords) or configured by this app before.
    private var savedNetworks: [String] {
        var names = MultiviewNetworkStore.savedNetworks().filter { $0.hotspot != true }
            .map(\.ssid)
        for name in configured where !names.contains(name) { names.append(name) }
        return names.filter { $0 != currentSSID && !isCameraNetwork($0) }
    }

    private func hasPassword(_ ssid: String) -> Bool {
        MultiviewNetworkStore.load(ssid: ssid, hotspot: false) != nil
    }

    private func networksPage(_ landscape: Bool) -> some View {
        let known = VStack(alignment: .leading, spacing: 7) {
            if !landscape {
                Text("Choose the network").font(MonitorTheme.font(22, weight: .semibold))
                hint("The camera and this iPhone must be on the same Wi-Fi.").padding(.bottom, 8)
            }
            if let currentSSID {
                sectionLabel("THIS IPHONE IS ON")
                group {
                    networkRow(
                        currentSSID,
                        detail: hasPassword(currentSSID)
                            ? "Connected · password saved" : "Connected",
                        detailColor: good)
                }
            } else if let locationHint {
                sectionLabel("THIS IPHONE IS ON")
                group {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        row(
                            icon: .wifi, title: locationHint,
                            detail:
                                "Settings › OpenPocketCine › Location. Only the Wi-Fi name is used."
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addSetup.locationHint")
                }
            }
            if !savedNetworks.isEmpty {
                sectionLabel("SAVED ON THIS IPHONE").padding(.top, 6)
                group {
                    ForEach(Array(savedNetworks.enumerated()), id: \.element) { index, name in
                        if index > 0 { divider }
                        networkRow(name, detail: hasPassword(name) ? "Password saved" : nil)
                    }
                }
            }
        }
        let nearby = VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                sectionLabel("NEARBY")
                if scanning { ProgressView().controlSize(.mini) }
                Spacer()
                if !scanning, scan != nil {
                    Button("Scan again", action: rescan)
                        .font(MonitorTheme.font(12, weight: .semibold))
                        .frame(minHeight: 32)
                        .accessibilityIdentifier("addSetup.rescan")
                }
            }
            .padding(.top, landscape ? 0 : 6)
            group {
                let nearbyNames = found.filter { !savedNetworks.contains($0) && $0 != currentSSID }
                ForEach(Array(nearbyNames.enumerated()), id: \.element) { index, name in
                    if index > 0 { divider }
                    networkRow(name, detail: hasPassword(name) ? "Password saved" : nil)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !nearbyNames.isEmpty { divider }
                if scan == nil || scanning || nearbyNames.isEmpty {
                    row(
                        icon: scanning ? nil : .scan,
                        title: scanning
                            ? "The camera is looking for networks…"
                            : scan == nil
                                ? "Turn the camera on to find networks" : "No networks found yet",
                        detail: scanning
                            ? "Networks appear here as it finds them"
                            : scanFailed ? "The scan did not finish. Try Scan again." : nil,
                        showsProgress: scanning, chevron: false
                    )
                    .accessibilityIdentifier("addSetup.scanStatus")
                    divider
                }
                Button {
                    otherName = ""
                    otherNetwork = true
                } label: {
                    row(icon: .plus, title: "Other network…", detail: nil)
                }
                .buttonStyle(.plain)
            }
            if landscape {
                hint("The camera and this iPhone must be on the same Wi-Fi.").padding(.top, 4)
            }
        }
        return Group {
            if landscape {
                HStack(alignment: .top, spacing: 16) {
                    known.frame(maxWidth: .infinity)
                    nearby.frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    known
                    nearby
                }
            }
        }
    }

    private func networkRow(_ name: String, detail: String? = nil, detailColor: Color? = nil)
        -> some View
    {
        Button {
            open(.password(name))
        } label: {
            row(icon: .wifi, title: name, detail: detail, detailColor: detailColor, lock: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addSetup.network.\(name)")
    }

    private func passwordPage(_ ssid: String, _ landscape: Bool) -> some View {
        let network = HStack(spacing: 12) {
            MonitorIcon.wifi.frame(width: 19, height: 19).foregroundStyle(MonitorTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    MonitorTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(ssid).font(MonitorTheme.font(16, weight: .semibold))
                Text(
                    ssid == currentSSID
                        ? "This iPhone’s current network" : "This iPhone joins it too"
                )
                .font(MonitorTheme.font(11.5)).foregroundStyle(MonitorTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13).background(card)
        let checklist = VStack(alignment: .leading, spacing: 13) {
            sectionLabel("BEFORE YOU CONNECT")
            check(
                "WPA2 or WPA2/WPA3 mixed",
                landscape ? nil : "WPA3-only networks can refuse some cameras.")
            check(
                "Devices can see each other",
                landscape ? nil : "Guest networks with client isolation block the picture.")
            check(
                "Camera within range",
                landscape ? nil : "The camera leaves its own Wi-Fi and joins this one.")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(card)
        let field = VStack(alignment: .leading, spacing: 6) {
            secureField("PASSWORD", text: $password, id: "addSetup.password")
            hint("Saved in this iPhone’s Keychain. Multiview can reuse it.")
        }
        let valid =
            (password.isEmpty || password.count >= 8)
            && (try? MulticamCommands.join(ssid: ssid, password: password, seq: 0)) != nil
        let connect = connectButton("Connect over Wi-Fi", enabled: valid) {
            save(.wifi, ssid, password)
        }
        return Group {
            if landscape {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 10) {
                        network
                        checklist
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        field
                        Spacer(minLength: 8)
                        connect
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    network
                    field
                    checklist
                    connect.padding(.top, 8)
                }
            }
        }
    }

    // MARK: Hotspot

    private func hotspotPage(_ landscape: Bool) -> some View {
        let status = HStack(spacing: 10) {
            (hotspotActive ? MonitorIcon.radio : MonitorIcon.triangleAlert)
                .frame(width: 18, height: 18)
            Text(
                hotspotActive
                    ? "Personal Hotspot is on"
                    : "Personal Hotspot not detected yet. It can appear once the camera joins."
            )
            .font(MonitorTheme.font(13, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(hotspotActive ? good : warning)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            (hotspotActive ? good : warning).opacity(0.1), in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(
                (hotspotActive ? good : warning).opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("addSetup.hotspotStatus")
        let checklist = VStack(alignment: .leading, spacing: 13) {
            sectionLabel("IN SETTINGS › PERSONAL HOTSPOT")
            numbered(
                1, "Allow Others to Join",
                landscape ? nil : "Lets the camera join without a prompt.")
            numbered(
                2, "Maximize Compatibility",
                landscape ? nil : "Uses 2.4 GHz, which every Osmo camera supports.")
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack(spacing: 8) {
                    MonitorIcon.settings.frame(width: 16, height: 16)
                    Text("Open Settings").font(MonitorTheme.font(13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(MonitorTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(card)
        let name = VStack(alignment: .leading, spacing: 6) {
            sectionLabel("HOTSPOT NAME")
            TextField(
                "Hotspot name",
                text: Binding(
                    get: { hotspotName },
                    set: {
                        hotspotNameTouched = true
                        hotspotName = $0
                    })
            )
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .modifier(InputStyle())
            .accessibilityIdentifier("addSetup.hotspotName")
            if phoneNetworks.count > 1
                || (phoneNetworks.count == 1 && phoneNetworks[0] != hotspotName)
            {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(phoneNetworks, id: \.self) { name in
                            Button(name) {
                                hotspotNameTouched = true
                                hotspotName = name
                            }
                            .font(MonitorTheme.font(12, weight: .semibold))
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .background(MonitorTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                            .padding(.vertical, 5).contentShape(Rectangle())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if scanning, hotspotName.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    hint("The camera is looking for this iPhone’s hotspot…")
                }
            } else if !landscape {
                hint("This iPhone’s name, as in Settings › General › About › Name.")
            }
        }
        let pass = VStack(alignment: .leading, spacing: 6) {
            secureField("HOTSPOT PASSWORD", text: $hotspotPassword, id: "addSetup.hotspotPassword")
            if !landscape {
                hint(
                    "iOS keeps it private: copy it from Settings › Personal Hotspot once. It is remembered here."
                )
            }
        }
        let trimmed = hotspotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid =
            hotspotPassword.count >= 8
            && (try? MulticamCommands.join(ssid: trimmed, password: hotspotPassword, seq: 0))
                != nil
        let connect = connectButton("Connect over Hotspot", enabled: valid) {
            save(.phoneHotspot, trimmed, hotspotPassword)
        }
        return Group {
            if landscape {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 10) {
                        status
                        checklist
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        name
                        pass
                        Spacer(minLength: 8)
                        connect
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    status
                    checklist
                    name
                    pass
                    connect.padding(.top, 8)
                }
            }
        }
    }

    // MARK: Pieces

    private var card: some View {
        RoundedRectangle(cornerRadius: 13).fill(MonitorTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(MonitorTheme.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private func group<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(spacing: 0, content: rows).background(card)
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(MonitorTheme.font(10, weight: .bold)).tracking(1.6)
            .foregroundStyle(MonitorTheme.muted)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(MonitorTheme.font(11.5)).foregroundStyle(MonitorTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(
        icon: MonitorIcon?, title: String, detail: String?, detailColor: Color? = nil,
        lock: Bool = false, showsProgress: Bool = false, chevron: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView().frame(width: 17, height: 17)
            } else if let icon {
                icon.frame(width: 17, height: 17).foregroundStyle(MonitorTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MonitorTheme.font(14.5, weight: .medium)).lineLimit(1)
                if let detail {
                    Text(detail).font(MonitorTheme.font(11))
                        .foregroundStyle(detailColor ?? MonitorTheme.muted)
                }
            }
            Spacer(minLength: 0)
            if lock {
                MonitorIcon.lock.frame(width: 13, height: 13).foregroundStyle(MonitorTheme.faint)
            }
            if chevron {
                MonitorIcon.chevronRight.frame(width: 16, height: 16)
                    .foregroundStyle(MonitorTheme.faint)
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
    }

    private func check(_ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MonitorIcon.check.frame(width: 12, height: 12).foregroundStyle(good)
                .frame(width: 20, height: 20).background(good.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MonitorTheme.font(13, weight: .medium))
                if let detail { hint(detail) }
            }
        }
    }

    private func numbered(_ number: Int, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(MonitorTheme.font(11, weight: .bold))
                .foregroundStyle(MonitorTheme.accent)
                .frame(width: 22, height: 22)
                .background(MonitorTheme.accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MonitorTheme.font(13, weight: .medium))
                if let detail { hint(detail) }
            }
        }
    }

    private func secureField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(label)
            HStack(spacing: 0) {
                Group {
                    if reveal {
                        TextField("Password", text: text)
                    } else {
                        SecureField("Password", text: text)
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textContentType(.password)
                .accessibilityIdentifier(id)
                Button {
                    reveal.toggle()
                } label: {
                    (reveal ? MonitorIcon.eyeOff : MonitorIcon.eye).frame(width: 18, height: 18)
                        .foregroundStyle(MonitorTheme.muted).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
            .modifier(InputStyle(trailing: 2))
        }
    }

    private func connectButton(_ title: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button {
            finish(action)
        } label: {
            Text(title).font(MonitorTheme.font(15, weight: .semibold))
                .foregroundStyle(
                    enabled
                        ? Color(red: 6 / 255, green: 16 / 255, blue: 24 / 255) : MonitorTheme.muted
                )
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    enabled ? MonitorTheme.accent : MonitorTheme.raised,
                    in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityIdentifier("addSetup.connect")
    }
}

private struct InputStyle: ViewModifier {
    var trailing: CGFloat = 14
    func body(content: Content) -> some View {
        content.font(MonitorTheme.font(15))
            .padding(.leading, 14).padding(.trailing, trailing)
            .frame(minHeight: 48)
            .background(MonitorTheme.raised, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
