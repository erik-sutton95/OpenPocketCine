import SwiftUI

// MARK: - Edit view (per-DISP chrome)

/// Measured bounds of every badgeable monitor element, in canvas space.
///
/// Boxes are measured, never derived from the zone map: a zone frame is a layout
/// budget, and several elements draw inset within theirs.
struct ChromeEditBoundsKey: PreferenceKey {
    static let defaultValue: [PocketDispChrome.Section: CGRect] = [:]

    static func reduce(
        value: inout [PocketDispChrome.Section: CGRect],
        nextValue: () -> [PocketDispChrome.Section: CGRect]
    ) {
        value.merge(nextValue()) { existing, next in existing.union(next) }
    }
}

enum ChromeEditSpace {
    static var name: String { LiveCanvasSpace.name }
}

/// Where the Edit view puts each element's eye badge. Pure geometry so tests can
/// pin placement without a live monitor.
///
/// Badges sit **on** the control, on the side toward the canvas centre. Centering
/// them on an outer corner (then clamping 3 pt in) put rail / top-deck eyes in
/// the display corner radius, where they were clipped and untappable.
enum PocketChromeEditLayout {
    static let badgeSize: CGFloat = 26
    static let badgeGap: CGFloat = 4
    /// Hard inset from the physical canvas. 16 pt keeps a 26 pt eye inside the
    /// iPhone display corner curve (~52 pt).
    static let edgeInset: CGFloat = 16
    /// How far a badge may peek past its element's edge. The rest sits on it.
    static let overhang: CGFloat = 4

    struct Box: Equatable, Sendable {
        let section: PocketDispChrome.Section
        let frame: CGRect
    }

    static func badgeFrames(
        _ boxes: [Box],
        viewport: CGSize,
        badgeSize: CGFloat = badgeSize
    ) -> [PocketDispChrome.Section: CGRect] {
        let playable = playableRect(in: viewport, badgeSize: badgeSize)
        var placed: [CGRect] = []
        var result: [PocketDispChrome.Section: CGRect] = [:]

        for box in boxes where box.frame.width > 1 && box.frame.height > 1 {
            let candidates = anchors(on: box.frame, viewport: viewport, badgeSize: badgeSize)
                .map { clamped($0, in: playable) }
            let choice =
                candidates.first { candidate in
                    !placed.contains { overlaps($0, candidate) }
                } ?? candidates[0]
            placed.append(choice)
            result[box.section] = choice
        }
        return result
    }

