#if os(iOS)
    import SwiftUI

    /// A viewport-bounded inspector. Native apps own its selection, content and
    /// actions; this shell owns only layout, scrolling and the reveal animation.
    public struct MonitorInspector<Navigation: View, Content: View, Footer: View>: View {
        private let title: String
        private let viewport: CGSize
        private let safeArea: EdgeInsets
        private let trailing: Bool
        private let hasNavigation: Bool
        private let onClose: () -> Void
        private let helpVisible: Binding<Bool>?
        private let navigation: Navigation
        private let content: Content
        private let footer: Footer
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var revealed = false

        public init(
            title: String, viewport: CGSize, safeArea: EdgeInsets = EdgeInsets(),
            trailing: Bool = false, hasNavigation: Bool = true,
            helpVisible: Binding<Bool>? = nil,
            onClose: @escaping () -> Void,
            @ViewBuilder navigation: () -> Navigation,
            @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
        ) {
            self.title = title
            self.viewport = viewport
            self.safeArea = safeArea
            self.trailing = trailing
            self.hasNavigation = hasNavigation
            self.onClose = onClose
            self.helpVisible = helpVisible
            self.navigation = navigation()
            self.content = content()
            self.footer = footer()
        }

        private var portrait: Bool { viewport.height > viewport.width }
        private var width: CGFloat {
            min(trailing ? 312 : 424, viewport.width * (trailing ? 0.66 : 0.86))
        }
        private var height: CGFloat {
            portrait && trailing ? min(viewport.height * 0.52, 620) : viewport.height
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
                    header
                    if portrait && hasNavigation { navigation.padding(.bottom, 8) }
                    HStack(alignment: .top, spacing: 0) {
                        if !portrait && hasNavigation {
                            navigation.frame(width: 108)
                            Rectangle().fill(MonitorTheme.border).frame(width: 1)
                        }
                        VStack(spacing: 0) {
                            ScrollView {
                                content.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            }.scrollBounceBehavior(.basedOnSize)
                            footer.padding(.horizontal, 14).padding(.bottom, 10)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.top, portrait && trailing ? 4 : max(4, safeArea.top))
                .padding(.bottom, portrait && trailing ? 4 : max(4, safeArea.bottom))
                .padding(
                    trailing ? .trailing : .leading,
                    portrait ? 0 : min(44, trailing ? safeArea.trailing : safeArea.leading)
                )
                .frame(width: width, height: max(1, height))
                .monitorGlass(
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: trailing ? 16 : 0, bottomLeadingRadius: trailing ? 16 : 0,
                        bottomTrailingRadius: trailing ? 0 : 16,
                        topTrailingRadius: trailing ? 0 : 16),
                    density: .expanded
                )
                .clipped()
                .offset(x: revealed ? 0 : (trailing ? width : -width))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("monitor.inspector")
            }
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
            .onAppear {
                withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)) {
                    revealed = true
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
                    }.buttonStyle(MonitorButtonStyle()).accessibilityLabel("Show option help")
                        .accessibilityValue(helpVisible.wrappedValue ? "On" : "Off")
                }
                Button(action: onClose) {
                    MonitorIcon.x.frame(width: 14, height: 14)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(MonitorButtonStyle()).foregroundStyle(MonitorTheme.secondary)
                    .accessibilityLabel("Close \(title)")
            }
            .padding(.leading, 14).padding(.trailing, 2)
        }
    }
#endif
