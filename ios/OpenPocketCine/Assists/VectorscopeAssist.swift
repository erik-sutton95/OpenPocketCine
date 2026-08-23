import SwiftUI
import UIKit

/// OpenZCine vectorscope operator options + `MovablePanel` (id `"vector"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.vectorscopeRows`):
/// * Trace Zoom — 1x / 2x / 4x (graticule stays at unity)
/// * Brightness — 0…200% (default 100; unity baseline, unlike WAVE/PARADE’s /400)
///
/// Always-on plot (no popup toggle in OpenZCine): 75% graticule, 123° I-phase
/// skin line, colour density rendering (log alpha + `traceTint` + 1.1-bin blur
/// + 0.35 crisp core + 0.35 trail).
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum VectorscopeAssist {
    static let panelID = "vector"
    static let longPressPanelWidth: CGFloat = 400
    static let baseSize = ScopePanelSize.vectorscope
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

    /// OpenZCine `AssistConfiguration.Scopes.VectorscopeZoom`.
    enum Zoom: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case x1 = "1x"
        case x2 = "2x"
        case x4 = "4x"
        var id: String { rawValue }

        /// Multiplier applied to plotted chroma before binning. Graticule stays at unity.
        var gain: Double {
            switch self {
            case .x1: 1
            case .x2: 2
            case .x4: 4
            }
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
        var zoom: Zoom
        var brightness: Int
        var scale: Double
        var storedCenter: StoredCenter?
        var storedCenterPortrait: StoredCenter?

        static let `default` = Options(
            zoom: .x1,
            brightness: defaultBrightness,
            scale: defaultScale,
            storedCenter: nil,
            storedCenterPortrait: nil)

        init(
            zoom: Zoom = .x1,
            brightness: Int = defaultBrightness,
            scale: Double = defaultScale,
            storedCenter: StoredCenter? = nil,
            storedCenterPortrait: StoredCenter? = nil
        ) {
            self.zoom = zoom
            self.brightness = Self.clampedBrightness(brightness)
            self.scale = Self.clampedScale(scale)
            self.storedCenter = storedCenter
            self.storedCenterPortrait = storedCenterPortrait
        }

        enum CodingKeys: String, CodingKey {
            case zoom, brightness, scale, storedCenter, storedCenterPortrait
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            zoom = try c.decodeIfPresent(Zoom.self, forKey: .zoom) ?? .x1
            brightness = Self.clampedBrightness(
                try c.decodeIfPresent(Int.self, forKey: .brightness) ?? defaultBrightness)
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

    /// OpenZCine `Scopes.brightnessMultiplier` — vectorscope keeps the unity baseline.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `ScopeMini` vectorscope chip — `MON · 1X`.
    static func chip(zoom: Zoom) -> String {
        "MON · \(zoom.rawValue.uppercased())"
    }

    /// OpenZCine `feedOutsideCenter` for the vectorscope's top-trailing default.
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
    static var store: VectorscopeAssistStore { VectorscopeAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        VectorscopeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared vectorscope store. `assist` is unused — options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> VectorscopeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// OpenZCine `AssistQuickSettingsContent.vectorscopeRows` titles, in order.
    static let popupRows = ["Trace Zoom", "Brightness"]

    /// Long-press-drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> VectorscopeMovablePanel<Content> {
        VectorscopeMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

@MainActor
@Observable
final class VectorscopeAssistStore {
    static let shared = VectorscopeAssistStore(options: load())
    private static let defaultsKey = "OpenPocketCine.VectorscopeAssist.v1"

    var options: VectorscopeAssist.Options {
        didSet { persist() }
    }
    /// Session centre in canvas space (OpenZCine `movablePanelCenters["vector"]`).
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    var optionsBinding: Binding<VectorscopeAssist.Options> {
        Binding(
            get: { self.options },
            set: { self.options = $0 }
        )
    }

    init(options: VectorscopeAssist.Options = .default) {
        self.options = options
    }

    static func load() -> VectorscopeAssist.Options {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(VectorscopeAssist.Options.self, from: data)
        else { return .default }
        return decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func setScale(_ scale: Double) {
        options.scale = VectorscopeAssist.Options.clampedScale(scale)
    }

    func sessionCenter(in bounds: CGRect) -> CGPoint? {
        ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds)
    }

    func storedCenter(in bounds: CGRect) -> VectorscopeAssist.StoredCenter? {
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
        let stored = VectorscopeAssist.StoredCenter(center: center, in: bounds)
        if ScopeCanvasSlot.forBounds(bounds) == .portrait {
            next.storedCenterPortrait = stored
        } else {
            next.storedCenter = stored
        }
        options = next
    }
}

/// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
struct VectorscopeLongPressMenu: View {
    @Binding var options: VectorscopeAssist.Options
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInlineRow(
                title: "Trace Zoom",
                help:
                    "Magnifies only the chroma trace; the graticule stays at unity. The vectorscope reads the monitor image (your active LUT, or the built-in display tone map), where chroma is meaningful.",
                showTopDivider: false,
                stacked: compact
            ) {
                SettingsSegmented(
                    options: VectorscopeAssist.Zoom.allCases.map(\.rawValue),
                    selected: options.zoom.rawValue,
                    compact: compact,
                    stacked: compact
                ) {
                    guard let zoom = VectorscopeAssist.Zoom(rawValue: $0), zoom != options.zoom
                    else { return }
                    VectorscopeAssistHaptics.selection()
                    options.zoom = zoom
                }
            }
            SettingsInlineRow(
                title: "Brightness",
                help: "Raise trace intensity when the chroma plot is hard to read.",
                stacked: compact
            ) {
                VectorscopePercentSlider(
                    value: Binding(
                        get: { options.brightness },
                        set: {
                            let next = VectorscopeAssist.Options.clampedBrightness($0)
                            guard next != options.brightness else { return }
                            VectorscopeAssistHaptics.selection()
                            options.brightness = next
                        }),
                    range: VectorscopeAssist.brightnessRange)
            }
        }
    }
}

/// OpenZCine `SettingsPercentSlider`.
private struct VectorscopePercentSlider: View {
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

/// OpenZCine `MovablePanel` specialised for vectorscope — long-press-drag + L-corner resize.
struct VectorscopeMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content

    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: VectorscopeAssistStore { VectorscopeAssist.store }

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0

    private var gripCornerInset: CGFloat {
        VectorscopeAssist.gripVisualSize - VectorscopeAssist.gripExteriorGap
    }

    var body: some View {
        let options = store.options
        let size = VectorscopeAssist.panelSize(scale: options.scale)
        let fallback = VectorscopeAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = VectorscopeAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas),
            defaultCenter: fallback,
            size: size,
            bounds: canvas)
        let gripPad = VectorscopeAssist.gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(
                            x: VectorscopeAssist.gripExteriorGap,
                            y: VectorscopeAssist.gripExteriorGap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(VectorscopeAssist.dragHitPadding)
                .contentShape(Rectangle())
                .padding(-VectorscopeAssist.dragHitPadding)
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
        LongPressGesture(minimumDuration: VectorscopeAssist.holdDuration)
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
                let size = VectorscopeAssist.panelSize(scale: store.options.scale)
                let snapped = VectorscopeAssist.clamp(
                    VectorscopeAssist.snap(proposed), size: size, bounds: canvas)
                let cell = VectorscopeAssist.hapticCell(snapped)
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
        return VectorscopeCornerResizeGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(
                width: VectorscopeAssist.gripVisualSize,
                height: VectorscopeAssist.gripVisualSize,
                alignment: .bottomTrailing
            )
            .frame(
                width: VectorscopeAssist.gripHitSize,
                height: VectorscopeAssist.gripHitSize,
                alignment: .bottomTrailing
            )
            .contentShape(Rectangle())
            .gesture(interfaceLocked ? nil : resizeGesture)
            .accessibilityLabel("Resize vectorscope")
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: VectorscopeAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.options.scale
                }
                guard let drag else { return }
                let reach = VectorscopeAssist.baseSize.width + VectorscopeAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.setScale(resizeStartScale + delta)
            }
            .onEnded { _ in isResizing = false }
    }
}

/// OpenZCine `CornerResizeGrip` — L-bracket at the bottom-trailing exterior corner.
struct VectorscopeCornerResizeGrip: Shape {
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
private enum VectorscopeAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
