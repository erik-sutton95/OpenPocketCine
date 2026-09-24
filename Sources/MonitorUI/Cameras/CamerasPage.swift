#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Brand-independent camera home. Connections and persistence are injected actions;
    /// the page never creates a camera session or owns a discovery timer.
    public struct CamerasPage: View {
        public var brandName: String
        public var paired: [CameraListItem]
        public var nearby: [CameraListItem]
        public var scanning: Bool
        public var busy: Bool
        public var safeArea: EdgeInsets
        public var onConnect: (String) -> Void
        public var onPair: (String?) -> Void
        public var onCancel: () -> Void
        public var onMedia: () -> Void
        public var onSettings: () -> Void
        public var onMultiview: (() -> Void)?
        public var onWatchFeed: (() -> Void)?
        public var onRename: ((String, String) -> Void)?
        public var onForget: ((String) -> Void)?
        /// Camera id, setup id. Nil hides setup chips.
        public var onConnectSetup: ((String, String) -> Void)?
        public var onAddSetup: ((String) -> Void)?
        public var onForgetSetup: ((String, String) -> Void)?
        /// Camera id, `CameraConnectFailure.Action` id.
        public var onFailureAction: ((String, String) -> Void)?

        @State private var renameItem: CameraListItem?
        @State private var removeItem: CameraListItem?
        @State private var renameText = ""

        public init(
            brandName: String, paired: [CameraListItem], nearby: [CameraListItem],
            scanning: Bool, busy: Bool, safeArea: EdgeInsets = EdgeInsets(),
            onConnect: @escaping (String) -> Void, onPair: @escaping (String?) -> Void,
            onCancel: @escaping () -> Void, onMedia: @escaping () -> Void,
            onSettings: @escaping () -> Void, onMultiview: (() -> Void)? = nil,
            onWatchFeed: (() -> Void)? = nil, onRename: ((String, String) -> Void)? = nil,
            onForget: ((String) -> Void)? = nil,
            onConnectSetup: ((String, String) -> Void)? = nil,
            onAddSetup: ((String) -> Void)? = nil,
            onForgetSetup: ((String, String) -> Void)? = nil,
            onFailureAction: ((String, String) -> Void)? = nil
        ) {
            self.brandName = brandName
            self.paired = paired
            self.nearby = nearby
            self.scanning = scanning
            self.busy = busy
            self.safeArea = safeArea
            self.onConnect = onConnect
            self.onPair = onPair
            self.onCancel = onCancel
            self.onMedia = onMedia
            self.onSettings = onSettings
            self.onMultiview = onMultiview
            self.onWatchFeed = onWatchFeed
            self.onRename = onRename
            self.onForget = onForget
            self.onConnectSetup = onConnectSetup
            self.onAddSetup = onAddSetup
            self.onForgetSetup = onForgetSetup
            self.onFailureAction = onFailureAction
        }

        @Environment(\.monitorWindowGeometry) private var windowGeometry

        public var body: some View {
            GeometryReader { proxy in
                let tablet = min(proxy.size.width, proxy.size.height) >= 600
                let landscape = proxy.size.width > proxy.size.height
                let sideInset = max(safeArea.leading, safeArea.trailing)
                let fullLabels = landscape || tablet
                VStack(spacing: 12) {
                    header(tablet: tablet, fullLabels: fullLabels)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            cameraGroup(
                                "PAIRED", note: "tap to reconnect", items: paired, saved: true,
                                tablet: tablet)
                            if !nearby.isEmpty {
                                cameraGroup(
                                    "NEARBY", note: "announcing over Bluetooth", items: nearby,
                                    saved: false, tablet: tablet)
                            }
                            if paired.isEmpty && nearby.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No cameras saved yet").font(
                                        MonitorTheme.font(15, weight: .semibold))
                                    Text("Pair a new camera to start monitoring.")
                                        .font(MonitorTheme.font(12)).foregroundStyle(
                                            MonitorTheme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(
                                    MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    Button {
                        onPair(nil)
                    } label: {
                        HStack(spacing: 9) {
                            CameraPageGlyph(icon: .plus).frame(width: 14, height: 14)
                            Text("Pair a new camera").font(MonitorTheme.font(13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(
                            Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11).stroke(
                                MonitorTheme.secondary.opacity(0.22), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(busy).opacity(busy ? 0.4 : 1)
                    .accessibilityIdentifier("cameras.pair")
                }
                .padding(.top, safeArea.top + windowGeometry.topControlInset + 14)
                .padding(.leading, (landscape ? sideInset : safeArea.leading) + 18)
                .padding(.trailing, (landscape ? sideInset : safeArea.trailing) + 18)
                .padding(.bottom, safeArea.bottom + 12)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(MonitorTheme.background).foregroundStyle(MonitorTheme.text)
            .alert(
                "Rename camera",
                isPresented: Binding(
                    get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })
            ) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameItem = nil }
                Button("Save") {
                    if let item = renameItem, !busy { onRename?(item.id, renameText) }
                    renameItem = nil
                }.disabled(busy)
            } message: {
                Text("Give this camera a name you'll recognize.")
            }
            .alert(
                "Remove camera?",
                isPresented: Binding(
                    get: { removeItem != nil }, set: { if !$0 { removeItem = nil } })
            ) {
                Button("Cancel", role: .cancel) { removeItem = nil }
                Button("Remove", role: .destructive) {
                    if let item = removeItem, !busy { onForget?(item.id) }
                    removeItem = nil
                }.disabled(busy)
            } message: {
                Text(
                    "This removes \(removeItem?.name ?? "the camera") from this phone. You can pair it again later."
                )
            }
        }

        private func header(tablet: Bool, fullLabels: Bool) -> some View {
            HStack(spacing: fullLabels ? 12 : 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brandName.uppercased()).font(MonitorTheme.font(8.5, weight: .bold))
                        .tracking(1.7).foregroundStyle(MonitorTheme.accent).lineLimit(1)
                    Text("Your cameras").font(
                        MonitorTheme.font(tablet ? 24 : 19, weight: .semibold)
                    )
                    .tracking(-0.2).lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if scanning {
                    HStack(spacing: 7) {
                        Circle().fill(MonitorTheme.accent).frame(width: 6, height: 6)
                            .monitorPulse(period: MonitorMotion.scanPulseDuration)
                        if fullLabels {
                            Text("SCANNING").font(MonitorTheme.font(9.5, weight: .bold)).tracking(
                                1.1)
                        }
                    }
                    .foregroundStyle(MonitorTheme.accent).padding(.horizontal, fullLabels ? 12 : 10)
                    .frame(height: tablet ? 48 : 43)
                    .background(
                        MonitorTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(
                            MonitorTheme.accent.opacity(0.24), lineWidth: 1)
                    )
                    .accessibilityLabel("Scanning for cameras")
                }
                if let onMultiview {
                    Menu {
                        Button("Open Multiview", action: onMultiview).disabled(busy)
                        if let onWatchFeed {
                            Button("Watch a feed", action: onWatchFeed).disabled(busy)
                        }
                    } label: {
                        headerIcon(
                            .grid, title: fullLabels ? "Multi-view" : nil, tablet: tablet,
                            accented: true)
                    } primaryAction: {
                        if !busy { onMultiview() }
                    }
                    .disabled(busy).accessibilityLabel("Open Multiview")
                    .accessibilityHint("Touch and hold for Watch a feed")
                    .accessibilityIdentifier("cameras.multiview")
                } else if let onWatchFeed {
                    Button(action: onWatchFeed) { headerIcon(.eye, tablet: tablet) }.disabled(busy)
                        .accessibilityLabel("Watch a feed").accessibilityIdentifier(
                            "cameras.watchFeed")
                }
                Button(action: onMedia) { headerIcon(.film, tablet: tablet) }
                    .accessibilityLabel("Media library").accessibilityIdentifier("cameras.media")
                Button(action: onSettings) { headerIcon(.settings, tablet: tablet) }
                    .accessibilityLabel("Settings").accessibilityIdentifier("cameras.settings")
            }
            .buttonStyle(.plain)
        }

        private func headerIcon(
            _ icon: CameraPageIcon, title: String? = nil, tablet: Bool, accented: Bool = false
        ) -> some View {
            HStack(spacing: 8) {
                CameraPageGlyph(icon: icon)
                    .foregroundStyle(accented ? MonitorTheme.accent : MonitorTheme.secondary)
                    .frame(width: tablet ? 26 : 23, height: tablet ? 26 : 23)
                if let title {
                    Text(title).font(MonitorTheme.font(12.5, weight: .semibold)).fixedSize()
                }
            }
            .padding(.horizontal, 11).frame(height: tablet ? 48 : 43)
            .background(
                accented ? MonitorTheme.accent.opacity(0.12) : MonitorTheme.secondary.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    accented ? MonitorTheme.accent.opacity(0.3) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }

        private func cameraGroup(
            _ title: String, note: String, items: [CameraListItem], saved: Bool, tablet: Bool
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(title).font(MonitorTheme.font(8.5, weight: .bold)).tracking(1.7)
                    Text(note).font(MonitorTheme.font(9)).tracking(0.9)
                }.foregroundStyle(MonitorTheme.faint)
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8), count: tablet ? 2 : 1),
                    spacing: 8
                ) {
                    cameraRows(items, saved: saved)
                }
            }
        }

        private func cameraRows(_ items: [CameraListItem], saved: Bool)
            -> ForEach<[CameraListItem], String, CameraCatalogCard>
        {
            let rename: (@MainActor @Sendable (CameraListItem) -> Void)?
            if onRename == nil {
                rename = nil
            } else {
                rename = { item in
                    renameText = item.name
                    renameItem = item
                }
            }
            let remove: (@MainActor @Sendable (CameraListItem) -> Void)?
            if onForget == nil {
                remove = nil
            } else {
                remove = { item in removeItem = item }
            }
            var connectSetup: (@MainActor @Sendable (CameraListItem, CameraSetupChip) -> Void)?
            if let onConnectSetup {
                connectSetup = { item, setup in if !busy { onConnectSetup(item.id, setup.id) } }
            }
            var addSetup: (@MainActor @Sendable (CameraListItem) -> Void)?
            if let onAddSetup {
                addSetup = { item in if !busy { onAddSetup(item.id) } }
            }
            var forgetSetup: (@MainActor @Sendable (CameraListItem, CameraSetupChip) -> Void)?
            if let onForgetSetup {
                forgetSetup = { item, setup in if !busy { onForgetSetup(item.id, setup.id) } }
            }
            var failureAction: (@MainActor @Sendable (CameraListItem, String) -> Void)?
            if let onFailureAction {
                failureAction = { item, action in if !busy { onFailureAction(item.id, action) } }
            }
            let actions = CameraCatalogActions(
                activate: { activate($0, saved: saved) }, cancel: { onCancel() },
                rename: rename, remove: remove, connectSetup: connectSetup, addSetup: addSetup,
                forgetSetup: forgetSetup, failureAction: failureAction)
            return CameraCatalogRows.make(items, saved: saved, busy: busy, actions: actions)
        }

        private func activate(_ item: CameraListItem, saved: Bool) {
            guard !busy else { return }
            if saved { onConnect(item.id) } else { onPair(item.id) }
        }
    }
    /// Rendering a lazy camera collection only copies immutable row values.
    /// Native session and rename/remove bindings are captured as MainActor actions.
    struct CameraCatalogActions: Sendable {
        let activate: @MainActor @Sendable (CameraListItem) -> Void
        let cancel: @MainActor @Sendable () -> Void
        let rename: (@MainActor @Sendable (CameraListItem) -> Void)?
        let remove: (@MainActor @Sendable (CameraListItem) -> Void)?
        var connectSetup: (@MainActor @Sendable (CameraListItem, CameraSetupChip) -> Void)? = nil
        var addSetup: (@MainActor @Sendable (CameraListItem) -> Void)? = nil
        var forgetSetup: (@MainActor @Sendable (CameraListItem, CameraSetupChip) -> Void)? = nil
        var failureAction: (@MainActor @Sendable (CameraListItem, String) -> Void)? = nil
    }

    enum CameraCatalogRows {
        nonisolated static func make(
            _ items: [CameraListItem], saved: Bool, busy: Bool, actions: CameraCatalogActions
        ) -> ForEach<[CameraListItem], String, CameraCatalogCard> {
            ForEach(items) { item in
                CameraCatalogCard(item: item, saved: saved, busy: busy, actions: actions)
            }
        }
    }

    struct CameraCatalogCard: View {
        nonisolated let item: CameraListItem
        nonisolated let saved: Bool
        nonisolated let busy: Bool
        nonisolated let actions: CameraCatalogActions

        nonisolated init(
            item: CameraListItem, saved: Bool, busy: Bool, actions: CameraCatalogActions
        ) {
            self.item = item
            self.saved = saved
            self.busy = busy
            self.actions = actions
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    CameraPageGlyph(icon: .camera)
                        .frame(width: 19, height: 19).foregroundStyle(
                            item.isPrimary ? MonitorTheme.accent : MonitorTheme.muted
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            item.isPrimary
                                ? MonitorTheme.accent.opacity(0.14) : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        actions.activate(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(MonitorTheme.font(14.5, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text(item.subtitle).font(MonitorTheme.font(9.5)).foregroundStyle(
                                MonitorTheme.muted
                            ).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy)
                    if !item.badge.isEmpty {
                        Text(item.badge).font(MonitorTheme.font(8, weight: .bold)).tracking(1.1)
                            .foregroundStyle(
                                item.isPrimary ? MonitorTheme.accent : MonitorTheme.muted
                            )
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                item.isPrimary
                                    ? MonitorTheme.accent.opacity(0.16) : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .lineLimit(1).fixedSize()
                    }
                    if let bars = item.signalBars { CameraSignalBars(count: bars) }
                }
                if !item.details.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), alignment: .leading)],
                        alignment: .leading, spacing: 8
                    ) {
                        MonitorSnapshotRows(item.details) { detail in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.title.uppercased()).font(
                                    MonitorTheme.font(8, weight: .bold)
                                ).tracking(1.2).foregroundStyle(MonitorTheme.faint)
                                Text(detail.value).font(MonitorTheme.font(10.5, weight: .semibold))
                                    .foregroundStyle(MonitorTheme.secondary)
                            }
                        }
                    }
                }
                if saved, let connect = actions.connectSetup, !item.setups.isEmpty {
                    setupChips(connect: connect)
                }
                if item.isBusy, !item.steps.isEmpty {
                    CameraConnectProgress(steps: item.steps)
                }
                if let failure = item.failure, !item.isBusy {
                    failureBanner(failure)
                }
                HStack(spacing: 7) {
                    if item.isBusy, !item.steps.isEmpty {
                        Text(CameraConnectProgress.caption(item.steps))
                            .font(MonitorTheme.font(10.5)).foregroundStyle(MonitorTheme.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                            .animation(
                                .easeInOut(duration: 0.25),
                                value: CameraConnectProgress.caption(item.steps))
                    } else if item.isBusy {
                        CameraProgressLabel(title: item.status)
                    } else if item.failure == nil {
                        Text(item.status).font(MonitorTheme.font(9.5)).foregroundStyle(
                            item.isAvailable ? MonitorTheme.muted : MonitorTheme.faint
                        ).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if saved && (actions.rename != nil || actions.remove != nil) {
                        Menu {
                            if let rename = actions.rename {
                                Button("Rename") { rename(item) }
                            }
                            if let remove = actions.remove {
                                Button("Remove", role: .destructive) { remove(item) }
                            }
                        } label: {
                            CameraPageGlyph(icon: .more).frame(
                                width: 15, height: 15
                            ).frame(width: 36, height: 44)
                        }.disabled(busy).accessibilityLabel("Options for \(item.name)")
                    }
                    if let failure = item.failure, !item.isBusy, let act = actions.failureAction {
                        ForEach(failure.actions) { action in
                            Button(action.title) { act(item, action.id) }
                                .buttonStyle(CameraPageButtonStyle(primary: action.primary))
                                .disabled(busy)
                        }
                    } else {
                        Button {
                            if item.isBusy { actions.cancel() } else { actions.activate(item) }
                        } label: {
                            Text(item.isBusy ? "Cancel" : item.actionTitle)
                        }
                        .buttonStyle(CameraPageButtonStyle(primary: item.isPrimary && !item.isBusy))
                        .disabled(busy && !item.isBusy)
                        .accessibilityLabel(
                            item.isBusy
                                ? "Cancel connecting to \(item.name)"
                                : "\(item.actionTitle) \(item.name)")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(
                item.isPrimary
                    ? Color(red: 28 / 255, green: 30 / 255, blue: 31 / 255)
                    : Color(red: 23 / 255, green: 24 / 255, blue: 25 / 255),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13).stroke(
                    item.isPrimary ? MonitorTheme.accent.opacity(0.26) : Color.white.opacity(0.06),
                    lineWidth: 1))
        }

        /// OpenZCine-style setup tabs: one per way in, plus Add setup. Scrolls sideways
        /// rather than truncating on a portrait phone.
        private func setupChips(
            connect: @escaping @MainActor @Sendable (CameraListItem, CameraSetupChip) -> Void
        ) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(item.setups) { setup in
                        Button {
                            connect(item, setup)
                        } label: {
                            chipLabel(setup.title, active: setup.isActive)
                        }
                        .buttonStyle(.plain).disabled(busy)
                        .contextMenu {
                            if setup.canForget, let forget = actions.forgetSetup {
                                Button("Forget \(setup.title) setup", role: .destructive) {
                                    forget(item, setup)
                                }
                            }
                        }
                        .accessibilityLabel("Connect \(item.name) over \(setup.title)")
                        .accessibilityIdentifier("cameras.setup.\(setup.id)")
                    }
                    if item.canAddSetup, let add = actions.addSetup {
                        Button {
                            add(item)
                        } label: {
                            HStack(spacing: 6) {
                                CameraPageGlyph(icon: .plus).frame(width: 11, height: 11)
                                Text("Add setup")
                            }
                            .font(MonitorTheme.font(11, weight: .semibold))
                            .foregroundStyle(MonitorTheme.muted)
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9).stroke(
                                    MonitorTheme.secondary.opacity(0.22),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                            .padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(busy)
                        .accessibilityLabel("Add a setup for \(item.name)")
                        .accessibilityIdentifier("cameras.addSetup")
                    }
                }
            }
        }

        private func failureBanner(_ failure: CameraConnectFailure) -> some View {
            let warning = MonitorTheme.linkHealthColor(.watch)
            return HStack(alignment: .top, spacing: 12) {
                MonitorIcon.triangleAlert.frame(width: 20, height: 20).foregroundStyle(warning)
                VStack(alignment: .leading, spacing: 5) {
                    Text(failure.title).font(MonitorTheme.font(13.5, weight: .semibold))
                    Text(failure.message).font(MonitorTheme.font(11.5))
                        .foregroundStyle(MonitorTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let link = failure.link, let act = actions.failureAction {
                        Button(link.title) { act(item, link.id) }
                            .font(MonitorTheme.font(12, weight: .semibold))
                            .foregroundStyle(MonitorTheme.accent)
                            .frame(minHeight: 44).contentShape(Rectangle())
                            .buttonStyle(.plain).disabled(busy)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 12)
            .padding(.bottom, failure.link == nil ? 12 : 0)
            .background(warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(warning.opacity(0.3), lineWidth: 1))
            .accessibilityElement(children: .contain)
        }

        private func chipLabel(_ title: String, active: Bool) -> some View {
            Text(title).font(MonitorTheme.font(11, weight: .semibold))
                .foregroundStyle(active ? Color.white : MonitorTheme.muted)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(
                    active ? MonitorTheme.accent.opacity(0.16) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9).stroke(
                        active ? MonitorTheme.accent.opacity(0.45) : Color.white.opacity(0.06),
                        lineWidth: 1)
                )
                // 34 pt chip, 44 pt tap target.
                .padding(.vertical, 5).contentShape(Rectangle())
        }
    }

    /// Connection progress as one bar that fills per step with a sweep running through it.
    /// The card shows `caption` beside Cancel.
    struct CameraConnectProgress: View {
        let steps: [CameraConnectStep]
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var sweep = false

        static func caption(_ steps: [CameraConnectStep]) -> String {
            guard
                let step = steps.first(where: { $0.state == .active })
                    ?? steps.last(where: { $0.state == .done })
            else { return "Connecting" }
            return step.detail.isEmpty ? step.title : "\(step.title) · \(step.detail)"
        }

        private var fraction: Double {
            let done = steps.filter { $0.state == .done }.count
            let active = steps.contains { $0.state == .active } ? 0.5 : 0
            return max(0.06, min(1, (Double(done) + active) / Double(max(steps.count, 1))))
        }

        var body: some View {
            GeometryReader { proxy in
                let fill = proxy.size.width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(MonitorTheme.accent).frame(width: fill)
                        .overlay(alignment: .leading) {
                            if !reduceMotion {
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.55), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: 70)
                                .offset(x: sweep ? fill : -70)
                            }
                        }
                        .clipShape(Capsule())
                        .animation(.easeInOut(duration: 0.45), value: fraction)
                }
            }
            .frame(height: 4)
            .padding(.vertical, 2)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.caption(steps))
            .accessibilityValue("\(Int(fraction * 100)) percent")
        }
    }
#endif
