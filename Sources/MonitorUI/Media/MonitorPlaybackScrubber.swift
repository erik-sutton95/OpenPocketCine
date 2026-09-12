#if os(iOS)
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
        @State private var isDragging = false

        public init(
            progress: Double, duration: Double, bufferedProgress: Double = 0,
            onScrubbingChanged: @escaping (Bool) -> Void,
            onProgressChange: @escaping (Double) -> Void, onSeek: @escaping (Double) -> Void
        ) {
            self.progress = progress
            self.duration = duration
            self.bufferedProgress = bufferedProgress
            self.onScrubbingChanged = onScrubbingChanged
            self.onProgressChange = onProgressChange
            self.onSeek = onSeek
        }

        private func fraction(_ seconds: Double) -> Double {
            guard duration.isFinite, duration > 0, seconds.isFinite else { return 0 }
            return min(1, max(0, seconds / duration))
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
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onScrubbingChanged(true)
                            }
                            onProgressChange(
                                seconds(at: value.location.x, width: geometry.size.width))
                        }
                        .onEnded { value in
                            onSeek(seconds(at: value.location.x, width: geometry.size.width))
                            isDragging = false
                            onScrubbingChanged(false)
                        })
            }
            .frame(height: 22)
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

        private func seconds(at x: CGFloat, width: CGFloat) -> Double {
            guard width > 0, duration.isFinite, duration > 0 else { return 0 }
            return Double(min(1, max(0, x / width))) * duration
        }
    }
#endif