    static func playableRect(in viewport: CGSize, badgeSize: CGFloat = badgeSize) -> CGRect {
        let inset = edgeInset
        let width = max(badgeSize, viewport.width - 2 * inset)
        let height = max(badgeSize, viewport.height - 2 * inset)
        let x = min(inset, max(0, viewport.width - width))
        let y = min(inset, max(0, viewport.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 4 corners + 4 mid-edges, badge mostly overlapping `frame`, inward first.
    private static func anchors(
        on frame: CGRect,
        viewport: CGSize,
        badgeSize: CGFloat
    ) -> [CGRect] {
        let preferTrailing = frame.midX < viewport.width / 2
        let preferBottom = frame.midY < viewport.height / 2
        return Anchor.allCases
            .sorted {
                rank($0, preferTrailing: preferTrailing, preferBottom: preferBottom)
                    < rank($1, preferTrailing: preferTrailing, preferBottom: preferBottom)
            }
            .map { $0.frame(on: frame, badgeSize: badgeSize, overhang: overhang) }
    }

    private enum Anchor: CaseIterable {
        case topLeading, top, topTrailing
        case leading, trailing
        case bottomLeading, bottom, bottomTrailing

        func frame(on box: CGRect, badgeSize: CGFloat, overhang: CGFloat) -> CGRect {
            let inner = badgeSize - overhang
            let midX = box.midX - badgeSize / 2
            let midY = box.midY - badgeSize / 2
            let x: CGFloat
            let y: CGFloat
            switch self {
            case .topLeading:
                x = box.minX - overhang
                y = box.minY - overhang
            case .top:
                x = midX
                y = box.minY - overhang
            case .topTrailing:
                x = box.maxX - inner
                y = box.minY - overhang
            case .leading:
                x = box.minX - overhang
                y = midY
            case .trailing:
                x = box.maxX - inner
                y = midY
            case .bottomLeading:
                x = box.minX - overhang
                y = box.maxY - inner
            case .bottom:
                x = midX
                y = box.maxY - inner
            case .bottomTrailing:
                x = box.maxX - inner
                y = box.maxY - inner
            }
            return CGRect(x: x, y: y, width: badgeSize, height: badgeSize)
        }
    }

    /// 0 = most inward (toward canvas centre), 4 = most outward (screen corner).
    private static func rank(
        _ anchor: Anchor,
        preferTrailing: Bool,
        preferBottom: Bool
    ) -> Int {
        let horizontal: Int
        switch anchor {
        case .topTrailing, .trailing, .bottomTrailing:
            horizontal = preferTrailing ? 0 : 2
        case .topLeading, .leading, .bottomLeading:
            horizontal = preferTrailing ? 2 : 0
        case .top, .bottom:
            horizontal = 1
        }
        let vertical: Int
        switch anchor {
        case .bottomLeading, .bottom, .bottomTrailing:
            vertical = preferBottom ? 0 : 2
        case .topLeading, .top, .topTrailing:
            vertical = preferBottom ? 2 : 0
        case .leading, .trailing:
            vertical = 1
        }
        return horizontal + vertical
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX + badgeGap && b.minX < a.maxX + badgeGap
            && a.minY < b.maxY + badgeGap && b.minY < a.maxY + badgeGap
    }

    private static func clamped(_ frame: CGRect, in playable: CGRect) -> CGRect {
        guard playable.width >= frame.width, playable.height >= frame.height else {
            return CGRect(
                x: playable.minX, y: playable.minY, width: frame.width, height: frame.height)
        }
        return CGRect(
            x: min(max(frame.minX, playable.minX), playable.maxX - frame.width),
            y: min(max(frame.minY, playable.minY), playable.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }
}

extension View {
    func chromeEditable(
        _ section: PocketDispChrome.Section,
        editing mode: PocketDispMode?
    ) -> some View {
        modifier(ChromeEditable(section: section, mode: mode))
    }
}

struct ChromeEditable: ViewModifier {
    @Environment(AppModel.self) private var model
    let section: PocketDispChrome.Section
    let mode: PocketDispMode?

    func body(content: Content) -> some View {
        if let mode, PocketDispChrome.isConfigurable(section, in: mode) {
            let on = model.chrome(for: mode).isVisible(section)
            content
                .opacity(on ? 1 : 0.3)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ChromeEditBoundsKey.self,
                            value: [section: proxy.frame(in: .named(ChromeEditSpace.name))]
                        )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            on ? LiveDesign.accent.opacity(0.75) : LiveDesign.muted.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .padding(-2)
                }
        } else {
            content
        }
    }
}

/// One eye badge. Tapping it shows or hides that element for the DISP mode being edited.
struct ChromeEditBadge: View {
    @Environment(AppModel.self) private var model
    let section: PocketDispChrome.Section
    let mode: PocketDispMode

    var body: some View {
        let on = model.chrome(for: mode).isVisible(section)
        Button {
            OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
            model.toggleChrome(section, for: mode)
        } label: {
            (on ? OpcIcon.eye : OpcIcon.eyeOff)
                .frame(width: 11, height: 11)
                .foregroundStyle(on ? LiveDesign.background : LiveDesign.text)
                .frame(
                    width: PocketChromeEditLayout.badgeSize,
                    height: PocketChromeEditLayout.badgeSize
                )
                .background(on ? LiveDesign.accent : Color.black.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(LiveDesign.text.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .minTapTarget()
        .accessibilityLabel(section.title)
        .accessibilityValue(on ? "Shown" : "Hidden")
        .accessibilityHint("Shows or hides this on \(mode.title)")
        .accessibilityIdentifier("monitor.chromeEdit.\(section.rawValue)")
    }
}

struct ChromeEditBadgeLayer: View {
    @Environment(AppModel.self) private var model
    let mode: PocketDispMode
    let boxes: [PocketDispChrome.Section: CGRect]
    let viewport: CGSize

    var body: some View {
        let frames = PocketChromeEditLayout.badgeFrames(
            PocketDispChrome.Section.allCases.compactMap { section in
                boxes[section].map {
                    PocketChromeEditLayout.Box(section: section, frame: $0)
                }
            },
            viewport: viewport
        )
        ZStack(alignment: .topLeading) {
            ForEach(PocketDispChrome.Section.allCases) { section in
                if let frame = frames[section] {
                    ChromeEditBadge(section: section, mode: mode)
                        .environment(model)
                        .liveModuleFrame(frame)
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }
}

/// Names the mode being edited and gets the operator back to Display settings.
struct ChromeEditBanner: View {
    @Environment(AppModel.self) private var model
    let mode: PocketDispMode

    var body: some View {
        HStack(spacing: 10) {
            OpcIcon.eye
                .frame(width: 11, height: 11)
                .foregroundStyle(LiveDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Editing \(mode.title)")
                    .font(LiveType.ui(size: 11.5, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                Text("Tap an eye to show or hide it")
                    .font(LiveType.ui(size: 10, weight: .regular))
                    .foregroundStyle(LiveDesign.muted)
            }
            Button {
                model.endChromeEditing()
            } label: {
                Text("Done")
                    .font(LiveType.ui(size: 11.5, weight: .bold))
                    .foregroundStyle(LiveDesign.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LiveDesign.accent, in: Capsule())
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityIdentifier("monitor.chromeEdit.done")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .liquidGlass(in: Capsule())
        .accessibilityIdentifier("monitor.chromeEdit.banner")
    }
}
