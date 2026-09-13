#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// A camera-independent page frame. The host supplies already-resolved physical
    /// safe areas because a full-screen overlay may itself report zero safe insets.
    public struct MonitorPage<Navigation: View, Detail: View>: View {
        private let safeArea: EdgeInsets
        private let navigationWidth: CGFloat
        private let heading: MonitorPageHeading
        private let backLabel: String
        private let back: () -> Void
        private let navigation: (Bool) -> Navigation
        private let detail: (Bool) -> Detail
        @Environment(\.monitorWindowGeometry) private var windowGeometry

        public init(
            safeArea: EdgeInsets, navigationWidth: CGFloat = 168, heading: MonitorPageHeading,
            backLabel: String, back: @escaping () -> Void,
            @ViewBuilder navigation: @escaping (Bool) -> Navigation,
            @ViewBuilder detail: @escaping (Bool) -> Detail
        ) {
            self.safeArea = safeArea
            self.navigationWidth = navigationWidth
            self.heading = heading
            self.backLabel = backLabel
            self.back = back
            self.navigation = navigation
            self.detail = detail
        }

        public var body: some View {
            GeometryReader { proxy in
                let portrait = proxy.size.height > proxy.size.width
                let pageTop = safeArea.top + windowGeometry.topControlInset + 10
                // Share live-monitor button dimensions and physical corner clearance.
                let control = FieldMonitorLayout(
                    width: proxy.size.width, height: proxy.size.height,
                    safeArea: MonitorSafeArea(
                        top: safeArea.top, leading: safeArea.leading,
                        bottom: safeArea.bottom, trailing: safeArea.trailing),
                    topControlInset: windowGeometry.topControlInset
                ).lock
                let buttonSide = CGFloat(control.width)
                HStack(alignment: .top, spacing: 10) {
                    if !portrait {
                        backButton(size: buttonSide)
                            .padding(.top, max(0, CGFloat(control.y) - pageTop))
                    }
                    MonitorPageRegions(portrait: portrait, navigationWidth: navigationWidth) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 9) {
                                if portrait { backButton(size: buttonSide) }
                                heading
                            }
                            navigation(portrait)
                        }
                        .padding(10)
                        .background(
                            MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).strokeBorder(MonitorTheme.border)
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("monitor.page.navigation")
                        detail(portrait)
                            .frame(
                                minWidth: 0, maxWidth: .infinity, minHeight: 0,
                                maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.top, pageTop)
                .padding(.bottom, safeArea.bottom + 10)
                // Use the existing landscape margin for Back before taking width
                // from the page. The corner button sits above the side cutout.
                .padding(
                    .leading,
                    portrait
                        ? safeArea.leading + 12
                        : max(CGFloat(control.x), max(14, safeArea.leading) + 12 - buttonSide - 10)
                )
                .padding(
                    .trailing, (portrait ? safeArea.trailing : max(14, safeArea.trailing)) + 12
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(MonitorTheme.background)
        }

        private func backButton(size: CGFloat) -> some View {
            MonitorChromeButton(backLabel, size: CGSize(width: size, height: size), action: back) {
                MonitorIcon.chevronLeft.frame(width: size * 29 / 54, height: size * 29 / 54)
            }
        }
    }

    /// Both page regions keep their identity. Explicit proposals prevent the
    /// navigation's intrinsic portrait height and the flexible detail region
    /// from feeding each other's measurements during an orientation change.
    private struct MonitorPageRegions: Layout {
        var portrait: Bool
        var navigationWidth: CGFloat
        private let spacing: CGFloat = 10

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize
        {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize,
            subviews: Subviews, cache: inout ()
        ) {
            guard subviews.count == 2 else { return }
            let width = portrait ? bounds.width : min(navigationWidth, bounds.width)
            let proposedHeight: CGFloat? = portrait ? nil : bounds.height
            let measured = subviews[0].sizeThatFits(
                ProposedViewSize(width: width, height: proposedHeight))
            let height = portrait ? min(bounds.height, max(0, measured.height)) : bounds.height
            subviews[0].place(
                at: bounds.origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height))
            let origin = CGPoint(
                x: bounds.minX + (portrait ? 0 : width + spacing),
                y: bounds.minY + (portrait ? height + spacing : 0))
            subviews[1].place(
                at: origin, anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: max(0, bounds.maxX - origin.x),
                    height: max(0, bounds.maxY - origin.y)))
        }
    }

    public struct MonitorPageHeading: View {
        private let brand: String
        private let title: String

        public init(brand: String, title: String) {
            self.brand = brand
            self.title = title
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(brand.uppercased())
                    .font(MonitorTheme.font(8, weight: .bold)).tracking(1.4)
                    .foregroundStyle(MonitorTheme.accent)
                    .lineLimit(1).minimumScaleFactor(0.9)
                Text(title).font(MonitorTheme.font(13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .foregroundStyle(MonitorTheme.text)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("monitor.page.heading")
        }
    }

    public struct MonitorNavigationItem: View {
        private let title: String
        private let subtitle: String?
        private let count: String?
        private let selected: Bool
        private let action: () -> Void

        public init(
            _ title: String, subtitle: String? = nil, count: String? = nil,
            selected: Bool, action: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.count = count
            self.selected = selected
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(selected ? MonitorTheme.accent : .clear)
                        .frame(width: 4, height: subtitle == nil ? 20 : 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(MonitorTheme.font(12.5, weight: .semibold))
                            .foregroundStyle(selected ? MonitorTheme.text : MonitorTheme.muted)
                        if let subtitle {
                            Text(subtitle).font(MonitorTheme.font(10))
                                .foregroundStyle(MonitorTheme.faint)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let count {
                        Text(count).font(MonitorTheme.font(10, weight: .bold)).monospacedDigit()
                            .foregroundStyle(selected ? MonitorTheme.accent : MonitorTheme.faint)
                    }
                }
                .padding(.horizontal, 8).frame(minHeight: 44)
                .background(
                    selected ? Color.white.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    /// Card placement uses measured heights, so two columns do not leave holes below
    /// shorter cards. Subview identity is preserved while a viewport changes columns.
    public struct MonitorCardColumns: Layout {
        public var minimumColumnWidth: CGFloat
        public var spacing: CGFloat

        public init(minimumColumnWidth: CGFloat = 275, spacing: CGFloat = 10) {
            self.minimumColumnWidth = minimumColumnWidth
            self.spacing = spacing
        }

        public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
            -> CGSize
        {
            let width = proposal.width ?? minimumColumnWidth
            let result = positions(width: width, subviews: subviews)
            return CGSize(width: width, height: result.height)
        }

        public func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize,
            subviews: Subviews, cache: inout ()
        ) {
            for (index, rect) in positions(width: bounds.width, subviews: subviews).frames
                .enumerated()
            {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                    anchor: .topLeading,
                    // Match measurement exactly. Supplying the measured height
                    // here creates a second proposal and relays out every nested
                    // settings row during placement and scrolling.
                    proposal: ProposedViewSize(width: rect.width, height: nil))
            }
        }

        private func positions(width: CGFloat, subviews: Subviews) -> (
            frames: [CGRect], height: CGFloat
        ) {
            let columnCount = width >= minimumColumnWidth * 2 + spacing ? 2 : 1
            let columnWidth = max(
                0, (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
            var heights = Array(repeating: CGFloat.zero, count: columnCount)
            var frames: [CGRect] = []
            for subview in subviews {
                let full = subview[MonitorFullWidthCard.self]
                let column = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
                let cardWidth = full ? width : columnWidth
                let y = full ? (heights.max() ?? 0) : heights[column]
                let size = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
                frames.append(
                    CGRect(
                        x: full ? 0 : CGFloat(column) * (columnWidth + spacing),
                        y: y, width: cardWidth, height: size.height))
                if full {
                    heights = Array(repeating: y + size.height + spacing, count: columnCount)
                } else {
                    heights[column] = y + size.height + spacing
                }
            }
            return (frames, max(0, (heights.max() ?? 0) - spacing))
        }
    }

    private struct MonitorFullWidthCard: LayoutValueKey {
        static let defaultValue = false
    }

    extension View {
        public func monitorFullWidthCard() -> some View {
            layoutValue(key: MonitorFullWidthCard.self, value: true)
        }

        public func monitorCardSurface(radius: CGFloat = 12) -> some View {
            background(MonitorTheme.surface, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(MonitorTheme.border))
        }
    }
#endif
