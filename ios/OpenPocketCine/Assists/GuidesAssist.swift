import SwiftUI

/// OpenZCine `AssistPanel` `.guides` body + `AspectGuideFrameView`.
///
/// Long-press options (no title-safe / action-safe — OpenZCine does not offer those):
/// - Film / Social family tabs
/// - Multi-select aspect chips for the active tab
/// - "Mask outside frame" (darkens the inverse of the union)
enum GuidesAssist {
    /// OpenZCine `assistPanelWidth(for: .guides)`.
    static let panelWidth: CGFloat = 472

    @MainActor
    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func overlay(feed: CGRect, assist: LiveAssistState, fallback: GuideAspect) -> some View {
        AspectGuideFrameView(
            selectedRatios: assist.selectedGuides.isEmpty ? [fallback] : assist.selectedGuides,
            maskEnabled: assist.guideMask,
            feed: feed
        )
    }

    /// OpenZCine `AssistConfiguration.Guides.summaryLabel`.
    static func summaryLabel(for selected: Set<GuideAspect>) -> String {
        if selected.count == 1 { return selected.first?.rawValue ?? "—" }
        return selected.isEmpty ? "—" : "\(selected.count) ratios"
    }

    /// OpenZCine `rectForRatio` — letterbox when the guide is wider than the feed,
    /// pillarbox when narrower.
    static func rectForRatio(_ feed: CGRect, _ ratio: CGFloat) -> CGRect {
        let width: CGFloat
        let height: CGFloat
        if feed.width / feed.height > ratio {
            height = feed.height
            width = feed.height * ratio
        } else {
            width = feed.width
            height = feed.width / ratio
        }
        return CGRect(
            x: feed.minX + (feed.width - width) / 2,
            y: feed.minY + (feed.height - height) / 2,
            width: width,
            height: height
        )
    }
}

/// OpenZCine `AssistPanel` `case .guides` — family tabs, 5-column chips, mask row.
private struct GuidesLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GuidesSegmentedButtons(
                items: GuideFamily.allCases.map(\.rawValue),
                selected: assist.guideFamily.rawValue
            ) { value in
                if let family = GuideFamily(rawValue: value) {
                    assist.guideFamily = family
                    assist.persist()
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 5),
                spacing: 10
            ) {
                ForEach(GuideAspect.ratios(for: assist.guideFamily)) { ratio in
                    Button {
                        assist.toggleGuide(ratio)
                    } label: {
                        GuidesGlassChoice(
                            title: ratio.rawValue,
                            isSelected: assist.selectedGuides.contains(ratio)
                        )
                    }
                    .buttonStyle(.zcTapTarget)
                }
            }
            Button {
                assist.guideMask.toggle()
                assist.persist()
            } label: {
                GuidesToggleRow(title: "Mask outside frame", isOn: assist.guideMask)
            }
            .buttonStyle(.zcTapTarget)
        }
    }
}

/// One selected aspect resolved to its centred frame within the feed rect.
private struct GuideFrame: Identifiable {
    let ratio: GuideAspect
    let rect: CGRect
    var id: String { ratio.rawValue }
}

/// OpenZCine `AspectGuideFrameView` — gold frames, corner tags, optional union mask.
struct AspectGuideFrameView: View {
    let selectedRatios: Set<GuideAspect>
    var maskEnabled = false
    let feed: CGRect

    var body: some View {
        let frames =
            selectedRatios
            .sorted { $0.ratio < $1.ratio }
            .map { GuideFrame(ratio: $0, rect: GuidesAssist.rectForRatio(feed, $0.ratio)) }
        ZStack {
            if maskEnabled, !frames.isEmpty {
                Canvas { context, _ in
                    context.fill(Path(feed), with: .color(.black.opacity(0.6)))
                    context.blendMode = .destinationOut
                    for frame in frames {
                        context.fill(Path(frame.rect), with: .color(.black))
                    }
                }
            }
            ForEach(frames) { frame in
                Rectangle()
                    .stroke(LiveDesign.accent.opacity(0.85), lineWidth: 1)
                    .frame(width: frame.rect.width, height: frame.rect.height)
                    .position(x: frame.rect.midX, y: frame.rect.midY)
                Text(frame.ratio.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(LiveDesign.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                    .position(x: frame.rect.minX, y: frame.rect.minY)
                    .offset(x: 34, y: 13)
            }
        }
    }
}

/// OpenZCine `SegmentedButtons` — capsule chips, gold when selected.
private struct GuidesSegmentedButtons: View {
    let items: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item)
                        .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(item == selected ? LiveDesign.accent : LiveDesign.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            item == selected ? LiveDesign.accentDim : LiveDesign.glassBright,
                            in: Capsule()
                        )
                }
                .buttonStyle(.zcTapTarget)
            }
        }
    }
}

/// OpenZCine `GlassChoice`.
private struct GuidesGlassChoice: View {
    let title: String
    var isSelected = false

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .foregroundStyle(isSelected ? LiveDesign.accent : LiveDesign.text)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? LiveDesign.accentDim : LiveDesign.glassBright,
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                    .stroke(isSelected ? LiveDesign.accentDim : LiveDesign.hairline, lineWidth: 1)
            )
    }
}

/// OpenZCine `ToggleRow`.
private struct GuidesToggleRow: View {
    let title: String
    let isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Group {
                if isOn {
                    LucideIconView(name: OpcIcon.circleCheck.lucideName, filled: true)
                } else {
                    OpcIcon.circle
                }
            }
            .foregroundStyle(isOn ? LiveDesign.accent : LiveDesign.muted)
            .frame(width: 18, height: 18)
        }
        .padding(14)
        .background(
            isOn ? LiveDesign.accentDim : LiveDesign.glassBright,
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
        )
    }
}
