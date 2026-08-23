import SwiftUI
import UIKit

/// OpenZCine waveform operator options + `MovablePanel` (id `"wave"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.waveformRows`):
/// * Mode — Luma / RGB
/// * Brightness — 0…200% (default 100; OpenZCine `/400`, so 100% = 0.25)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Size is the L-corner grip only (OpenZCine dropped Small/Medium/Large; no
/// Size slider in the popup). Scale is 0.6…1.6.
/// WAVE axis matches traffic lights: 0 = paper black, 100 = live-tap
/// ceiling, 18% gray at the log paper IRE (D-Log2 = 30.50). Dotted 5 / 95
/// are safe-border guides. Hold the panel (no drag) or long-press WAVE
/// on the assist bar to open options.
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid).
/// No pinch-resize — OpenZCine scales only from the L-corner grip.
enum WaveformAssist {
    static let panelID = "wave"
    static let longPressPanelWidth: CGFloat = 400
    static let baseSize = ScopePanelSize.waveform
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

    /// OpenZCine `AssistQuickSettingsContent.waveformRows` titles (no Size, no IRE labels).
    static let popupRows = [
        "Mode", "Brightness", "Safe Border Clip", "Safe Border Crush", "Middle Gray",
    ]
    static let brightnessHelp =
        "Raise trace intensity when the waveform is hard to read in bright light."

    enum Mode: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case luma = "Luma"
        case rgb = "RGB"
        var id: String { rawValue }
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

    /// OpenZCine `waveformParadeBrightnessMultiplier` — 100% = former 25%.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 400
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `feedOutsideCenter` for the waveform's top-leading default.
    static func defaultCenter(
        feed: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.minX + halfWidth
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
    static var store: WaveformAssistStore { WaveformAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.waveformRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        WaveformLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared waveform store. Options live off `LiveAssistState` so
    /// parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> WaveformLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> WaveformLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Hold-without-drag on the WAVE panel, or long-press the WAVE chip.
    @MainActor
    static func presentOptions(anchor: CGRect, assist: LiveAssistState) {
        assist.longPressAnchor = anchor
        assist.configureTool = .waveform
    }

    static func shouldPresentOptions(translation: CGSize) -> Bool {
        WaveformAxis.shouldPresentOptions(translation: translation)
    }

    /// Long-press-drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    /// A hold that does not drag opens ``presentOptions``.
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        onOpenOptions: ((CGRect) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> WaveformMovablePanel<Content> {
        WaveformMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance,
            onOpenOptions: onOpenOptions, content: content)
    }
}

@MainActor
@Observable
final class WaveformAssistStore {
    static let shared = WaveformAssistStore(options: load())
    private static let defaultsKey = "OpenPocketCine.WaveformAssist.v1"

    var options: WaveformAssist.Options {
        didSet { persist() }
    }
    /// Session centre in canvas space (OpenZCine `movablePanelCenters["wave"]`).
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    var optionsBinding: Binding<WaveformAssist.Options> {
        Binding(
            get: { self.options },
            set: { self.options = $0 }
        )
    }

    init(options: WaveformAssist.Options = .default) {
        self.options = options
    }

    static func load() -> WaveformAssist.Options {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(WaveformAssist.Options.self, from: data)
        else { return .default }
        return decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func setScale(_ scale: Double) {
        options.scale = WaveformAssist.Options.clampedScale(scale)
    }

    func sessionCenter(in bounds: CGRect) -> CGPoint? {
        ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds)
    }

    func storedCenter(in bounds: CGRect) -> WaveformAssist.StoredCenter? {
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
        let stored = WaveformAssist.StoredCenter(center: center, in: bounds)
        if ScopeCanvasSlot.forBounds(bounds) == .portrait {
            next.storedCenterPortrait = stored
        } else {
            next.storedCenter = stored
        }
        options = next
    }
}

/// OpenZCine `AssistQuickSettingsContent.waveformRows`.
struct WaveformLongPressMenu: View {
    @Binding var options: WaveformAssist.Options
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(title: "Mode", showTopDivider: false, stacked: compact) {
                SettingsSegmented(
                    options: WaveformAssist.Mode.allCases.map(\.rawValue),
                    selected: options.mode.rawValue,
                    compact: compact,
                    stacked: compact
                ) {
                    guard let mode = WaveformAssist.Mode(rawValue: $0), mode != options.mode else {
                        return
                    }
                    WaveformAssistHaptics.selection()
                    options.mode = mode
                }
            }
            SettingsInlineRow(
                title: "Brightness",
                help: WaveformAssist.brightnessHelp,
                stacked: compact
            ) {
                WaveformPercentSlider(
                    value: Binding(
                        get: { options.brightness },
                        set: {
                            let next = WaveformAssist.Options.clampedBrightness($0)
                            guard next != options.brightness else { return }
                            WaveformAssistHaptics.selection()
                            options.brightness = next
                        }),
                    range: WaveformAssist.brightnessRange)
            }
            SettingsSwitchInlineRow(
                title: "Safe Border Clip",
                stacked: compact,
                isOn: options.guides.clip
            ) {
                WaveformAssistHaptics.selection()
                options.guides.clip.toggle()
            }
            SettingsSwitchInlineRow(
                title: "Safe Border Crush",
                stacked: compact,
                isOn: options.guides.crush
            ) {
                WaveformAssistHaptics.selection()
                options.guides.crush.toggle()
            }
            SettingsSwitchInlineRow(
                title: "Middle Gray",
                stacked: compact,
                isOn: options.guides.middle
            ) {
                WaveformAssistHaptics.selection()
                options.guides.middle.toggle()
            }
        }
    }
}

