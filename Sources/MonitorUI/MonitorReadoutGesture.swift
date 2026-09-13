#if os(iOS)
    import MonitorPresentation
    import SwiftUI
    import UIKit

    /// One recognizer owns tap, hold and drag while the host draws a passive
    /// preview elsewhere. Only pointer-down starts a timer; no idle work runs.
    ///
    /// Inputs are immutable display/source snapshots. presentationOwner is read
    /// on the main actor at event time so external dismissal cannot race release.
    /// The host renders preview events, closes the matching preview on commit or
    /// cancel, and alone decides whether a release may perform native work.
    public struct MonitorReadoutGesture<SourceIdentity: Hashable & Sendable>: ViewModifier {
        private let snapshot: MonitorReadoutSnapshot?
        private let sourceIdentity: SourceIdentity
        private let isEnabled: Bool
        @Binding private var ownership: MonitorReadoutOwnership
        private let presentationOwner: @MainActor () -> UUID?
        private let onEvent: @MainActor (MonitorReadoutEvent<SourceIdentity>) -> Void
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.monitorWindowGeometry) private var windowGeometry
        @State private var interaction = MonitorReadoutInteraction()
        @State private var admission: Admission?
        @State private var identity = UUID()
        @State private var holdTask: Task<Void, Never>?
        @GestureState private var touching = false

        private struct Admission: Equatable {
            let snapshot: MonitorReadoutSnapshot?
            let source: SourceIdentity
            let window: MonitorWindowGeometry
            let revision: UInt64
        }

        public init(
            snapshot: MonitorReadoutSnapshot?, sourceIdentity: SourceIdentity,
            isEnabled: Bool, ownership: Binding<MonitorReadoutOwnership>,
            presentationOwner: @escaping @MainActor () -> UUID?,
            onEvent: @escaping @MainActor (MonitorReadoutEvent<SourceIdentity>) -> Void
        ) {
            self.snapshot = snapshot
            self.sourceIdentity = sourceIdentity
            self.isEnabled = isEnabled
            _ownership = ownership
            self.presentationOwner = presentationOwner
            self.onEvent = onEvent
        }

        private var canInteract: Bool { isEnabled && scenePhase == .active }
        private var ownsPointer: Bool {
            ownership.owns(identity)
                && (presentationOwner() == nil || presentationOwner() == identity)
        }
        private var admissionIsCurrent: Bool {
            guard let admission else { return false }
            return admission.snapshot == snapshot && admission.source == sourceIdentity
                && admission.window == windowGeometry
        }

        public func body(content: Content) -> some View {
            let interactive = interactiveContent(content)
            let lifecycle = observeLifecycle(interactive)
            let admission = observeAdmission(lifecycle)
            return observeOwnership(admission)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) {
                    if canInteract, ownership.owner == nil, presentationOwner() == nil {
                        onEvent(.open(sourceIdentity))
                    }
                }
        }

        private func interactiveContent(_ content: Content) -> some View {
            content
                .accessibilityElement(children: .ignore)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($touching) { _, active, _ in active = true }
                        .onChanged(handleChanged)
                        .onEnded(handleEnded)
                )
                .onChange(of: touching) { _, active in
                    if !active, interaction.phase != .idle { cancel() }
                }
        }

        private func observeAdmission<V: View>(_ content: V) -> some View {
            content
                .onChange(of: isEnabled) { _, enabled in if !enabled { cancel() } }
                .onChange(of: snapshot) { _, _ in cancel() }
                .onChange(of: sourceIdentity) { _, _ in cancel() }
                .onChange(of: windowGeometry) { _, _ in cancel() }
        }

        private func observeOwnership<V: View>(_ content: V) -> some View {
            content
                .onChange(of: presentationOwner()) { _, owner in
                    if interaction.phase == .drumming, owner != identity { cancel() }
                    if interaction.phase == .pressing, let owner, owner != identity { cancel() }
                }
                .onChange(of: ownership.owner) { _, owner in
                    if interaction.phase != .idle, owner != identity { cancel() }
                }
        }

        private func observeLifecycle<V: View>(_ content: V) -> some View {
            content
                .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIDevice.orientationDidChangeNotification)
                ) { _ in cancel() }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willResignActiveNotification)
                ) { _ in cancel() }
                .onDisappear { cancel() }
        }

        private func handleChanged(_ value: DragGesture.Value) {
            guard canInteract else {
                cancel()
                return
            }
            if interaction.phase == .idle, !begin() { return }
            guard ownsPointer, admissionIsCurrent else {
                cancel()
                return
            }
            let armed = interaction.move(x: value.translation.width, y: value.translation.height)
            if armed { holdTask?.cancel() }
            if interaction.phase == .drumming { publish() }
        }

        private func handleEnded(_ value: DragGesture.Value) {
            holdTask?.cancel()
            holdTask = nil
            guard canInteract, ownsPointer, admissionIsCurrent, let admission else {
                cancel()
                _ = interaction.end()
                return
            }
            _ = interaction.move(x: value.translation.width, y: value.translation.height)
            let owned = presentationOwner() == identity
            let outcome = interaction.end()
            ownership.release(identity)
            self.admission = nil
            switch outcome {
            case .tap: onEvent(.open(admission.source))
            case .commit(let translation):
                if owned, let snapshot = admission.snapshot {
                    onEvent(
                        .commit(
                            MonitorReadoutValue(
                                id: identity, sourceIdentity: admission.source, snapshot: snapshot,
                                position: snapshot.position(translation: translation)),
                            ownershipRevision: admission.revision))
                } else {
                    onEvent(.cancel(identity))
                }
            case .cancelled: onEvent(.cancel(identity))
            }
        }

        private func begin() -> Bool {
            guard canInteract, presentationOwner() == nil else {
                interaction.cancel()
                return false
            }
            let nextIdentity = UUID()
            guard let revision = ownership.acquire(nextIdentity) else {
                interaction.cancel()
                return false
            }
            identity = nextIdentity
            admission = Admission(
                snapshot: snapshot, source: sourceIdentity, window: windowGeometry,
                revision: revision)
            interaction.begin()
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(MonitorReadoutInteraction.holdMilliseconds))
                guard !Task.isCancelled, canInteract, ownsPointer, admissionIsCurrent,
                    interaction.hold()
                else { return }
                holdTask = nil
                publish()
            }
            return true
        }

        private func publish() {
            guard canInteract, ownsPointer, admissionIsCurrent,
                let snapshot = admission?.snapshot, !snapshot.options.isEmpty
            else {
                cancel()
                return
            }
            onEvent(
                .preview(
                    MonitorReadoutValue(
                        id: identity, sourceIdentity: sourceIdentity, snapshot: snapshot,
                        position: snapshot.position(translation: interaction.translation))))
        }

        private func cancel() {
            holdTask?.cancel()
            holdTask = nil
            interaction.cancel()
            if !touching { interaction = .init() }
            ownership.release(identity)
            admission = nil
            onEvent(.cancel(identity))
        }
    }
#endif
