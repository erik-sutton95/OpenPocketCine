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
            onForget: ((String) -> Void)? = nil
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
        }

        @Environment(\.monitorWindowGeometry) private var windowGeometry

        public var body: some View {
            GeometryReader { proxy in
                let tablet = min(proxy.size.width, proxy.size.height) >= 600
                let fullLabels = proxy.size.width > proxy.size.height || tablet
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
                            CameraPageGlyph(icon: .plus).stroke(
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            ).frame(width: 14, height: 14)
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
                .padding(.leading, safeArea.leading + 18)
                .padding(.trailing, safeArea.trailing + 18)
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
                CameraPageGlyph(icon: icon).stroke(
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                )
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
                    ForEach(items) { item in cameraCard(item, saved: saved) }
                }
            }
        }

        private func cameraCard(_ item: CameraListItem, saved: Bool) -> some View {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    CameraPageGlyph(icon: .camera).stroke(
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 19, height: 19).foregroundStyle(
                        item.isPrimary ? MonitorTheme.accent : MonitorTheme.muted
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        item.isPrimary
                            ? MonitorTheme.accent.opacity(0.14) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        activate(item, saved: saved)
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
                        ForEach(item.details) { detail in
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
                HStack(spacing: 7) {
                    if item.isBusy {
                        CameraProgressLabel(title: item.status)
                    } else {
                        Text(item.status).font(MonitorTheme.font(9.5)).foregroundStyle(
                            item.isAvailable ? MonitorTheme.muted : MonitorTheme.faint
                        ).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if saved && (onRename != nil || onForget != nil) {
                        Menu {
                            if onRename != nil {
                                Button("Rename") {
                                    renameText = item.name
                                    renameItem = item
                                }
                            }
                            if onForget != nil {
                                Button("Remove", role: .destructive) { removeItem = item }
                            }
                        } label: {
                            CameraPageGlyph(icon: .more).stroke(lineWidth: 1.8).frame(
                                width: 15, height: 15
                            ).frame(width: 36, height: 44)
                        }.disabled(busy).accessibilityLabel("Options for \(item.name)")
                    }
                    Button {
                        if item.isBusy { onCancel() } else { activate(item, saved: saved) }
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

        private func activate(_ item: CameraListItem, saved: Bool) {
            guard !busy else { return }
            if saved { onConnect(item.id) } else { onPair(item.id) }
        }
    }
#endif
