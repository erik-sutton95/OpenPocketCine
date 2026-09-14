#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// A cylindrical selector shared by capture, movement and preview controls.
    /// During a drag only the visual detent moves; the binding commits once on lift.
    /// A supplied preview position is read-only and retains the enabled appearance;
    /// its selection binding describes the displayed value, or empty for unknown.
    public struct MonitorValueDrum: View {
        public let options: [String]
        @Binding private var selection: String
        private let markedValues: Set<String>
        private let isInteractive: Bool
        private let haptics: Bool
        private let previewPosition: Double?
        private let interactionIdentity: () -> AnyHashable
        @State private var drag = MonitorDrumDrag<AnyHashable>()
        @State private var translation: CGFloat = 0
        /// GestureState lags the first `onChanged`, so finger tracking is a
        /// separate flag set in the same write as the first translation.
        @State private var tracking = false
        @State private var canvasWidth: CGFloat = 0
        @GestureState private var dragging = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(
            options: [String], selection: Binding<String>, markedValues: Set<String> = [],
            isInteractive: Bool = true, haptics: Bool = true, previewPosition: Double? = nil,
            interactionIdentity: @escaping () -> AnyHashable = { AnyHashable(0) }
        ) {
            self.options = options
            _selection = selection
            self.markedValues = markedValues
            self.isInteractive = isInteractive
            self.haptics = haptics
            self.previewPosition = previewPosition
            self.interactionIdentity = interactionIdentity
        }

        private var originIndex: Int { options.firstIndex(of: drag.origin ?? selection) ?? 0 }
        private var position: Double {
            if let previewPosition, previewPosition.isFinite {
                return min(Double(max(0, options.count - 1)), max(0, previewPosition))
            }
            return MonitorDrumSelection.position(
                origin: originIndex, translation: translation, count: options.count)
        }
        private var focusedIndex: Int { Int(position.rounded()) }
        private var acceptsInput: Bool { isInteractive && previewPosition == nil }
        private var followsFinger: Bool { tracking || dragging }
        private var settleAnimation: Animation? {
            MonitorMotion.settle(reduceMotion)
        }

        public var body: some View {
            let metrics = MonitorDrumMetrics(options: options)
            let currentPosition = position
            let hasSelection = followsFinger || options.contains(selection)
            let rows = options.enumerated().compactMap { index, option -> MonitorDrumRow? in
                let distance = Double(index) - currentPosition
                guard abs(distance) < 4 else { return nil }
                return MonitorDrumRow(
                    option: option, distance: distance,
                    selected: abs(distance) < 0.5 && hasSelection,
                    marked: markedValues.contains(option), metrics: metrics,
                    action: { commit(option) })
            }
            Self.drawing(rows: rows, position: currentPosition, cellWidth: metrics.cellWidth)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: DrumCanvasWidthKey.self, value: proxy.size.width)
                    }
                }
                .onPreferenceChange(DrumCanvasWidthKey.self) { canvasWidth = $0 }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragging) { _, active, _ in active = true }
                        .onChanged { value in
                            guard acceptsInput,
                                drag.begin(selection: selection, identity: interactionIdentity())
                            else { return }
                            followFinger(value.translation.width)
                        }
                        .onEnded { value in
                            finishPointer(value, metrics: metrics)
                        }
                )
                .frame(height: 86)
                .transaction { if followsFinger || previewPosition != nil { $0.animation = nil } }
                .animation(
                    followsFinger || previewPosition != nil ? nil : settleAnimation, value: selection
                )
                .opacity(isInteractive || previewPosition != nil ? 1 : 0.45)
                .onChange(of: options) { _, _ in cancelDrag() }
                .onChange(of: selection) { _, _ in if drag.origin != nil { cancelDrag() } }
                .onChange(of: interactionIdentity()) { _, _ in cancelDrag() }
                .onChange(of: acceptsInput) { _, active in if !active { cancelDrag() } }
                .onChange(of: dragging) { _, active in
                    if !active {
                        tracking = false
                        if drag.origin != nil { settleToRest() }
                    }
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: focusedIndex) { old, new in
                    guard haptics, isInteractive || previewPosition != nil,
                        options.indices.contains(new)
                    else {
                        return false
                    }
                    let previous = options.indices.contains(old) ? options[old] : nil
                    return MonitorDialHaptic.shouldTick(
                        previous: previous, next: options[new], optionCount: options.count)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Value")
                .accessibilityValue(selection.isEmpty ? "Not set" : selection)
                .accessibilityAdjustableAction { direction in
                    guard acceptsInput, !options.isEmpty else { return }
                    let next =
                        options.firstIndex(of: selection).map {
                            direction == .increment ? $0 + 1 : $0 - 1
                        } ?? 0
                    if options.indices.contains(next) { commit(options[next]) }
                }
        }

        private func finishPointer(_ value: DragGesture.Value, metrics: MonitorDrumMetrics) {
            let origin = drag.end(identity: interactionIdentity())
            tracking = false
            guard acceptsInput, let origin else {
                settleToRest()
                return
            }
            let originIndex = options.firstIndex(of: origin) ?? 0
            let travel = hypot(value.translation.width, value.translation.height)
            if travel < 10, canvasWidth > 1 {
                let dx = Double(value.startLocation.x - canvasWidth / 2)
                let tapped = Int((Double(originIndex) + dx / metrics.cellWidth).rounded())
                if options.indices.contains(tapped) {
                    commit(options[tapped])
                    return
                }
            }
            if let index = MonitorDrumSelection.changedIndex(
                origin: originIndex, translation: value.translation.width, count: options.count)
            {
                commit(options[index])
            } else {
                settleToRest()
            }
        }

        private func commit(_ option: String) {
            guard acceptsInput, options.contains(option) else { return }
            tracking = false
            withAnimation(settleAnimation) {
                if selection != option { selection = option }
                drag.cancel(pointerIsActive: dragging)
                translation = 0
            }
        }

        private func followFinger(_ next: CGFloat) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                tracking = true
                translation = next
            }
        }

        private func settleToRest() {
            tracking = false
            withAnimation(settleAnimation) {
                drag.reset()
                translation = 0
            }
        }

        private func resetDrag() {
            drag.reset()
            translation = 0
        }
        private func cancelDrag() {
            drag.cancel(pointerIsActive: dragging)
            tracking = false
            translation = 0
        }

        /// SwiftUI may call deferred GeometryReader/ForEach render closures on
        /// AsyncRenderer. These factories capture immutable drawing data only;
        /// camera state and binding access stay in body or an explicit action.
        nonisolated private static func drawing(
            rows: [MonitorDrumRow], position: Double, cellWidth: Double
        ) -> some View {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ruler(position: position, cellWidth: cellWidth)
                    renderRows(rows, width: geometry.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                            .init(color: .black, location: 0.86), .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                }
                .clipped()
            }
        }

        nonisolated static func renderRows(_ rows: [MonitorDrumRow], width: CGFloat)
            -> ForEach<[MonitorDrumRow], String, MonitorDrumValueCell>
        {
            ForEach(rows, id: \.option) { row in
                MonitorDrumValueCell(row: row, canvasWidth: width)
            }
        }

        nonisolated private static func ruler(position: Double, cellWidth: Double) -> some View {
            Canvas { context, size in
                let phase = (size.width / 2 - position * cellWidth).truncatingRemainder(
                    dividingBy: 6.75)
                var ticks = Path()
                for offset in stride(from: phase - 6.75, through: size.width + 6.75, by: 6.75) {
                    ticks.move(to: CGPoint(x: offset, y: 73))
                    ticks.addLine(to: CGPoint(x: offset, y: 78))
                }
                context.stroke(ticks, with: .color(.white.opacity(0.22)), lineWidth: 1)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private struct DrumCanvasWidthKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    struct MonitorDrumRow: Sendable {
        let option: String
        let distance: Double
        let selected: Bool
        let marked: Bool
        let metrics: MonitorDrumMetrics
        let action: @MainActor @Sendable () -> Void
    }

    struct MonitorDrumValueCell: View {
        nonisolated let row: MonitorDrumRow
        nonisolated let canvasWidth: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        nonisolated init(row: MonitorDrumRow, canvasWidth: CGFloat) {
            self.row = row
            self.canvasWidth = canvasWidth
        }

        var body: some View {
            ZStack(alignment: .top) {
                HStack(spacing: 3) {
                    Text(row.option).font(
                        MonitorTheme.font(15, weight: row.selected ? .semibold : .regular)
                    )
                    .monospacedDigit().lineLimit(1).fixedSize()
                    if row.marked {
                        MonitorIcon.star.view(filled: true).frame(width: 8, height: 8)
                    }
                }
                .foregroundStyle(row.selected ? Color.white : Color.white.opacity(0.45))
                .frame(height: 26, alignment: .bottom)
                .scaleEffect(row.selected ? row.metrics.selectedScale : 1, anchor: .bottom)
                .padding(.top, 18)
                Rectangle().fill(row.selected ? MonitorTheme.accent : Color.white.opacity(0.34))
                    .frame(width: 2, height: row.selected ? 17 : 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: row.metrics.cellWidth, height: 78)
            .contentShape(Rectangle())
            .animation(
                MonitorMotion.curve(MonitorMotion.soft, duration: 0.18, reduceMotion: reduceMotion),
                value: row.selected
            )
            .position(x: canvasWidth / 2 + row.distance * row.metrics.cellWidth, y: 39)
            .animation(nil, value: row.distance)
            .allowsHitTesting(false)
        }
    }
#endif
