import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// "Add setup" on a saved camera (#406): Wi-Fi (a router) or Hotspot (this phone).
/// A sheet in portrait; a centered card in landscape, like Multiview's network setup.
/// Saving connects over the new setup at once; Camera Wi-Fi stays as the other chip.
struct AddSetupView: View {
    enum Page: Equatable {
        case choose, networks, hotspot
        case password(String)
    }

    let camera: SavedCamera
    /// Nil when the camera is not nearby over Bluetooth.
    var scan: (() async throws -> [String])?
    var save: (CameraConnectionSetup, String, String) -> Void
    var close: () -> Void
    @State var page: Page = .choose

    @State private var currentSSID: String?
    @State private var found: [String] = []
    @State private var scanning = false
    @State private var scanFailed = false
    @State private var otherNetwork = false
    @State private var otherName = ""
    @State private var password = ""
    @State private var hotspotName = ""
    @State private var hotspotPassword = ""
    @State private var reveal = false
    @State private var hotspotActive = false
    @Environment(\.openURL) private var openURL

    private let sheet = Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)
    private var warning: Color { MonitorTheme.linkHealthColor(.watch) }
    private var good: Color { MonitorTheme.linkHealthColor(.stable) }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            // Portrait: the sheet runs through the home-indicator area like a system sheet.
            let bottomInset = landscape ? 0 : proxy.safeAreaInsets.bottom
            ZStack(alignment: landscape ? .center : .bottom) {
                Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: close)
                VStack(spacing: 0) {
                    if !landscape {
                        Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 5)
                            .padding(.top, 7)
                    }
                    navBar
                    Group {
                        if landscape {
                            content(landscape: true).padding(.horizontal, 18).padding(.bottom, 16)
                        } else {
                            ScrollView {
                                content(landscape: false).padding(.horizontal, 18)
                                    .padding(.bottom, 24 + bottomInset)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(
                    width: landscape ? min(600, proxy.size.width) : proxy.size.width,
                    height: landscape
                        ? min(400, proxy.size.height - 12)
                        : max(0, proxy.size.height - 44 + bottomInset)
                )
                .background(
                    sheet,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: landscape ? 16 : 0,
                        bottomTrailingRadius: landscape ? 16 : 0, topTrailingRadius: 16)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: landscape ? 16 : 0,
                        bottomTrailingRadius: landscape ? 16 : 0, topTrailingRadius: 16
                    )
                    .stroke(Color.white.opacity(landscape ? 0.08 : 0), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("addSetup")
            }
            .ignoresSafeArea(.container, edges: landscape ? [] : .bottom)
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
            let current = await WiFiJoiner.currentSSID()
            // The camera's own access point is not a network to move it onto.
            if let current, !current.lowercased().hasPrefix("osmo") { currentSSID = current }
        }
        .task {
            while !Task.isCancelled {
                hotspotActive = SharedWiFiPath.address(hotspot: true) != nil
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onAppear { prefill(page) }
    }

    // MARK: Navigation

    private var navBar: some View {
        HStack {
            Button {
                switch page {
                case .choose: close()
                case .networks, .hotspot: open(.choose)
                case .password: open(.networks)
                }
            } label: {
                HStack(spacing: 4) {
                    if page != .choose {
                        MonitorIcon.chevronLeft.frame(width: 18, height: 18)
                    }
                    Text(page == .choose ? "Cancel" : "Back")
                }
                .foregroundStyle(MonitorTheme.accent)
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title).font(MonitorTheme.font(15, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 88, height: 44)
        }
        .padding(.horizontal, 12).padding(.top, 2)
    }

    private var title: String {
        switch page {
        case .choose: "Add setup"
        case .networks, .password: "Wi-Fi"
        case .hotspot: "Hotspot"
        }
    }

    private func open(_ next: Page) {
        prefill(next)
        page = next
    }

    private func prefill(_ next: Page) {
        reveal = false
        switch next {
        case .password(let ssid):
            password = MultiviewNetworkStore.load(ssid: ssid, hotspot: false)?.password ?? ""
        case .hotspot:
            // A hotspot saved by Multiview or another camera is this same phone's.
            let known =
                camera.hotspotSSID.flatMap { MultiviewNetworkStore.load(ssid: $0, hotspot: true) }
                ?? MultiviewNetworkStore.savedNetworks().last { $0.hotspot == true }
            hotspotName = known?.ssid ?? camera.hotspotSSID ?? ""
            hotspotPassword = known?.password ?? ""
        case .choose, .networks: break
        }
    }

    @ViewBuilder private func content(landscape: Bool) -> some View {
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
                .foregroundStyle(MonitorTheme.muted).padding(.top, 10)
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

    private var savedNetworks: [String] {
        MultiviewNetworkStore.savedNetworks().filter { $0.hotspot != true }.map(\.ssid)
            .filter { $0 != currentSSID }
    }

    private func networksPage(_ landscape: Bool) -> some View {
        let left = VStack(alignment: .leading, spacing: 7) {
            if !landscape {
                Text("Choose the network").font(MonitorTheme.font(22, weight: .semibold))
                    .padding(.top, 6)
                hint("The camera and this iPhone must be on the same Wi-Fi.").padding(.bottom, 8)
            }
            if let currentSSID {
                sectionLabel("THIS IPHONE IS ON")
                group { networkRow(currentSSID, detail: "Connected", detailColor: good) }
            }
            if !savedNetworks.isEmpty {
                sectionLabel("SAVED ON THIS IPHONE").padding(.top, 6)
                group {
                    ForEach(Array(savedNetworks.enumerated()), id: \.element) { index, name in
                        if index > 0 { divider }
                        networkRow(name)
                    }
                }
            }
        }
        let right = VStack(alignment: .leading, spacing: 7) {
            sectionLabel("MORE").padding(.top, landscape ? 0 : 6)
            group {
                Button {
                    runScan()
                } label: {
                    row(
                        icon: scanning ? nil : .scan, title: "Scan with the camera",
                        detail: scanning
                            ? "Scanning… about 20 s"
                            : scan == nil
                                ? "Turn the camera on to scan"
                                : scanFailed ? "Scan did not finish. Try again." : "About 20 s",
                        showsProgress: scanning)
                }
                .buttonStyle(.plain).disabled(scan == nil || scanning)
                .accessibilityIdentifier("addSetup.scan")
                divider
                Button {
                    otherName = ""
                    otherNetwork = true
                } label: {
                    row(icon: .plus, title: "Other network…", detail: nil)
                }
                .buttonStyle(.plain).disabled(scanning)
            }
            if !found.isEmpty {
                sectionLabel("FOUND BY THE CAMERA").padding(.top, 6)
                group {
                    ForEach(Array(found.enumerated()), id: \.element) { index, name in
                        if index > 0 { divider }
                        networkRow(name)
                    }
                }
            }
            if landscape {
                hint("The camera and this iPhone must be on the same Wi-Fi.").padding(.top, 4)
            }
        }
        return Group {
            if landscape {
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        left.frame(maxWidth: .infinity)
                        right.frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    left
                    right
                }
            }
        }
    }

    private func runScan() {
        guard let scan, !scanning else { return }
        scanning = true
        scanFailed = false
        Task {
            do {
                found = try await scan()
            } catch {
                scanFailed = true
            }
            scanning = false
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
        .buttonStyle(.plain).disabled(scanning)
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
                    network.padding(.top, 10)
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
            TextField("Hotspot name", text: $hotspotName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .modifier(InputStyle())
                .accessibilityIdentifier("addSetup.hotspotName")
            if !landscape { hint("Same as Settings › General › About › Name.") }
        }
        let pass = secureField(
            "HOTSPOT PASSWORD", text: $hotspotPassword, id: "addSetup.hotspotPassword")
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
                    status.padding(.top, 10)
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
        lock: Bool = false, showsProgress: Bool = false
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
            MonitorIcon.chevronRight.frame(width: 16, height: 16)
                .foregroundStyle(MonitorTheme.faint)
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
            action()
            close()
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
