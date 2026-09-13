#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// The complete shared gallery. The thumbnail slot is the sole image-loading seam;
    /// actions remain intents so another camera storefront supplies its own I/O.
    public struct MonitorMediaCatalog<Thumbnail: View, Empty: View, Filters: View>: View {
        private let brand: String
        private let safeArea: EdgeInsets
        private let items: [MonitorMediaItem]
        private let categories: [MonitorMediaCategory]
        private let category: String
        private let layout: MonitorMediaLayout
        private let thumbnailSize: MonitorThumbnailSize
        private let sortTitle: String
        private let status: String
        private let selectedIDs: Set<String>
        private let selecting: Bool
        private let refreshing: Bool
        private let canRefresh: Bool
        private let action: (MonitorMediaAction) -> Void
        private let thumbnail: (MonitorMediaItem) -> Thumbnail
        private let empty: Empty
        private let filters: Filters
        private let tablet: Bool
        @State private var selectionInteraction = MonitorMediaSelectionInteraction()
        @Environment(\.scenePhase) private var scenePhase

        public init(
            brand: String, safeArea: EdgeInsets, items: [MonitorMediaItem],
            categories: [MonitorMediaCategory], category: String, layout: MonitorMediaLayout,
            thumbnailSize: MonitorThumbnailSize, sortTitle: String, status: String,
            selectedIDs: Set<String>, selecting: Bool, refreshing: Bool, canRefresh: Bool,
            tablet: Bool, action: @escaping (MonitorMediaAction) -> Void,
            @ViewBuilder thumbnail: @escaping (MonitorMediaItem) -> Thumbnail,
            @ViewBuilder empty: () -> Empty, @ViewBuilder filters: () -> Filters
        ) {
            self.brand = brand
            self.safeArea = safeArea
            self.items = items
            self.categories = categories
            self.category = category
            self.layout = layout
            self.thumbnailSize = thumbnailSize
            self.sortTitle = sortTitle
            self.status = status
            self.selectedIDs = selectedIDs
            self.selecting = selecting
            self.refreshing = refreshing
            self.canRefresh = canRefresh
            self.tablet = tablet
            self.action = action
            self.thumbnail = thumbnail
            self.empty = empty()
            self.filters = filters()
        }

        public var body: some View {
            MonitorPage(
                safeArea: safeArea, navigationWidth: 206,
                heading: MonitorPageHeading(brand: brand, title: "Media"), backLabel: "Back",
                back: dismiss
            ) { portrait in
                navigation(portrait: portrait)
            } detail: { portrait in
                VStack(alignment: .leading, spacing: 8) {
                    header(portrait: portrait)
                    gallery
                    if selecting { selectionTray }
                    if portrait { displayControls }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { selectionInteraction.cancel() }
            }
            .onDisappear { selectionInteraction.detach() }
        }

        private func dismiss() { action(.back) }

        private func navigation(portrait: Bool) -> some View {
            VStack(alignment: .leading, spacing: 9) {
                ScrollView(portrait ? .horizontal : .vertical, showsIndicators: false) {
                    let arrangement =
                        portrait
                        ? AnyLayout(HStackLayout(spacing: 3))
                        : AnyLayout(VStackLayout(spacing: 3))
                    arrangement {
                        ForEach(categories) { item in
                            MonitorNavigationItem(
                                item.title, count: String(item.count),
                                selected: item.id == category
                            ) {
                                action(.category(item.id))
                            }
                            .fixedSize(horizontal: portrait, vertical: false)
                        }
                    }
                }
                .frame(height: portrait ? 44 : nil)
                if !portrait {
                    VStack(alignment: .leading, spacing: 5) {
                        MonitorSectionHeader("Library")
                        Text(status).font(MonitorTheme.font(9.5)).foregroundStyle(
                            MonitorTheme.muted
                        )
                        .lineLimit(3)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                if !portrait { displayControls }
            }
        }

        private var displayControls: some View {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    layoutButton(.grid, icon: .layoutGrid, label: "Grid view")
                    layoutButton(.list, icon: .menu, label: "List view")
                }
                .padding(3)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                HStack(spacing: 2) {
                    ForEach(MonitorThumbnailSize.allCases, id: \.self) { size in
                        sizeButton(size)
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
            }
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("monitor.media.displayControls")
        }

        private func layoutButton(
            _ mode: MonitorMediaLayout, icon: MonitorIcon, label: String
        ) -> some View {
            let on = layout == mode
            return Button {
                action(.layout(mode))
            } label: {
                icon.view().frame(width: 13, height: 13)
                    .foregroundStyle(on ? Color.white : MonitorTheme.muted)
                    .frame(width: 32, height: 28)
                    .background(
                        on ? Color.white.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("monitor.media.layout.\(mode.rawValue)")
        }

        private func sizeButton(_ size: MonitorThumbnailSize) -> some View {
            let on = size == thumbnailSize
            let dot: CGFloat = size == .small ? 7 : size == .medium ? 10 : 13
            return Button {
                action(.thumbnailSize(size))
            } label: {
                RoundedRectangle(cornerRadius: 3)
                    .fill(on ? Color.white : MonitorTheme.faint)
                    .frame(width: dot, height: dot)
                    .frame(width: 28, height: 28)
                    .background(
                        on ? Color.white.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel("\(size.rawValue.capitalized) thumbnails")
            .accessibilityAddTraits(on ? .isSelected : [])
        }

        @ViewBuilder private func header(portrait: Bool) -> some View {
            if portrait {
                stackedHeader
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        headerCaption.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        toolbar.fixedSize(horizontal: true, vertical: true)
                    }
                    stackedHeader
                }
            }
        }

        private var stackedHeader: some View {
            VStack(alignment: .leading, spacing: 8) {
                headerCaption
                ScrollView(.horizontal, showsIndicators: false) { toolbar }
            }
        }

        private var headerCaption: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if refreshing {
                        ProgressView().controlSize(.mini).tint(MonitorTheme.accent)
                    }
                    Text("\(items.count) items · \(category.lowercased())")
                        .font(MonitorTheme.font(10.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text)
                }
                Text(
                    selecting
                        ? "Swipe to scroll · Hold or drag sideways to select"
                        : "Tap to open · Hold, then drag to select"
                )
                .font(MonitorTheme.font(9)).foregroundStyle(MonitorTheme.faint).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var toolbar: some View {
            HStack(spacing: 6) {
                chip("Sort", icon: .arrowUpDown, text: sortTitle) {
                    action(.cycleSort)
                }
                filters
            }
        }

        private var gallery: some View {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if items.isEmpty {
                            empty.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        } else if layout == .grid {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 10),
                                    count: thumbnailSize.columns(tablet: tablet)), spacing: 10
                            ) {
                                ForEach(items) { item in gridCard(item) }
                            }
                        } else {
                            LazyVStack(spacing: 1) {
                                ForEach(items) { item in listRow(item) }
                            }
                            .background(
                                MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .background(
                        MonitorMediaSelectionBridge(
                            interaction: selectionInteraction, ids: items.map(\.id),
                            selected: selectedIDs, selecting: selecting,
                            context:
                                "\(category)/\(layout.rawValue)/\(thumbnailSize.rawValue)/\(sortTitle)"
                        ) { [action] selection in action(.selection(selection)) })
                }
                .scrollBounceBehavior(.always)
                .refreshable { refresh() }
                .accessibilityIdentifier("monitor.media.gallery")
            }
        }

        private func refresh() {
            if canRefresh && !refreshing { action(.refresh) }
        }

        private func gridCard(_ item: MonitorMediaItem) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail(item)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit).clipped()
                    .overlay(alignment: .topLeading) {
                        if selecting { selectButton(item).padding(2) }
                    }
                    .overlay(alignment: .topTrailing) { favoriteButton(item).padding(2) }
                    .overlay(alignment: .bottomLeading) { stateTag(item).padding(6) }
                    .overlay(alignment: .bottomTrailing) { durationTag(item).padding(6) }
                    .overlay(alignment: .bottom) { progressBar(item) }
                    .contentShape(Rectangle())
                    .onTapGesture { action(selecting ? .select(item.id) : .open(item.id)) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.filename).font(MonitorTheme.font(10.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text)
                    Text(item.metadata).font(MonitorTheme.font(9)).foregroundStyle(
                        MonitorTheme.faint)
                }
                .lineLimit(1).padding(.horizontal, 9).padding(.vertical, 8)
            }
            .background(MonitorTheme.surface).clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { selectedOverlay(item, radius: 11) }
            .background(MonitorMediaSelectionAnchor(id: item.id, interaction: selectionInteraction))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("monitor.media.clip.\(item.id)")
            .accessibilityAction(named: selecting ? "Toggle selection" : "Select clip") {
                action(.select(item.id))
            }
        }

        private func listRow(_ item: MonitorMediaItem) -> some View {
            HStack(spacing: 10) {
                if selecting { selectButton(item) }
                thumbnail(item).frame(width: tablet ? 96 : 76, height: tablet ? 54 : 43)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) { durationTag(item) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.filename).font(MonitorTheme.font(11.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text)
                    Text(item.metadata).font(MonitorTheme.font(9.5)).foregroundStyle(
                        MonitorTheme.faint)
                }
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if tablet {
                    Text(item.format).font(MonitorTheme.font(10.5)).frame(
                        width: 100, alignment: .leading)
                    Text(item.color).font(MonitorTheme.font(9, weight: .bold)).frame(width: 70)
                    stateTag(item)
                }
                favoriteButton(item)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .foregroundStyle(MonitorTheme.secondary)
            .contentShape(Rectangle())
            .onTapGesture { action(selecting ? .select(item.id) : .open(item.id)) }
            .overlay { selectedOverlay(item, radius: 0) }
            .background(MonitorMediaSelectionAnchor(id: item.id, interaction: selectionInteraction))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("monitor.media.clip.\(item.id)")
            .accessibilityAction(named: selecting ? "Toggle selection" : "Select clip") {
                action(.select(item.id))
            }
        }

        private var selectedItems: [MonitorMediaItem] {
            items.filter { selectedIDs.contains($0.id) }
        }

        private func selectionAllows(_ permission: MonitorMediaPermissions, every: Bool = false)
            -> Bool
        {
            !selectedItems.isEmpty
                && (every
                    ? selectedItems.allSatisfy { $0.permissions.contains(permission) }
                    : selectedItems.contains { $0.permissions.contains(permission) })
        }

        private var selectionTray: some View {
            HStack(spacing: 4) {
                Text("\(selectedIDs.count) selected").font(
                    MonitorTheme.font(10.5, weight: .semibold)
                )
                .foregroundStyle(MonitorTheme.text).lineLimit(1)
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        chip("Select all", icon: .circleCheck, text: "All") {
                            action(.selectAll)
                        }
                        chip("Clear selection", icon: .x, text: "Clear") {
                            action(.clearSelection)
                        }
                        chip(
                            "Share selected", icon: .share, text: "Share",
                            active: true
                        ) {
                            action(.shareSelection)
                        }
                        .disabled(!selectionAllows(.share, every: true))
                        chip("Cache selected", icon: .download) { action(.cacheSelection) }
                            .disabled(!selectionAllows(.cache))
                        chip("Favorite selected", icon: .star) { action(.favoriteSelection) }
                            .disabled(!selectionAllows(.favorite))
                        chip("Delete selected", icon: .trash, danger: true) {
                            action(.deleteSelection)
                        }
                        .disabled(!selectionAllows(.delete, every: true))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6).monitorCardSurface()
        }

        private func chip(
            _ label: String, icon: MonitorIcon, filled: Bool = false, text: String? = nil,
            active: Bool = false,
            iconSize: CGFloat = 13, danger: Bool = false, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 7) {
                    icon.view(filled: filled).frame(width: iconSize, height: iconSize)
                    if let text {
                        Text(text).font(MonitorTheme.font(10.5, weight: .semibold)).lineLimit(1)
                    }
                }
                .foregroundStyle(
                    danger
                        ? MonitorTheme.recording
                        : active ? MonitorTheme.text : MonitorTheme.secondary
                )
                .padding(.horizontal, text == nil ? 9 : 11).frame(minWidth: 44, minHeight: 44)
                .background(
                    active ? MonitorTheme.accent.opacity(0.18) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(MonitorButtonStyle()).accessibilityLabel(label)
        }

        private func selectButton(_ item: MonitorMediaItem) -> some View {
            Button {
                action(.select(item.id))
            } label: {
                (selectedIDs.contains(item.id) ? MonitorIcon.circleCheck : .circle)
                    .frame(width: 22, height: 22).foregroundStyle(
                        selectedIDs.contains(item.id) ? MonitorTheme.accent : .white.opacity(0.7)
                    )
                    .background(.black.opacity(0.4), in: Circle()).frame(width: 44, height: 44)
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(
                selectedIDs.contains(item.id)
                    ? "Deselect \(item.filename)" : "Select \(item.filename)")
        }

        private func favoriteButton(_ item: MonitorMediaItem) -> some View {
            Button {
                action(.favorite(item.id))
            } label: {
                MonitorIcon.star.view(filled: item.favorite).frame(width: 13, height: 13)
                    .foregroundStyle(
                        item.favorite ? MonitorTheme.color(0xE9C35A) : .white.opacity(0.7)
                    )
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(MonitorButtonStyle()).disabled(!item.permissions.contains(.favorite))
            .accessibilityLabel(item.favorite ? "Remove favorite" : "Add favorite")
        }

        private func stateTag(_ item: MonitorMediaItem) -> some View {
            Text(item.stateLabel).font(MonitorTheme.font(8, weight: .bold)).tracking(0.4)
                .foregroundStyle(
                    item.progress != nil
                        ? MonitorTheme.accent
                        : item.availability == .original
                            ? MonitorTheme.color(0x3FD3A3) : MonitorTheme.muted
                )
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 4))
        }

        private func durationTag(_ item: MonitorMediaItem) -> some View {
            Text(item.duration).font(MonitorTheme.font(9.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                .background(
                    item.duration.isEmpty ? .clear : .black.opacity(0.66),
                    in: RoundedRectangle(cornerRadius: 4))
        }

        @ViewBuilder private func progressBar(_ item: MonitorMediaItem) -> some View {
            if let progress = item.progress {
                GeometryReader { proxy in
                    Rectangle().fill(MonitorTheme.accent)
                        .frame(width: proxy.size.width * min(1, max(0, progress)))
                }
                .frame(height: 3).background(.black.opacity(0.5))
            }
        }

        @ViewBuilder private func selectedOverlay(_ item: MonitorMediaItem, radius: CGFloat)
            -> some View
        {
            if selectedIDs.contains(item.id) {
                RoundedRectangle(cornerRadius: radius).fill(MonitorTheme.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius).strokeBorder(
                            MonitorTheme.accent, lineWidth: 2)
                    )
                    .allowsHitTesting(false)
            }
        }
    }
#endif
