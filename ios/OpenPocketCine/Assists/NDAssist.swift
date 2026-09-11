import OpenPocketViewCore
import SwiftUI

/// Live-picture ND chip. Suggestion only — the app cannot set a screw-on filter.
/// Parks bottom-leading, just above the view-assist toolbar. Hold 0.3 s then
/// drag to move; L-corner grip scales 0.6…1.6. Same movable contract as LIGHTS.
enum NDAssist {
    static let panelID = "nd-meter"
    static let baseSize = ScopePanelSize.ndMeter
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2
    static let meterTitle = "ND"
    static let accessibilityTitle = "ND Suggestion"
    static let defaultNotation = NDFilterNotation.factor
    static let notationTitle = "Units"
    static let notationHelp =
        "Stops vs middle gray, filter factor (ND16 / ND32 / ND64), or optical density (ND 0.3 = 1 stop)."
    static let helpCopy =
        "Meters the live picture against middle gray and suggests a screw-on ND — stops and ND number — to balance it. The app cannot set a filter."
    static var notationOptions: [String] { NDFilterNotation.allCases.map(\.editorLabel) }

    static func longPressMenu(assist _: LiveAssistState) -> NDLongPressMenu {
        NDLongPressMenu()
    }

    /// Bottom-leading, just inside the picture and above the assist/capture strip.
    static func defaultCenter(
        feed: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance: EdgeInsets,
        gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.minX + halfWidth
        let outside = feed.maxY + gap + halfHeight
        let y: CGFloat
        if outside + halfHeight <= bounds.maxY {
            y = outside
        } else {
            y = min(feed.maxY, bounds.maxY - chromeClearance.bottom) - gap - halfHeight
        }
        return clamp(CGPoint(x: x, y: y), size: size, in: bounds)
    }

    static func reading(from bundle: ScopeAssistBundle) -> NDFilterSuggestion? {
        NDFilterRecommendation.reading(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
    }

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

    struct Snapshot: Codable, Equatable, Sendable {
        var scale: Double
        var position: StoredCenter?
        var positionPortrait: StoredCenter?
        var notation: NDFilterNotation?
    }

    static func clampedScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
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
        session: CGPoint? = nil,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, in: bounds) }
        let raw = stored?.center(in: bounds) ?? defaultCenter
        return clamp(raw, size: size, in: bounds)
    }

    @MainActor
    static var store: NDAssistStore { NDAssistStore.shared }
}

@MainActor
@Observable
final class NDAssistStore {
    static let shared = NDAssistStore()
    fileprivate static let prefsKey = "OpenPocketCine.Assist.ndMeter.v1"

    var scale: Double
    var notation: NDFilterNotation
    var position: NDAssist.StoredCenter?
    var positionPortrait: NDAssist.StoredCenter?
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
            let snap = try? JSONDecoder().decode(NDAssist.Snapshot.self, from: data)
        {
            scale = NDAssist.clampedScale(snap.scale)
            notation = snap.notation ?? NDAssist.defaultNotation
            position = snap.position
            positionPortrait = snap.positionPortrait
        } else {
            scale = NDAssist.defaultScale
            notation = NDAssist.defaultNotation
            position = nil
            positionPortrait = nil
        }
    }

    func persist() {
        let snap = NDAssist.Snapshot(
            scale: NDAssist.clampedScale(scale),
            position: position,
            positionPortrait: positionPortrait,
            notation: notation)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: Self.prefsKey)
    }
}

struct NDLongPressMenu: View {
    @Bindable var store = NDAssist.store
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsInlineRow(
                title: NDAssist.notationTitle,
                help: NDAssist.notationHelp,
                showTopDivider: false,
                stacked: true
            ) {
                SettingsSegmented(
                    options: NDAssist.notationOptions,
                    selected: store.notation.editorLabel,
                    compact: true,
                    stacked: compact
                ) { label in
                    guard
                        let next = NDFilterNotation.allCases.first(where: {
                            $0.editorLabel == label
                        })
                    else { return }
                    store.notation = next
                    store.persist()
                }
            }
            Text(NDAssist.helpCopy)
                .font(LiveType.ui(size: 13))
                .foregroundStyle(LiveDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NDMeterOverlay: View {
    @Environment(AppModel.self) private var model
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let store = NDAssist.store
        let size = ScopePanelPlacement.size(
            NDAssist.panelSize(scale: store.scale),
            canvas: bounds, clearance: chromeClearance)
        NDMovablePanel(
            store: store,
            size: size,
            defaultCenter: NDAssist.defaultCenter(
                feed: feed, size: size, bounds: bounds, chromeClearance: chromeClearance),
            bounds: bounds,
            placementBounds: ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        ) {
            NDMeterChip(
                reading: NDAssist.reading(from: model.frameSamples.displayBundle),
                notation: store.notation)
        }
    }
}

/// Compact HUD chip. One label — Stops, ND32, or ND 0.3 — from the long-press setting.
struct NDMeterChip: View {
    var reading: NDFilterSuggestion?
    var notation: NDFilterNotation = NDAssist.defaultNotation

