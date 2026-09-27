#if os(iOS)
    import SwiftUI

    /// Preferred inspector width. Assist and a wide gimbal pane share `.assist`;
    /// a compact trailing drawer keeps `.trailing` so other hosts do not widen.
    public struct MonitorInspectorWidth: Equatable, Sendable {
        public var preferred: CGFloat
        public var fraction: CGFloat

        public static let assist = MonitorInspectorWidth(preferred: 460, fraction: 0.92)
        public static let trailing = MonitorInspectorWidth(preferred: 312, fraction: 0.66)

        public init(preferred: CGFloat, fraction: CGFloat) {
            self.preferred = preferred
            self.fraction = min(1, max(0.1, fraction))
        }

        public func resolved(viewportWidth: CGFloat) -> CGFloat {
            min(preferred, viewportWidth * fraction)
        }
    }

    /// A viewport-bounded inspector. Native apps own its selection, content and
    /// actions; this shell owns only layout, scrolling and the reveal animation.
    public struct MonitorInspector<Navigation: View, Content: View, Footer: View>: View {
        private let title: String
        private let viewport: CGSize
        private let safeArea: EdgeInsets
        private let trailing: Bool
        private let hasNavigation: Bool
        private let preferredWidth: MonitorInspectorWidth
        private let onClose: () -> Void
        private let helpVisible: Binding<Bool>?
        private let scrollsContent: Bool
        private let closeIdentifier: String
        private let compactHeader: Bool
        private let navigation: Navigation
        private let content: Content
        private let footer: Footer
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var revealed = false

        public init(
            title: String, viewport: CGSize, safeArea: EdgeInsets = EdgeInsets(),
            trailing: Bool = false, hasNavigation: Bool = true,
            preferredWidth: MonitorInspectorWidth? = nil,
            helpVisible: Binding<Bool>? = nil,
            scrollsContent: Bool = true, closeIdentifier: String = "", compactHeader: Bool = false,
            onClose: @escaping () -> Void,
            @ViewBuilder navigation: () -> Navigation,
            @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
        ) {
            self.title = title
            self.viewport = viewport
            self.safeArea = safeArea
            self.trailing = trailing
            self.hasNavigation = hasNavigation
            self.preferredWidth = preferredWidth ?? (trailing ? .trailing : .assist)
            self.onClose = onClose
            self.helpVisible = helpVisible
            self.scrollsContent = scrollsContent
            self.closeIdentifier = closeIdentifier
            self.compactHeader = compactHeader
            self.navigation = navigation()
            self.content = content()
            self.footer = footer()
        }

        private var portrait: Bool { viewport.height > viewport.width }
        private var width: CGFloat { preferredWidth.resolved(viewportWidth: viewport.width) }
        private var height: CGFloat {
            portrait && trailing ? min(viewport.height * 0.52, 620) : viewport.height
        }

        /// Fixed columns prevent a selected menu's ideal width from expanding
        /// the shell; only the content's vertical scroll extent may change.
        private var contentWidth: CGFloat {
            let edge = portrait ? 0 : max(0, trailing ? safeArea.trailing : safeArea.leading)
            return max(1, width - edge - (!portrait && hasNavigation ? 109 : 0))
        }

        public var body: some View {
            ZStack(
                alignment: trailing && portrait
                    ? .trailing : (trailing ? .topTrailing : .topLeading)
            ) {
                Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture(perform: onClose)
                    .accessibilityLabel("Dismiss \(title)")
                    .accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    header.zIndex(1)
                    if portrait && hasNavigation {
                        navigation.frame(height: 44).padding(.bottom, 8)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        if !portrait && hasNavigation {
                            navigation.frame(width: 108)
                            Rectangle().fill(MonitorTheme.border).frame(width: 1)
                        }
                        VStack(spacing: 0) {
                            if scrollsContent {
                                ScrollView {
                                    content
                                        .frame(width: max(1, contentWidth - 28), alignment: .leading)
                                        .padding(14)
                                }
                                .scrollBounceBehavior(.basedOnSize)
                                .monitorScrollFade()
                            } else {
                                // The host owns scrolling, e.g. fixed tab rails beside scrolled
                                // controls; its top tabs sit directly under the header.
                                content
                                    .frame(width: max(1, contentWidth - 28), alignment: .topLeading)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .padding([.horizontal, .bottom], 14)
                            }
                            footer.padding(.horizontal, 14).padding(.bottom, 10)
                        }
                        .frame(width: contentWidth)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.top, portrait && trailing ? 4 : max(4, safeArea.top))
                .padding(.bottom, portrait && trailing ? 4 : max(4, safeArea.bottom))
                .padding(
                    trailing ? .trailing : .leading,
                    portrait ? 0 : max(0, trailing ? safeArea.trailing : safeArea.leading)
                )
                .frame(width: width, height: max(1, height))
                .frame(
                    width: revealed ? width : MonitorMotion.drawerCollapsedWidth,
                    alignment: trailing ? .trailing : .leading
                )
                .monitorGlass(
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: trailing ? 16 : 0, bottomLeadingRadius: trailing ? 16 : 0,
                        bottomTrailingRadius: trailing ? 0 : 16,
                        topTrailingRadius: trailing ? 0 : 16),
                    density: .expanded
                )
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("monitor.inspector")
            }
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
            .onAppear {
                if reduceMotion {
                    revealed = true
                } else if let animation = MonitorMotion.drawerReveal(false) {
                    withAnimation(animation) { revealed = true }
                }
            }
        }

        private var header: some View {
            HStack(spacing: 8) {
                Text(title).font(MonitorTheme.font(14, weight: .semibold)).foregroundStyle(
                    MonitorTheme.text
                )
                .lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let helpVisible {
                    Button {
                        helpVisible.wrappedValue.toggle()
                    } label: {
                        MonitorIcon.circleQuestionMark.frame(width: 17, height: 17)
                            .foregroundStyle(
                                helpVisible.wrappedValue ? MonitorTheme.accent : MonitorTheme.muted
                            )
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(MonitorButtonStyle()).padding(.vertical, compactHeader ? -11 : 0)
                    .accessibilityLabel("Show option help")
                        .accessibilityValue(helpVisible.wrappedValue ? "On" : "Off")
                }
                Button(action: onClose) {
                    MonitorIcon.x.frame(width: 14, height: 14)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(MonitorButtonStyle()).foregroundStyle(MonitorTheme.secondary)
                    .padding(.vertical, compactHeader ? -11 : 0)
                    .accessibilityLabel("Close \(title)")
                    .accessibilityIdentifier(closeIdentifier)
            }
            // A compact header is one title line: the 44 pt close target overflows it,
            // sits 8 pt further in from the corner, and top tabs start under the title.
            .padding(.leading, 14).padding(.trailing, compactHeader ? 10 : 2)
            .padding(.top, compactHeader ? 16 : 0).padding(.bottom, compactHeader ? -10 : 0)
        }
    }

    /// A bounded set of related inspector controls, with an optional section title.
    public struct MonitorInspectorCard<Content: View>: View {
        private let title: String?
        private let content: Content

        public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                if let title {
                    Text(title.uppercased())
                        .font(MonitorTheme.font(9, weight: .semibold))
                        .foregroundStyle(MonitorTheme.muted)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.022), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(
                            .white.opacity(0.055), lineWidth: 1))
            }
        }
    }

#endif
