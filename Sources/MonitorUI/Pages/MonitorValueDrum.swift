#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// A cylindrical selector shared by capture, movement and preview controls.
    /// During a drag only the visual detent moves; the binding commits once on lift.
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
        private var settleAnimation: Animation? {
            reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.1)
        }

        public var body: some View {
            GeometryReader { geometry in
                let cellWidth = min(
                    180, max(76, CGFloat(options.map(\.count).max() ?? 4) * 10 + 24))
                ZStack {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        let distance = Double(index) - position
                        if abs(distance) < 4 {
                            drumCell(option, distance: distance, width: cellWidth)
                                .position(x: geometry.size.width / 2 + distance * cellWidth, y: 43)
                                .onTapGesture { commit(option) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .updating($dragging) { _, active, _ in active = true }
                        .onChanged { value in
                            guard isInteractive,
                                drag.begin(selection: selection, identity: interactionIdentity())
                            else { return }
                            translation = value.translation.width
                        }
                        .onEnded { value in
                            let origin = drag.end(identity: interactionIdentity())
                            guard isInteractive, let origin,
                                let index = MonitorDrumSelection.changedIndex(
                                    origin: options.firstIndex(of: origin) ?? 0,
                                    translation: value.translation.width,
                                    count: options.count)
                            else {
                                resetDrag()
                                return
                            }
                            commit(options[index])
                        }
                )
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                            .init(color: .black, location: 0.86), .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                }
                .clipped()
            }
            .frame(height: 86)
            .opacity(isInteractive ? 1 : 0.45)
            .onChange(of: options) { _, _ in cancelDrag() }
            .onChange(of: selection) { _, _ in if drag.origin != nil { cancelDrag() } }
            .onChange(of: interactionIdentity()) { _, _ in cancelDrag() }
            .onChange(of: isInteractive) { _, active in if !active { cancelDrag() } }
            .onChange(of: dragging) { _, active in
                if !active {
                    resetDrag()
                }
            }
            .sensoryFeedback(.selection, trigger: focusedIndex) { _, _ in haptics && isInteractive }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Value")
            .accessibilityValue(selection.isEmpty ? "Not set" : selection)
            .accessibilityAdjustableAction { direction in
                guard isInteractive, !options.isEmpty else { return }
                let next =
                    options.firstIndex(of: selection).map {
                        direction == .increment ? $0 + 1 : $0 - 1
                    } ?? 0
                if options.indices.contains(next) { commit(options[next]) }
            }
        }

        private func commit(_ option: String) {
            guard isInteractive, options.contains(option) else { return }
            withAnimation(settleAnimation) {
                if selection != option { selection = option }
                drag.cancel(pointerIsActive: dragging)
                translation = 0
            }
        }

        private func resetDrag() {
            drag.reset()
            translation = 0
        }
        private func cancelDrag() {
            drag.cancel(pointerIsActive: dragging)
            translation = 0
        }

        private func drumCell(_ option: String, distance: Double, width: CGFloat) -> some View {
            let proximity = max(0, 1 - abs(distance))
            let selected =
                abs(distance) < 0.5
                && (dragging || previewPosition != nil || options.contains(selection))
            return VStack(spacing: 8) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(option).font(
                        MonitorTheme.font(
                            15 + 8 * proximity, weight: selected ? .semibold : .regular)
                    )
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    if markedValues.contains(option) {
                        MonitorIcon.star.view(filled: true).frame(width: 9, height: 9)
                    }
                }
                .foregroundStyle(selected ? MonitorTheme.text : MonitorTheme.muted)
                .frame(height: 32, alignment: .bottom)
                .rotation3DEffect(
                    .degrees(max(-65, min(65, distance * -22))), axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5)
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(0..<10, id: \.self) { _ in
                            Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 5)
                        }
                    }
                    Rectangle().fill(selected ? MonitorTheme.accent : MonitorTheme.muted)
                        .frame(width: 2, height: selected ? 15 : 9)
                }
            }
            .frame(width: width, height: 78)
            .contentShape(Rectangle())
        }
    }
#endif
