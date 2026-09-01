import OpenPocketViewCore
import SwiftUI

/// Two SET-relative rings so an operator can see AirPods and gimbal 1:1.
/// Yaw: 12 o'clock is forward. Pitch: arrow-right is 0, nod is up/down.
/// White arrow is the head; sky arrow is live `0x04/0x05`.
struct LiveHeadTrackAxisDials: View {
    var pose: HeadTrackAxisPose

    private let dialSize: CGFloat = 76

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            dial(
                title: "YAW",
                lookDeg: pose.yawDeg,
                rotationDeg: HeadTrack.yawDialDeg(lookRightDeg: pose.yawDeg),
                gimbalDeg: pose.gimbalYawDeg,
                gimbalRotationDeg: pose.gimbalYawDeg.map(HeadTrack.yawDialDeg(lookRightDeg:)),
                forward: .up)
            dial(
                title: "PITCH",
                lookDeg: pose.pitchDeg,
                rotationDeg: HeadTrack.pitchDialDeg(lookUpDeg: pose.pitchDeg),
                gimbalDeg: pose.gimbalPitchDeg,
                gimbalRotationDeg: pose.gimbalPitchDeg.map(HeadTrack.pitchDialDeg(lookUpDeg:)),
                forward: .right)
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                legendSwatch(LiveDesign.text, "HEAD")
                if pose.gimbalYawDeg != nil || pose.gimbalPitchDeg != nil {
                    legendSwatch(LiveDesign.accent, "GIMBAL")
                }
            }
            .padding(.top, 6)
            .padding(.leading, 10)
        }
        .overlay(alignment: .topTrailing) {
            Text(pose.locked ? "SET" : "IMU")
                .font(LiveType.ui(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(LiveDesign.text.opacity(0.72))
                .padding(.top, 6)
                .padding(.trailing, 10)
        }
        .liveChromeCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("monitor.system.headTrackAxisDials")
    }

    private var accessibilityText: String {
        var text =
            "Head yaw \(Int(pose.yawDeg.rounded())) degrees, pitch \(Int(pose.pitchDeg.rounded())) degrees"
        if let gy = pose.gimbalYawDeg, let gp = pose.gimbalPitchDeg {
            text +=
                ", gimbal yaw \(Int(gy.rounded())) degrees, pitch \(Int(gp.rounded())) degrees"
        }
        return text
    }

    private enum Forward {
        case up
        case right
    }

    private func dial(
        title: String, lookDeg: Double, rotationDeg: Double,
        gimbalDeg: Double?, gimbalRotationDeg: Double?, forward: Forward
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(LiveType.ui(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LiveDesign.text.opacity(0.78))
            ZStack {
                Circle()
                    .strokeBorder(LiveDesign.hairline, lineWidth: 1.5)
                if forward == .right {
                    Rectangle()
                        .fill(LiveDesign.text.opacity(0.22))
                        .frame(width: dialSize - 10, height: 1)
                }
                cardinalTicks
                forwardMark(forward)
                if let gimbalRotationDeg {
                    LiveHeadTrackForwardArrow()
                        .fill(LiveDesign.accent)
                        .frame(width: 22, height: dialSize * 0.62)
                        .rotationEffect(.degrees(gimbalRotationDeg))
                }
                LiveHeadTrackForwardArrow()
                    .fill(LiveDesign.text)
                    .frame(width: 16, height: dialSize * 0.50)
                    .rotationEffect(.degrees(rotationDeg))
            }
            .frame(width: dialSize, height: dialSize)
            VStack(spacing: 0) {
                Text(String(format: "%+.0f°", lookDeg))
                    .foregroundStyle(LiveDesign.text.opacity(0.9))
                if let gimbalDeg {
                    Text(String(format: "%+.0f°", gimbalDeg))
                        .foregroundStyle(LiveDesign.accent)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 8, height: 3)
            Text(title)
                .font(LiveType.ui(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(color.opacity(0.86))
        }
    }

    private func forwardMark(_ forward: Forward) -> some View {
        Capsule()
            .fill(LiveDesign.text)
            .frame(
                width: forward == .right ? 9 : 2.5,
                height: forward == .right ? 2.5 : 9
            )
            .offset(
                x: forward == .right ? (dialSize / 2) - 8 : 0,
                y: forward == .up ? -(dialSize / 2) + 8 : 0)
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