/// OpenZCine `SettingsPercentSlider`.
private struct WaveformPercentSlider: View {
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

/// OpenZCine `MovablePanel` specialised for waveform — long-press-drag + L-corner resize.
struct WaveformMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    var onOpenOptions: ((CGRect) -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: WaveformAssistStore { WaveformAssist.store }

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0

    private var gripCornerInset: CGFloat {
        WaveformAssist.gripVisualSize - WaveformAssist.gripExteriorGap
    }

    var body: some View {
        let options = store.options
        let size = WaveformAssist.panelSize(scale: options.scale)
        let fallback = WaveformAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = WaveformAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas),
            defaultCenter: fallback,
            size: size,
            bounds: canvas)
        let gripPad = WaveformAssist.gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(
                            x: WaveformAssist.gripExteriorGap, y: WaveformAssist.gripExteriorGap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(WaveformAssist.dragHitPadding)
                .contentShape(Rectangle())
                .padding(-WaveformAssist.dragHitPadding)
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

    /// Long-press then drag on the panel body to reposition (not applied to the resize grip).
    private func panelDragGesture(center: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: WaveformAssist.holdDuration)
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
                let size = WaveformAssist.panelSize(scale: store.options.scale)
                let snapped = WaveformAssist.clamp(
                    WaveformAssist.snap(proposed), size: size, bounds: canvas)
                let cell = WaveformAssist.hapticCell(snapped)
                if cell != snapCell { snapCell = cell }
                store.drag(to: snapped, in: canvas)
            }
            .onEnded { value in
                let heldAndReleased: (CGSize)?
                if case .second(true, let drag) = value {
                    heldAndReleased = drag?.translation ?? .zero
                } else {
                    heldAndReleased = nil
                }
                store.endDrag(bounds: canvas)
                isDragging = false
                dragOrigin = nil
                if let translation = heldAndReleased,
                    WaveformAssist.shouldPresentOptions(translation: translation)
                {
                    let size = WaveformAssist.panelSize(scale: store.options.scale)
                    let frame = CGRect(
                        x: center.x - size.width / 2,
                        y: center.y - size.height / 2,
                        width: size.width,
                        height: size.height)
                    WaveformAssistHaptics.confirm()
                    onOpenOptions?(frame)
                }
            }
    }

    private var resizeHandle: some View {
        let gripColor = isResizing ? LiveDesign.accent : LiveDesign.muted
        return WaveformCornerResizeGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(
                width: WaveformAssist.gripVisualSize, height: WaveformAssist.gripVisualSize,
                alignment: .bottomTrailing
            )
            .frame(
                width: WaveformAssist.gripHitSize, height: WaveformAssist.gripHitSize,
                alignment: .bottomTrailing
            )
            .contentShape(Rectangle())
            .gesture(interfaceLocked ? nil : resizeGesture)
            .accessibilityLabel("Resize waveform")
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: WaveformAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.options.scale
                }
                guard let drag else { return }
                let reach = WaveformAssist.baseSize.width + WaveformAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.setScale(resizeStartScale + delta)
            }
            .onEnded { _ in isResizing = false }
    }
}

/// OpenZCine `CornerResizeGrip` — L-bracket at the bottom-trailing exterior corner.
struct WaveformCornerResizeGrip: Shape {
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
private enum WaveformAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    static func confirm() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }
}
