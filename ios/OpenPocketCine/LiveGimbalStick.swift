import CoreImage
import OpenPocketViewCore
import SwiftUI

/// On-feed analog stick. Streams `0x04/0x01` while held, center on lift.
/// Light chrome on a dark picture, dark chrome on a bright picture.
struct LiveGimbalStick: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    var enabled: Bool
    var feed: CGRect
    var frame: CGRect
    @State private var knobOffset: CGSize = .zero
    @State private var dragging = false
    @State private var contact = false
    @State private var darkChrome = false
    @State private var taps = GimbalStick.TapSequence()
    @State private var pendingDouble: Task<Void, Never>?
    @State private var pressTick = 0
    @State private var recenterTick = 0
    @State private var flipTick = 0

    private var size: CGFloat { LiveChromeMetrics.gimbalStickSize }
    private var knob: CGFloat { LiveChromeMetrics.gimbalKnobSize }
    private var travel: CGFloat { (size - knob) / 2 }
    private var opacity: CGFloat { LiveChromeMetrics.gimbalStickOpacity }
    private var interactive: Bool { enabled && !interfaceLocked }
    private var ink: Color { darkChrome ? .black : LiveDesign.text }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ink.opacity(opacity), lineWidth: 2)
            Circle()
                .fill(ink.opacity(opacity))
                .frame(width: knob, height: knob)
                .offset(knobOffset)
        }
        .animation(.easeInOut(duration: 0.2), value: darkChrome)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(drag, including: interactive ? .gesture : .none)
        .allowsHitTesting(interactive)
        .sensoryFeedback(.impact(weight: .light), trigger: pressTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: recenterTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: flipTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gimbal stick")
        .accessibilityHint("Drag to move the gimbal. Double-tap to recenter. Triple-tap to flip.")
        .accessibilityIdentifier("monitor.system.gimbal")
        .task(id: "\(Int(frame.minX))x\(Int(frame.minY))") {
            while !Task.isCancelled {
                refreshChrome()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        .onDisappear {
            cancelTaps()
            contact = false
            model.session.endGimbalStick()
        }
        .onChange(of: interfaceLocked) { _, locked in
            if locked {
                contact = false
                cancelTaps()
                release()
            }
        }
        .onChange(of: enabled) { _, on in
            if !on {
                contact = false
                cancelTaps()
                release()
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !contact {
                    contact = true
                    hapticPress()
                }
                let limited = clamp(value.translation)
                let mag =
                    hypot(Double(limited.width), Double(limited.height))
                    / Double(max(travel, 1))
                if !GimbalStick.isTap(normalizedMagnitude: mag) {
                    cancelTaps()
                    dragging = true
                    knobOffset = limited
                    let nx = Double(limited.width / max(travel, 1))
                    let ny = Double(-limited.height / max(travel, 1))
                    model.session.updateGimbalStick(
                        x: nx, y: ny, sensitivity: model.gimbalStickSensitivity,
                        assistMirror: model.assist.isVisible(.mirror))
                }
            }
            .onEnded { _ in
                contact = false
                if dragging {
                    cancelTaps()
                    release()
                    return
                }
                handleTap()
                knobOffset = .zero
            }
    }

    private func handleTap() {
        switch taps.tap(at: Date().timeIntervalSinceReferenceDate) {
        case .first:
            break
        case .second:
            pendingDouble?.cancel()
            pendingDouble = Task { @MainActor in
                let ns = UInt64(GimbalStick.doubleTapWindow * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                if taps.commitDouble() {
                    hapticRecenter()
                    model.session.recenterGimbal()
                }
            }
        case .third:
            pendingDouble?.cancel()
            pendingDouble = nil
            hapticFlip()
            model.session.flipGimbal()
        }
    }

    private func refreshChrome() {
        guard
            let region = GimbalStick.chromeSampleRegion(
                stick: MonitorLayoutRegion(
                    x: Double(frame.minX), y: Double(frame.minY),
                    width: Double(frame.width), height: Double(frame.height)),
                feed: MonitorLayoutRegion(
                    x: Double(feed.minX), y: Double(feed.minY),
                    width: Double(feed.width), height: Double(feed.height)))
        else {
            darkChrome = false
            return
        }
        let luma = GimbalStickLumaTap.meanLuma(
            buffer: model.frameSamples.sourcePixelBuffer,
            normalized: CGRect(
                x: region.x, y: region.y, width: region.width, height: region.height))
        darkChrome = GimbalStick.prefersDarkChrome(luma: luma, previous: darkChrome)
    }

    private func hapticPress() {
        guard model.hapticsEnabled else { return }
        pressTick += 1
    }

    private func hapticRecenter() {
        guard model.hapticsEnabled else { return }
        recenterTick += 1
    }

    private func hapticFlip() {
        guard model.hapticsEnabled else { return }
        flipTick += 1
    }

    private func cancelTaps() {
        pendingDouble?.cancel()
        pendingDouble = nil
        taps.reset()
    }

    private func release() {
        dragging = false
        knobOffset = .zero
        model.session.endGimbalStick()
    }

    private func clamp(_ raw: CGSize) -> CGSize {
        let mag = hypot(raw.width, raw.height)
        guard mag > travel, mag > 0 else { return raw }
        return CGSize(width: raw.width / mag * travel, height: raw.height / mag * travel)
    }
}

/// 1×1 `CIAreaAverage` of the decoded frame under the stick.
enum GimbalStickLumaTap {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func meanLuma(buffer: CVPixelBuffer?, normalized: CGRect) -> Double? {
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        guard extent.width > 2, extent.height > 2 else { return nil }
        let sample = CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + (1 - normalized.maxY) * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        ).intersection(extent)
        guard sample.width > 1, sample.height > 1 else { return nil }
        let average = image.cropped(to: sample).applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: sample)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2]))
            / 255
    }
}
