import SwiftUI
import UIKit

/// OpenZCine RGB Parade operator options + `MovablePanel` (id `"parade"`).
///
/// Sources: `OperatorPreferences.Scopes.ParadeMode`,
/// `MonitorPanels.AssistQuickSettingsContent.paradeRows`,
/// `MonitorOverlays.LiveParadeScopePanel` / `ParadeScopePlot` / `ScopeMini` chip,
/// `ScopeTraceMetal.Mode.parade`.
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.paradeRows`):
/// * Mode — RGB / YRGB
/// * Brightness — 0…200% (default 100)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Parade Y is the WAVE IRE axis: 0 / 100 on the plot edges, dotted 5 / 95
/// safe borders, middle gray at paper IRE. No 0 / 50 / 100 labels.
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum ParadeAssist {
    static let panelID = "parade"
    static let longPressPanelWidth: CGFloat = 400
    static let baseSize = ScopePanelSize.parade
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let brightnessRange: ClosedRange<Int> = 0...200
    static let defaultBrightness = 100
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    enum Mode: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case rgb = "RGB"
        case yrgb = "YRGB"
        var id: String { rawValue }
        var laneCount: Int { self == .yrgb ? 4 : 3 }
    }

    /// OpenZCine `AssistQuickSettingsContent.paradeRows` titles (no Size — scale is the grip).
    static let popupRows = [
        "Mode", "Brightness", "Safe Border Clip", "Safe Border Crush", "Middle Gray",
    ]
    static let brightnessHelp =
        "Raise trace intensity when channel separation is hard to see."

    /// OpenZCine `ScopeMini` chip — mode only (`RGB` / `YRGB`), never the transfer.
    static func chip(_ mode: Mode) -> String { mode.rawValue.uppercased() }

    static func accessibilityLabel(_ mode: Mode) -> String {
        mode == .yrgb ? "YRGB parade" : "RGB parade"
    }

    /// Lane letters in draw order — YRGB prepends luma (OpenZCine `ParadeScopePlot`).
    static func laneLabels(_ mode: Mode) -> [String] {
        mode == .yrgb ? ["Y", "R", "G", "B"] : ["R", "G", "B"]
    }

    /// OpenZCine `rect.width / lanes.count`.
    static func laneWidth(mode: Mode, plot: CGRect) -> CGFloat {
        plot.width / CGFloat(mode.laneCount)
    }

    /// OpenZCine `originX + xRatio * (laneWidth - 1)`.
    static func laneX(xRatio: Double, lane: Int, mode: Mode, plot: CGRect) -> CGFloat {
        let width = laneWidth(mode: mode, plot: plot)
        let originX = plot.minX + CGFloat(lane) * width
        return originX + CGFloat(xRatio) * (width - 1)
    }

    struct GuideLines: Codable, Equatable, Sendable {
        var clip: Bool
        var crush: Bool
        var middle: Bool

        static let `default` = GuideLines(clip: true, crush: true, middle: true)

        init(clip: Bool = true, crush: Bool = true, middle: Bool = true) {
            self.clip = clip
            self.crush = crush
            self.middle = middle
        }
    }

    /// OpenZCine `MovablePanelStoredCenter` — centre as a fraction of the overlay bounds.
    struct StoredCenter: Codable, Equatable, Sendable {
        var xFraction: Double
        var yFraction: Double

        init(center: CGPoint, in bounds: CGRect) {
            let width = max(bounds.width, 1)
            let height = max(bounds.height, 1)
            xFraction = Double((center.x - bounds.minX) / width)
            yFraction = Double((center.y - bounds.minY) / height)
        }

        func center(in bounds: CGRect) -> CGPoint {
            CGPoint(
                x: bounds.minX + CGFloat(xFraction) * bounds.width,
                y: bounds.minY + CGFloat(yFraction) * bounds.height)
        }
    }

    struct Options: Equatable, Codable, Sendable {
        var mode: Mode
        var brightness: Int
        var guides: GuideLines
        var scale: Double
        var storedCenter: StoredCenter?
        var storedCenterPortrait: StoredCenter?

        static let `default` = Options(
            mode: .rgb,
            brightness: defaultBrightness,
            guides: .default,
            scale: defaultScale,
            storedCenter: nil,
            storedCenterPortrait: nil)

        init(
            mode: Mode = .rgb,
            brightness: Int = defaultBrightness,
            guides: GuideLines = .default,
            scale: Double = defaultScale,
            storedCenter: StoredCenter? = nil,
            storedCenterPortrait: StoredCenter? = nil
        ) {
            self.mode = mode
            self.brightness = Self.clampedBrightness(brightness)
            self.guides = guides
            self.scale = Self.clampedScale(scale)
            self.storedCenter = storedCenter
            self.storedCenterPortrait = storedCenterPortrait
        }

        enum CodingKeys: String, CodingKey {
            case mode, brightness, guides, scale, storedCenter, storedCenterPortrait
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .rgb
            brightness = Self.clampedBrightness(
                try c.decodeIfPresent(Int.self, forKey: .brightness) ?? defaultBrightness)
            guides = try c.decodeIfPresent(GuideLines.self, forKey: .guides) ?? .default
            scale = Self.clampedScale(
                try c.decodeIfPresent(Double.self, forKey: .scale) ?? defaultScale)
            storedCenter = try c.decodeIfPresent(StoredCenter.self, forKey: .storedCenter)
            storedCenterPortrait = try c.decodeIfPresent(
                StoredCenter.self, forKey: .storedCenterPortrait)
        }

        static func clampedScale(_ value: Double) -> Double {
            min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        }

        static func clampedBrightness(_ value: Int) -> Int {
            min(max(value, brightnessRange.lowerBound), brightnessRange.upperBound)
        }
    }

    /// Trace opacity at the given brightness. OpenZCine uses `/400` after a calibration
    /// pass; Pocket's shipped parade already reads at unity at 100%, so 100% stays 1.0.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `feedOutsideCenter` for the parade's top-trailing default.
    static func defaultCenter(
        feed: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.maxX - halfWidth
        let outside = feed.minY - gap - halfHeight
        let y: CGFloat
        if outside - halfHeight >= bounds.minY {
            y = outside
        } else {
            y = max(feed.minY, bounds.minY + chromeClearance.top) + gap + halfHeight
        }
        return clamp(CGPoint(x: x, y: y), size: size, bounds: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(bounds.minX + halfWidth, point.x), bounds.maxX - halfWidth),
            y: min(max(bounds.minY + halfHeight, point.y), bounds.maxY - halfHeight))
    }

    static func snap(_ point: CGPoint, grid: CGFloat = positionGrid) -> CGPoint {
        CGPoint(
            x: (point.x / grid).rounded() * grid,
            y: (point.y / grid).rounded() * grid)
    }

    static func hapticCell(_ point: CGPoint, grid: CGFloat = hapticGrid) -> Int {
        Int((point.x / grid).rounded()) &* 100_000
            &+ Int((point.y / grid).rounded())
    }

    static func resolvedCenter(
        session: CGPoint?,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, bounds: bounds) }
        if let stored { return clamp(stored.center(in: bounds), size: size, bounds: bounds) }
        return clamp(defaultCenter, size: size, bounds: bounds)
    }

    @MainActor
    static var store: ParadeAssistStore { ParadeAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.paradeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        ParadeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared parade store. `assist` is unused — parade options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> ParadeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Long-press-drag + L-corner resize wrapper (OpenZCine `MovablePanel` id `"parade"`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> ParadeMovablePanel<Content> {
        ParadeMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

@MainActor
@Observable
final class ParadeAssistStore {
    static let shared = ParadeAssistStore(options: load())
    private static let defaultsKey = "OpenPocketCine.ParadeAssist.v1"

    var options: ParadeAssist.Options {
        didSet { persist() }
    }
    /// Session centre in canvas space (OpenZCine `movablePanelCenters["parade"]`).
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    var optionsBinding: Binding<ParadeAssist.Options> {
        Binding(
            get: { self.options },
            set: { self.options = $0 }
        )
    }

    init(options: ParadeAssist.Options = .default) {
        self.options = options
    }

    static func load() -> ParadeAssist.Options {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(ParadeAssist.Options.self, from: data)
        else { return .default }
        return decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func setScale(_ scale: Double) {
        options.scale = ParadeAssist.Options.clampedScale(scale)
    }

    func sessionCenter(in bounds: CGRect) -> CGPoint? {
        ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds)
    }

    func storedCenter(in bounds: CGRect) -> ParadeAssist.StoredCenter? {
        ScopeCanvasSlot.pick(options.storedCenter, options.storedCenterPortrait, in: bounds)
    }

    func beginDrag(center: CGPoint, in bounds: CGRect) {
        ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: bounds, center)
    }

    func drag(to center: CGPoint, in bounds: CGRect) {
        beginDrag(center: center, in: bounds)
    }

    func endDrag(bounds: CGRect) {
        guard let center = sessionCenter(in: bounds) else { return }
        var next = options
        let stored = ParadeAssist.StoredCenter(center: center, in: bounds)
        if ScopeCanvasSlot.forBounds(bounds) == .portrait {
            next.storedCenterPortrait = stored
        } else {
            next.storedCenter = stored
        }
        options = next
    }
}

/// OpenZCine `AssistQuickSettingsContent.paradeRows`.
struct ParadeLongPressMenu: View {
    @Binding var options: ParadeAssist.Options
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(title: "Mode", showTopDivider: false, stacked: compact) {
                SettingsSegmented(
                    options: ParadeAssist.Mode.allCases.map(\.rawValue),
                    selected: options.mode.rawValue,
                    compact: compact,
                    stacked: compact
                ) {
                    guard let mode = ParadeAssist.Mode(rawValue: $0), mode != options.mode else {
                        return
                    }
                    ParadeAssistHaptics.selection()
                    options.mode = mode
                }
            }
            SettingsInlineRow(
                title: "Brightness",
                help: ParadeAssist.brightnessHelp,
                stacked: compact
            ) {
                ParadePercentSlider(
                    value: Binding(
                        get: { options.brightness },
                        set: {
                            let next = ParadeAssist.Options.clampedBrightness($0)
                            guard next != options.brightness else { return }
                            ParadeAssistHaptics.selection()
                            options.brightness = next
                        }),
                    range: ParadeAssist.brightnessRange)
            }
            SettingsSwitchInlineRow(
                title: "Safe Border Clip",
                stacked: compact,
                isOn: options.guides.clip
            ) {
                ParadeAssistHaptics.selection()
                options.guides.clip.toggle()
            }
            SettingsSwitchInlineRow(
                title: "Safe Border Crush",
                stacked: compact,
                isOn: options.guides.crush
            ) {
                ParadeAssistHaptics.selection()
                options.guides.crush.toggle()
            }
            SettingsSwitchInlineRow(
                title: "Middle Gray",
                stacked: compact,
                isOn: options.guides.middle
            ) {
                ParadeAssistHaptics.selection()
                options.guides.middle.toggle()
            }
        }
    }
}

/// OpenZCine `SettingsPercentSlider`.
private struct ParadePercentSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(LiveDesign.accent)
            .frame(minWidth: 120, idealWidth: 190)
            Text("\(value)%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(LiveDesign.text)
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

/// OpenZCine `MovablePanel` specialised for parade — long-press-drag + L-corner resize.
struct ParadeMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content

    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: ParadeAssistStore { ParadeAssist.store }

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0

    private var gripCornerInset: CGFloat {
        ParadeAssist.gripVisualSize - ParadeAssist.gripExteriorGap
    }

    var body: some View {
        let options = store.options
        let size = ParadeAssist.panelSize(scale: options.scale)
        let fallback = ParadeAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = ParadeAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas),
            defaultCenter: fallback,
            size: size,
            bounds: canvas)
        let gripPad = ParadeAssist.gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(x: ParadeAssist.gripExteriorGap, y: ParadeAssist.gripExteriorGap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(ParadeAssist.dragHitPadding)
                .contentShape(Rectangle())
                .padding(-ParadeAssist.dragHitPadding)
                .gesture(interfaceLocked ? nil : panelDragGesture(center: center))
        }
        .frame(
            width: size.width + gripPad,
            height: size.height + gripPad,
            alignment: .topLeading
        )
        .scaleEffect((isDragging || isResizing) ? 1.03 : 1)
        .shadow(color: .black.opacity((isDragging || isResizing) ? 0.5 : 0), radius: 18, y: 8)
        .position(x: center.x + gripPad / 2, y: center.y + gripPad / 2)
        .sensoryFeedback(trigger: isDragging) { _, dragging in
            dragging ? .impact(flexibility: .rigid, intensity: 1) : nil
        }
        .sensoryFeedback(.selection, trigger: snapCell)
        .sensoryFeedback(trigger: isResizing) { _, resizing in
            resizing ? .impact(flexibility: .rigid, intensity: 0.8) : nil
        }
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .animation(.easeOut(duration: 0.14), value: isResizing)
        .allowsHitTesting(!interfaceLocked)
    }

    private func panelDragGesture(center: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: ParadeAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isDragging {
                    isDragging = true
                    dragOrigin = center
                    store.beginDrag(center: center, in: canvas)
                }
                guard let drag, let origin = dragOrigin else { return }
                let proposed = CGPoint(
                    x: origin.x + drag.translation.width,
                    y: origin.y + drag.translation.height)
                let size = ParadeAssist.panelSize(scale: store.options.scale)
                let snapped = ParadeAssist.clamp(
                    ParadeAssist.snap(proposed), size: size, bounds: canvas)
                let cell = ParadeAssist.hapticCell(snapped)
                if cell != snapCell { snapCell = cell }
                store.drag(to: snapped, in: canvas)
            }
            .onEnded { _ in
                store.endDrag(bounds: canvas)
                isDragging = false
                dragOrigin = nil
            }
    }

    private var resizeHandle: some View {
        let gripColor = isResizing ? LiveDesign.accent : LiveDesign.muted
        return ParadeCornerResizeGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(
                width: ParadeAssist.gripVisualSize, height: ParadeAssist.gripVisualSize,
                alignment: .bottomTrailing
            )
            .frame(
                width: ParadeAssist.gripHitSize, height: ParadeAssist.gripHitSize,
                alignment: .bottomTrailing
            )
            .contentShape(Rectangle())
            .gesture(interfaceLocked ? nil : resizeGesture)
            .accessibilityLabel("Resize parade")
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: ParadeAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.options.scale
                }
                guard let drag else { return }
                let reach = ParadeAssist.baseSize.width + ParadeAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.setScale(resizeStartScale + delta)
            }
            .onEnded { _ in isResizing = false }
    }
}

/// OpenZCine `CornerResizeGrip` — L-bracket at the bottom-trailing exterior corner.
struct ParadeCornerResizeGrip: Shape {
    func path(in rect: CGRect) -> Path {
        let leg = min(rect.width, rect.height)
        let vertex = CGPoint(x: rect.maxX, y: rect.maxY)
        var path = Path()
        path.move(to: vertex)
        path.addLine(to: CGPoint(x: vertex.x - leg, y: vertex.y))
        path.move(to: vertex)
        path.addLine(to: CGPoint(x: vertex.x, y: vertex.y - leg))
        return path
    }
}

/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum ParadeAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
