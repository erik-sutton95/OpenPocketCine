import OpenPocketViewCore
import SwiftUI
import WatchKit

/// Wrist monitor: timecode, 16:9 preview with a REC tally border, storage · Record ·
/// camera battery. All camera control stays on the iPhone.
struct WatchMonitorView: View {
    @Environment(WatchSessionController.self) private var controller
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var state: WatchRelayState? { controller.state }
    private var isRecording: Bool { state?.isRecording ?? false }
    private var isPhotography: Bool { state?.isPhotography ?? false }

    @State private var zoom: Double = 1
    @State private var pan: CGSize = .zero
    @State private var panAnchor: CGSize = .zero
    @State private var feedSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 2) {
            topBar
                .padding(.horizontal, 6)
            feed
                .frame(maxHeight: .infinity)
            bottomBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .onChange(of: isRecording) { _, nowRecording in
            guard !isLuminanceReduced else { return }
            WKInterfaceDevice.current().play(nowRecording ? .success : .failure)
        }
        .onChange(of: controller.commandMessage) { _, message in
            guard !isLuminanceReduced, message != nil else { return }
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private var topBar: some View {
        Text(timecodeLabel)
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(isRecording ? .red : .primary)
            .frame(maxWidth: .infinity)
    }

    private var timecodeLabel: String {
        let clock =
            state?.connection == .noCamera
            ? state?.timecode : controller.frameTimecode ?? state?.timecode
        if let clock, !clock.isEmpty { return clock }
        return "--:--:--"
    }

    private var feed: some View {
        Color.black
            .aspectRatio(state?.feedAspectRatio ?? (16.0 / 9.0), contentMode: .fit)
            .overlay {
                if let image = controller.feedImage {
                    GeometryReader { proxy in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(isLuminanceReduced ? 1 : zoom)
                            .offset(isLuminanceReduced ? .zero : clampedPan(in: proxy.size))
                            .onAppear { feedSize = proxy.size }
                            .onChange(of: proxy.size) { _, size in feedSize = size }
                    }
                }
            }
            .clipped()
            .overlay(overlay)
            .overlay {
                if isRecording {
                    Rectangle()
                        .strokeBorder(.red, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottom) {
                if let message = controller.commandMessage {
                    Text(message)
                        .font(.system(size: 9, weight: .medium))
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.90, green: 0.71, blue: 0.40))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 3)
                }
            }
            .frame(maxWidth: .infinity)
            .focusable()
            .digitalCrownRotation(
                $zoom,
                from: 1,
                through: Self.maximumZoom,
                by: 0.05,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard zoom > 1 else { return }
                        pan = CGSize(
                            width: panAnchor.width + value.translation.width,
                            height: panAnchor.height + value.translation.height)
                    }
                    .onEnded { _ in panAnchor = clampedPan(in: feedSize) }
            )
            .onChange(of: zoom) { _, level in
                if level <= 1 {
                    pan = .zero
                    panAnchor = .zero
                }
            }
    }

    private static let maximumZoom: Double = 4

    private func clampedPan(in size: CGSize) -> CGSize {
        let limitX = max(0, (size.width * zoom - size.width) / 2)
        let limitY = max(0, (size.height * zoom - size.height) / 2)
        return CGSize(
            width: min(max(pan.width, -limitX), limitX),
            height: min(max(pan.height, -limitY), limitY))
    }

    @ViewBuilder private var overlay: some View {
        if let copy = WatchMonitorPlaceholder.resolve(
            isReachable: controller.isReachable,
            state: state,
            hasFeed: controller.feedImage != nil
        ).copy {
            placeholder(copy)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .padding(6)
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Text(state?.media ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)
            captureControl
            HStack(spacing: 3) {
                Image(systemName: "camera")
                batteryGauge
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var canRecord: Bool {
        controller.isReachable && state?.connection == .connected && !controller.isSendingCommand
    }

    @ViewBuilder private var captureControl: some View {
        if isPhotography { shutterButton } else { recordButton }
    }

    private var shutterButton: some View {
        Button {
            WKInterfaceDevice.current().play(.success)
            controller.sendCapture()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.4)
        .accessibilityLabel("Shutter")
    }

    private var recordButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            controller.sendToggleRecord()
        } label: {
            ZStack {
                Circle()
                    .stroke(isRecording ? .red : .white.opacity(0.6), lineWidth: 3)
                    .frame(width: 34, height: 34)
                RoundedRectangle(cornerRadius: isRecording ? 3 : 11)
                    .fill(.red)
                    .frame(
                        width: isRecording ? 14 : 22,
                        height: isRecording ? 14 : 22)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.15), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private var filledBars: Int {
        let percent = state?.cameraBatteryPercent ?? -1
        guard percent >= 0 else { return 0 }
        if percent == 0 { return 0 }
        return min(5, max(1, Int((Double(min(100, percent)) / 20.0).rounded(.up))))
    }

    private var batteryTint: Color {
        let percent = state?.cameraBatteryPercent ?? -1
        if percent < 0 { return .white.opacity(0.22) }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return Color(red: 0.42, green: 0.80, blue: 0.53)
    }

    @ViewBuilder private var batteryGauge: some View {
        if let percent = state?.cameraBatteryPercent, percent >= 0 {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                        .fill(index < filledBars ? batteryTint : Color.white.opacity(0.22))
                        .frame(width: 2.5, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Camera battery \(percent) percent")
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
