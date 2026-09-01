import OpenPocketViewCore
import SwiftUI

/// Two SET-relative rings so an operator can see AirPods yaw and pitch 1:1.
/// 12 o'clock is forward. The arrow is the nose.
struct LiveHeadTrackAxisDials: View {
    var pose: HeadTrackAxisPose

    private let dialSize: CGFloat = 76

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            dial(title: "YAW", degrees: pose.yawDeg)
            dial(title: "PITCH", degrees: pose.pitchDeg)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .topTrailing) {
            Text(pose.locked ? "SET" : "IMU")
                .font(LiveType.ui(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(LiveDesign.text.opacity(0.72))
                .padding(.top, 6)
                .padding(.trailing, 10)
        }
        .liveChromeCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Head yaw \(Int(pose.yawDeg.rounded())) degrees, pitch \(Int(pose.pitchDeg.rounded())) degrees"
        )
        .accessibilityIdentifier("monitor.system.headTrackAxisDials")
    }

    private func dial(title: String, degrees: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(LiveType.ui(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LiveDesign.text.opacity(0.78))
            ZStack {
                Circle()
                    .strokeBorder(LiveDesign.hairline, lineWidth: 1.5)
                cardinalTicks
                // Fixed forward mark at 12 o'clock.
                Capsule()
                    .fill(LiveDesign.text)
                    .frame(width: 2.5, height: 9)
                    .offset(y: -(dialSize / 2) + 8)
                LiveHeadTrackForwardArrow()
                    .fill(LiveDesign.text)
                    .frame(width: 22, height: dialSize * 0.62)
                    .rotationEffect(.degrees(degrees))
                Text(String(format: "%+.0f°", degrees))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.9))
                    .offset(y: dialSize * 0.28)
            }
            .frame(width: dialSize, height: dialSize)
        }
    }

    private var cardinalTicks: some View {
        ForEach(0..<4, id: \.self) { i in
            Capsule()
                .fill(LiveDesign.text.opacity(0.35))
                .frame(width: 1.5, height: 6)
                .offset(y: -(dialSize / 2) + 6)
                .rotationEffect(.degrees(Double(i) * 90))
        }
    }
}

/// Nose / forward. Drawn pointing up (12 o'clock) and rotated by the dial.
private struct LiveHeadTrackForwardArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let tipY = rect.minY
        let baseY = rect.minY + rect.height * 0.42
        let half = rect.width * 0.42
        path.move(to: CGPoint(x: midX, y: tipY))
        path.addLine(to: CGPoint(x: midX - half, y: baseY))
        path.addLine(to: CGPoint(x: midX + half, y: baseY))
        path.closeSubpath()
        let shaftW = max(2.5, rect.width * 0.14)
        path.addRect(
            CGRect(
                x: midX - shaftW / 2, y: baseY - 1, width: shaftW,
                height: rect.maxY - baseY - 4))
        return path
    }
}
