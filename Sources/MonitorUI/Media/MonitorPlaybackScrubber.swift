#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Shared transport track. Seeking cadence and playback-resume decisions belong
    /// to the host; this view translates a drag into elapsed seconds only.
    public struct MonitorPlaybackScrubber: View {
        private let progress: Double
        private let duration: Double
        private let bufferedProgress: Double
        private let onScrubbingChanged: (Bool) -> Void
        private let onProgressChange: (Double) -> Void
        private let onSeek: (Double) -> Void
        private let onCancelled: (MonitorEditingCancellation) -> Void
        private let interactionIdentity: () -> AnyHashable
        @State private var editing = MonitorEditingSession()
        @State private var admittedContext: Context?
        @GestureState private var pointerActive = false
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.monitorWindowGeometry) private var windowGeometry

        public init(
            progress: Double, duration: Double, bufferedProgress: Double = 0,
            interactionIdentity: @escaping () -> AnyHashable = { 0 },
            onScrubbingChanged: @escaping (Bool) -> Void,
            onProgressChange: @escaping (Double) -> Void, onSeek: @escaping (Double) -> Void,
            onCancelled: @escaping (MonitorEditingCancellation) -> Void = { _ in }
        ) {
            self.progress = progress
            self.duration = duration
            self.bufferedProgress = bufferedProgress
            self.interactionIdentity = interactionIdentity
            self.onScrubbingChanged = onScrubbingChanged
            self.onProgressChange = onProgressChange
            self.onSeek = onSeek
            self.onCancelled = onCancelled
        }

        private func fraction(_ seconds: Double) -> Double {
            guard duration.isFinite, duration > 0, seconds.isFinite else { return 0 }
            return min(1, max(0, seconds / duration))
        }

        private struct Context: Equatable {
            let source: AnyHashable
            let duration: Double
            let window: MonitorWindowGeometry
        }

        private var context: Context {
            Context(source: interactionIdentity(), duration: duration, window: windowGeometry)
        }

        private var cancellationReason: MonitorEditingCancellation {
            guard let admittedContext, scenePhase == .active,
                admittedContext.source == interactionIdentity(),
                admittedContext.duration == duration
            else { return .contextChanged }
            // A resize interrupts a gesture on the same clip. It must not be
            // classified as a source replacement based on callback ordering.
            return .interrupted
        }

        public var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                    Capsule().fill(.white.opacity(0.3))
                        .frame(width: geometry.size.width * fraction(bufferedProgress), height: 4)
                    Capsule().fill(MonitorTheme.accent)
                        .frame(width: geometry.size.width * fraction(progress), height: 4)
                    Circle().fill(.white).frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .offset(x: max(0, geometry.size.width * fraction(progress) - 6.5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($pointerActive) { _, active, _ in active = true }
                        .onChanged { value in
                            if editing.begin() {
                                admittedContext = context
                                onScrubbingChanged(true)
                            }
                            guard admittedContext == context, scenePhase == .active else {
                                cancelEditing(cancellationReason)
                                return
                            }
                            guard editing.isEditing else { return }
                            onProgressChange(
                                seconds(at: value.location.x, width: geometry.size.width))
                        }
                        .onEnded { value in
                            guard admittedContext == context, scenePhase == .active else {
                                cancelEditing(cancellationReason)
                                _ = editing.end()
                                return
                            }
                            guard editing.end() else { return }
                            admittedContext = nil
                            onSeek(seconds(at: value.location.x, width: geometry.size.width))
                            onScrubbingChanged(false)
                        }
                )
                .onChange(of: geometry.size) { _, _ in cancelEditing(cancellationReason) }
            }
            .frame(height: 22)
            .onChange(of: pointerActive) { _, active in
                if !active, editing.end() {
                    let reason = cancellationReason
                    admittedContext = nil
                    onScrubbingChanged(false)
                    onCancelled(reason)
                }
            }
            .onChange(of: interactionIdentity()) { _, _ in cancelEditing(.contextChanged) }
            .onChange(of: duration) { _, _ in cancelEditing(.contextChanged) }
            .onChange(of: windowGeometry) { _, _ in cancelEditing(cancellationReason) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelEditing(.contextChanged) }
            }
            .onDisappear { cancelEditing(.disappeared) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(progress.isFinite ? max(0, progress) : 0)) seconds")
            .accessibilityAdjustableAction { direction in
                let target = min(duration, max(0, progress + (direction == .increment ? 1 : -1)))
                if target.isFinite {
                    onScrubbingChanged(true)
                    onSeek(target)
                    onScrubbingChanged(false)
                }
            }
        }

        private func cancelEditing(_ reason: MonitorEditingCancellation) {
            if editing.cancel(pointerIsActive: pointerActive) {
                admittedContext = nil
                onScrubbingChanged(false)
                onCancelled(reason)
            }
        }

        private func seconds(at x: CGFloat, width: CGFloat) -> Double {
            guard width > 0, duration.isFinite, duration > 0 else { return 0 }
            return Double(min(1, max(0, x / width))) * duration
        }
    }
#endif
