import OpenPocketViewCore
import SwiftUI

/// OpenZCine `PortraitScopesStack` — first ≤2 enabled scopes, 96 pt units, canonical order.
struct LivePortraitScopesStack: View {
    @Environment(AppModel.self) private var model

    static let canonical: [LiveAssistTool] = [
        .waveform, .parade, .histogram, .vectorscope, .trafficLights,
    ]

    var kinds: [LiveAssistTool] {
        Array(Self.canonical.filter { model.assist.isVisible($0) }.prefix(2))
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(kinds, id: \.id) { kind in
                panel(for: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func panel(for kind: LiveAssistTool) -> some View {
        GeometryReader { proxy in
            let cell = CGRect(origin: .zero, size: proxy.size)
            switch kind {
            case .waveform:
                WaveformOverlay(canvas: cell, feed: cell)
            case .parade:
                ParadeOverlay(canvas: cell, feed: cell)
            case .histogram:
                HistogramOverlay(canvas: cell, feed: cell)
            case .vectorscope:
                VectorscopeOverlay(canvas: cell, feed: cell)
            case .trafficLights:
                TrafficLightsOverlay(bounds: cell, feed: cell, chromeClearance: EdgeInsets())
            default:
                EmptyView()
            }
        }
    }
}

/// OpenZCine `PortraitRecOptionsButton` — format / color over the feed.
struct LivePortraitRecOptionsButton: View {
    @Environment(AppModel.self) private var model
    @State private var popoverOpen = false

    var body: some View {
        Button {
            popoverOpen = true
        } label: {
            OpcIcon.audioWaveform
                .foregroundStyle(LiveDesign.text.opacity(0.86))
                .frame(width: 16, height: 16)
                .frame(width: 40, height: 40)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.zcTapTarget)
        .popover(isPresented: $popoverOpen, attachmentAnchor: .point(.bottomTrailing)) {
            recOptionsMenu
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Recording options")
    }

    private var recOptionsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuItem(title: "Resolution · Framerate") {
                model.captureSheet = .resolution
            }
            Divider().overlay(LiveDesign.hairline)
            menuItem(title: "Color") {
                model.captureSheet = .color
            }
        }
        .frame(width: 220)
        .background(LiveDesign.glass)
    }

    private func menuItem(title: String, action: @escaping () -> Void) -> some View {
        Button {
            popoverOpen = false
            action()
        } label: {
            Text(title)
                .font(LiveType.ui(size: 14, weight: .medium))
                .foregroundStyle(LiveDesign.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// Fit/fill quick key. Lives just under a landscape 16:9 well; in fill it
/// parks above the capture strip / system rail so the rail cannot cover it.
struct LivePortraitAspectToggle: View {
    @Binding var aspect: PortraitFeedAspect

    var body: some View {
        Button {
            aspect = aspect == .fill ? .fit16x9 : .fill
        } label: {
            (aspect == .fill ? OpcIcon.minimize : OpcIcon.maximize)
                .frame(width: 15, height: 15)
                .foregroundStyle(LiveDesign.text)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(aspect == .fill ? "Fit feed in frame" : "Fill frame with feed")
        .accessibilityValue(aspect == .fill ? "Fill" : "Fit")
    }
}

/// OpenZCine fill-mode vertical assist rail: collapsed 44 pt pill, expanded 60 pt column.
struct LivePortraitAssistRail: View {
    @Environment(AppModel.self) private var model
    var isLocked: Bool
    @Binding var expanded: Bool

    var body: some View {
        Group {
            if expanded {
                expandedBody
            } else {
                collapsedPill
            }
        }
        .opacity(isLocked ? 0.4 : 1)
        .allowsHitTesting(!isLocked)
    }

    private var collapsedPill: some View {
        Button {
            withAnimation(.spring(duration: 0.28)) { expanded = true }
        } label: {
            OpcIcon.slidersHorizontal
                .foregroundStyle(LiveDesign.text)
                .frame(width: 16, height: 16)
                .frame(width: 44, height: 44)
                .liveChromeGlass(in: Circle())
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Show view assists")
    }

    private var expandedBody: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(duration: 0.28)) { expanded = false }
            } label: {
                OpcIcon.chevronLeft
                    .foregroundStyle(LiveDesign.accent)
                    .frame(width: 13, height: 13)
                    .frame(width: 36, height: 28)
            }
            .buttonStyle(.zcTapTarget)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(LiveAssistTool.toolbarCases) { tool in
                        AssistBarButton(
                            tool: tool,
                            assist: model.assist,
                            isLocked: isLocked,
                            onPresent: presentOptions
                        )
                    }
                    AssistBarButton(
                        tool: .audioMeters,
                        assist: model.assist,
                        isLocked: isLocked,
                        onPresent: presentOptions
                    )
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
    }

    private func presentOptions(for tool: LiveAssistTool) {
        guard tool.hasConfiguration else { return }
        AssistBarHaptics.confirm()
        model.assist.configureTool = tool
        if tool == .lut { model.assist.showLUTPicker = false }
    }
}
