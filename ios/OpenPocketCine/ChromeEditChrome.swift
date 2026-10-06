import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
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
                    width: MonitorChromeEditBadgeLayout.badgeSize,
                    height: MonitorChromeEditBadgeLayout.badgeSize
                )
                .background(on ? LiveDesign.accent : Color.black.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(LiveDesign.text.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.monitorTapTarget)
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
        let frames = MonitorChromeEditBadgeLayout.badgeFrames(
            PocketDispChrome.Section.allCases.compactMap { section in
                boxes[section].map {
                    MonitorChromeEditBadgeLayout.Box(section: section, frame: $0)
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
                    .font(MonitorTheme.font(11.5, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                Text("Tap an eye to show or hide it")
                    .font(MonitorTheme.font(10, weight: .regular))
                    .foregroundStyle(LiveDesign.muted)
            }
            Button {
                model.endChromeEditing()
            } label: {
                Text("Done")
                    .font(MonitorTheme.font(11.5, weight: .bold))
                    .foregroundStyle(LiveDesign.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LiveDesign.accent, in: Capsule())
            }
            .buttonStyle(.monitorTapTarget)
            .accessibilityIdentifier("monitor.chromeEdit.done")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .liquidGlass(in: Capsule())
        .accessibilityIdentifier("monitor.chromeEdit.banner")
    }
}
