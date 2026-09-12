#if os(iOS)
    import SwiftUI

    /// The common floating action appearance for both playback and photo review.
    /// Glyphs remain injectable so host apps can supply their native icon catalog.
    public struct MonitorPlaybackChip<Icon: View>: View {
        private let icon: Icon
        private let title: String?
        private let active: Bool
        private let destructive: Bool

        public init(
            title: String? = nil, active: Bool = false, destructive: Bool = false,
            @ViewBuilder icon: () -> Icon
        ) {
            self.title = title
            self.active = active
            self.destructive = destructive
            self.icon = icon()
        }

        public var body: some View {
            HStack(spacing: 7) {
                icon.frame(width: 14, height: 14)
                if let title {
                    Text(title).font(MonitorTheme.font(10.5, weight: .semibold)).tracking(0.4)
                }
            }
            .foregroundStyle(
                destructive
                    ? MonitorTheme.recording : active ? MonitorTheme.text : MonitorTheme.secondary
            )
            .padding(.horizontal, 11).frame(height: 38)
            .background(
                destructive
                    ? MonitorTheme.recording.opacity(0.12)
                    : active ? MonitorTheme.accent.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        destructive
                            ? MonitorTheme.recording.opacity(0.4)
                            : active ? MonitorTheme.accent.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 1)
            )
            .monitorGlass(in: RoundedRectangle(cornerRadius: 10), density: .compact)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    public struct MonitorMetadataRow: Identifiable, Equatable {
        public var id: String { label }
        public let label: String
        public let value: String
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// A nonmodal, trailing clip inspector. Only facts provided by the host appear.
    public struct MonitorClipInfoPanel: View {
        private let rows: [MonitorMetadataRow]
        private let onClose: () -> Void
        public init(rows: [MonitorMetadataRow], onClose: @escaping () -> Void) {
            self.rows = rows
            self.onClose = onClose
        }

        public var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("CLIP INFO").font(MonitorTheme.font(9, weight: .bold)).tracking(1.8)
                    Spacer()
                    Button(action: onClose) {
                        MonitorIcon.x.frame(width: 12, height: 12)
                            .foregroundStyle(MonitorTheme.muted).frame(width: 44, height: 44)
                    }
                    .buttonStyle(MonitorButtonStyle()).accessibilityLabel("Close clip information")
                }
                .padding(.leading, 12).overlay(alignment: .bottom) {
                    Divider().overlay(MonitorTheme.border)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.label).font(MonitorTheme.font(11, weight: .semibold))
                                    .foregroundStyle(MonitorTheme.muted).fixedSize()
                                Spacer(minLength: 0)
                                Text(row.value).font(MonitorTheme.font(11)).foregroundStyle(
                                    MonitorTheme.secondary
                                )
                                .multilineTextAlignment(.trailing).textSelection(.enabled)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .overlay(alignment: .bottom) {
                                Divider().overlay(Color.white.opacity(0.04))
                            }
                        }
                    }
                }
            }
            .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .information)
        }
    }
#endif