    var body: some View {
        Text(reading?.chipLabel(notation) ?? "—")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(reading?.needsGlass == true ? LiveDesign.accent : LiveDesign.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liveChromeCapsule()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NDAssist.accessibilityTitle)
            .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let reading else { return "waiting for picture" }
        let label = reading.chipLabel(notation)
        if reading.needsGlass {
            return "\(label), \(reading.stopsLabel) stops over middle gray"
        }
        return "\(label), no ND"
    }
}

/// Drag to reposition; drag the corner grip to scale.
struct NDMovablePanel<Content: View>: View {
    @Bindable var store: NDAssistStore
    let size: CGSize
    let defaultCenter: CGPoint
    let bounds: CGRect
    var placementBounds: CGRect? = nil
    private var movementBounds: CGRect { placementBounds ?? ScopePanelPlacement.bounds(in: bounds) }
    @ViewBuilder var content: () -> Content

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0
    @State private var sessionCenter: CGPoint?
    @State private var sessionCenterPortrait: CGPoint?

    private var gripHitSize: CGFloat { NDAssist.gripHitSize }
    private var gripVisualSize: CGFloat { NDAssist.gripVisualSize }
    private var dragHitPadding: CGFloat { NDAssist.dragHitPadding }
    private var gripExteriorGap: CGFloat { NDAssist.gripExteriorGap }
    private var gripCornerInset: CGFloat { gripVisualSize - gripExteriorGap }

    var body: some View {
        let center = clamp(resolvedCenter())
        let gripPad = gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(x: gripPad, y: ScopePanelPlacement.gripBottomExtent)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(dragHitPadding)
                .contentShape(Rectangle())
                .padding(-dragHitPadding)
                .gesture(panelDragGesture(center: center))
        }
        .frame(
            width: size.width + gripPad,
            height: size.height + ScopePanelPlacement.gripBottomExtent,
            alignment: .topLeading
        )
        .opacity(ScopePanelPlacement.isUsable(movementBounds) ? 1 : 0)
        .allowsHitTesting(ScopePanelPlacement.isUsable(movementBounds))
        .shadow(color: .black.opacity((isDragging || isResizing) ? 0.5 : 0), radius: 18, y: 8)
        .position(x: center.x + gripPad / 2, y: center.y + ScopePanelPlacement.gripBottomExtent / 2)
        .sensoryFeedback(trigger: isDragging) { _, dragging in
            dragging ? .impact(flexibility: .rigid, intensity: 1) : nil
        }
        .sensoryFeedback(.selection, trigger: snapCell)
        .sensoryFeedback(trigger: isResizing) { _, resizing in
            resizing ? .impact(flexibility: .rigid, intensity: 0.8) : nil
        }
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .animation(.easeOut(duration: 0.14), value: isResizing)
    }

    private var resizeHandle: some View {
        let gripColor = isResizing ? LiveDesign.accent : LiveDesign.muted
        return NDCornerGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(width: gripVisualSize, height: gripVisualSize, alignment: .bottomTrailing)
            .offset(y: ScopePanelPlacement.gripTopInterior - gripCornerInset)
            .frame(width: gripHitSize, height: gripHitSize, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
    }

    private func panelDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { drag in
                if !isDragging {
                    isDragging = true
                    dragOrigin = center
                }
                guard let origin = dragOrigin else { return }
                let proposed = CGPoint(
                    x: origin.x + drag.translation.width,
                    y: origin.y + drag.translation.height)
                let snapped = clamp(NDAssist.snap(proposed))
                let cell = NDAssist.hapticCell(snapped)
                if cell != snapCell { snapCell = cell }
                ScopeCanvasSlot.assign(
                    &sessionCenter, &sessionCenterPortrait, in: bounds, snapped)
            }
            .onEnded { _ in
                if let final = ScopeCanvasSlot.pick(
                    sessionCenter, sessionCenterPortrait, in: bounds)
                {
                    let stored = NDAssist.StoredCenter(center: final, in: bounds)
                    if ScopeCanvasSlot.forBounds(bounds) == .portrait {
                        store.positionPortrait = stored
                    } else {
                        store.position = stored
                    }
                    store.persist()
                }
                isDragging = false
                dragOrigin = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { drag in
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.scale
                }
                let reach = NDAssist.baseSize.width + NDAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.scale = NDAssist.clampedScale(resizeStartScale + delta)
            }
            .onEnded { _ in
                isResizing = false
                store.persist()
            }
    }

    private func resolvedCenter() -> CGPoint {
        NDAssist.resolvedCenter(
            session: ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds),
            stored: ScopeCanvasSlot.pick(store.position, store.positionPortrait, in: bounds),
            defaultCenter: defaultCenter,
            size: size,
            bounds: bounds)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        ScopePanelPlacement.clamp(point, size: size, in: movementBounds)
    }
}

private struct NDCornerGrip: Shape {
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
