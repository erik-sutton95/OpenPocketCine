#if os(iOS)
    import SwiftUI

    /// Filter body shared by brand media pages. Native calendars stay in the shell.
    public struct MonitorMediaFilterForm: View {
        public struct ColorOption: Identifiable, Equatable, Sendable {
            public var id: UInt8
            public var label: String
            public init(id: UInt8, label: String) {
                self.id = id
                self.label = label
            }
        }

        public var formats: [String]
        public var resolutions: [String]
        public var colors: [ColorOption]
        public var formatSelection: Set<String>
        public var resolutionSelection: Set<String>
        public var colorSelection: Set<UInt8>
        public var dateStartLabel: String?
        public var dateEndLabel: String?
        public var hasDates: Bool
        public var onToggleFormat: (String) -> Void
        public var onToggleResolution: (String) -> Void
        public var onToggleColor: (UInt8) -> Void
        public var onPickStart: () -> Void
        public var onPickEnd: () -> Void
        public var onClear: () -> Void

        public init(
            formats: [String], resolutions: [String], colors: [ColorOption],
            formatSelection: Set<String>, resolutionSelection: Set<String>,
            colorSelection: Set<UInt8>, dateStartLabel: String?, dateEndLabel: String?,
            hasDates: Bool, onToggleFormat: @escaping (String) -> Void,
            onToggleResolution: @escaping (String) -> Void,
            onToggleColor: @escaping (UInt8) -> Void, onPickStart: @escaping () -> Void,
            onPickEnd: @escaping () -> Void, onClear: @escaping () -> Void
        ) {
            self.formats = formats
            self.resolutions = resolutions
            self.colors = colors
            self.formatSelection = formatSelection
            self.resolutionSelection = resolutionSelection
            self.colorSelection = colorSelection
            self.dateStartLabel = dateStartLabel
            self.dateEndLabel = dateEndLabel
            self.hasDates = hasDates
            self.onToggleFormat = onToggleFormat
            self.onToggleResolution = onToggleResolution
            self.onToggleColor = onToggleColor
            self.onPickStart = onPickStart
            self.onPickEnd = onPickEnd
            self.onClear = onClear
        }

        private var empty: Bool {
            formats.isEmpty && resolutions.isEmpty && !hasDates && colors.isEmpty
        }

        private var active: Bool {
            !formatSelection.isEmpty || !resolutionSelection.isEmpty || !colorSelection.isEmpty
                || dateStartLabel != nil || dateEndLabel != nil
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if !formats.isEmpty { chipSection("FORMAT", formats, formatSelection, onToggleFormat) }
                if !resolutions.isEmpty {
                    chipSection("RESOLUTION", resolutions, resolutionSelection, onToggleResolution)
                }
                if hasDates {
                    section("DATE") {
                        HStack(spacing: 6) {
                            dateField("Start", dateStartLabel, onPickStart)
                            Text("–").font(MonitorTheme.font(10.5, weight: .semibold))
                                .foregroundStyle(MonitorTheme.muted)
                            dateField("End", dateEndLabel, onPickEnd)
                        }
                    }
                }
                if !colors.isEmpty {
                    section("COLOUR") {
                        chipGrid(colors.map(\.label), Set(colors.filter { colorSelection.contains($0.id) }.map(\.label)))
                        { title in
                            if let option = colors.first(where: { $0.label == title }) {
                                onToggleColor(option.id)
                            }
                        }
                    }
                }
                if empty {
                    Text("Nothing in this tab to filter by.")
                        .font(MonitorTheme.font(11)).foregroundStyle(MonitorTheme.faint)
                }
                if active {
                    Button("Clear all filters", action: onClear)
                        .font(MonitorTheme.font(11, weight: .semibold))
                        .foregroundStyle(MonitorTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
            -> some View
        {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(MonitorTheme.font(9, weight: .bold)).foregroundStyle(MonitorTheme.muted)
                content()
            }
        }

        private func chipSection(
            _ title: String, _ titles: [String], _ active: Set<String>, _ toggle: @escaping (String) -> Void
        ) -> some View {
            section(title) { chipGrid(titles, active, toggle) }
        }

        private func chipGrid(
            _ titles: [String], _ active: Set<String>, _ toggle: @escaping (String) -> Void
        ) -> some View {
            let columns = [GridItem(.adaptive(minimum: 150), spacing: 5)]
            return LazyVGrid(columns: columns, spacing: 5) {
                ForEach(titles, id: \.self) { title in
                    Button {
                        toggle(title)
                    } label: {
                        Text(title)
                            .font(MonitorTheme.font(10, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .foregroundStyle(active.contains(title) ? MonitorTheme.accent : MonitorTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                active.contains(title)
                                    ? MonitorTheme.accent.opacity(0.14) : Color.white.opacity(0.04),
                                in: Capsule())
                    }
                    .buttonStyle(MonitorButtonStyle())
                }
            }
        }

        private func dateField(_ title: String, _ label: String?, _ action: @escaping () -> Void)
            -> some View
        {
            Button(action: action) {
                Text(label ?? title)
                    .font(MonitorTheme.font(10.5, weight: .semibold))
                    .foregroundStyle(label == nil ? MonitorTheme.muted : MonitorTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(title)
            .accessibilityValue(label ?? "Any")
            .accessibilityIdentifier("monitor.media.filter.\(title.lowercased())")
        }
    }

#endif
