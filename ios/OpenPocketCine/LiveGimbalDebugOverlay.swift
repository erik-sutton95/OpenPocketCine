import OpenPocketViewCore
import SwiftUI

/// TT180 / yaw / Selfie Flip readout plus L/R invert forces.
struct LiveGimbalDebugState: Equatable {
    var commanded180 = false
    var rotated180 = false
    var yawDegrees: Double?
    var face = "unknown"
    var pending = 0
    var autoInvert = false
    var appliedInvert = false
    var selfieFlip = false
    var lastFlipReplyAt: Date?
    var lastFlipSendAt: Date?
    var autoMirror = false
    var appliedMirror = false
}

struct LiveGimbalDebugOverlay: View {
    @Environment(AppModel.self) private var model
    var feed: CGRect

    var body: some View {
        Group {
            if model.session.showsGimbalDebugOverlay {
                plate
            } else {
                restoreChip
            }
        }
        .offset(x: feed.minX + 8, y: feed.minY + 8)
        .zIndex(6)
        .allowsHitTesting(true)
    }

    private var restoreChip: some View {
        Button {
            model.session.showsGimbalDebugOverlay = true
        } label: {
            Text("DBG")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LiveDesign.muted)
                .frame(width: 40, height: 22)
                .background(
                    Color.black.opacity(0.62),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var plate: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            plateBody(now: context.date)
        }
    }

    private func plateBody(now: Date) -> some View {
        let state = model.session.gimbalDebugState
        let slot = GimbalStickDebugSlot.current(commanded180: state.commanded180)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("GIMBAL DEBUG")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.muted)
                Spacer(minLength: 8)
                Button {
                    model.session.showsGimbalDebugOverlay = false
                } label: {
                    Text("HIDE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                        .frame(width: 40, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
            }
            Text(statusLine(state, slot: slot, now: now))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(LiveDesign.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("         invert")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiveDesign.muted)
            }
            ForEach(GimbalStickDebugSlot.allCases, id: \.self) { row in
                HStack(spacing: 8) {
                    Text(row == slot ? "▶" : " ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                        .frame(width: 10)
                    Text(row.title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(row == slot ? LiveDesign.text : LiveDesign.muted)
                        .frame(width: 78, alignment: .leading)
                    forceButton(model.session.gimbalStickDebug[row].invert) {
                        model.session.cycleGimbalDebugInvert(slot: row)
                    }
                }
            }
            Text("tap A→ON→OFF  applies in that pose")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(LiveDesign.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: 276, alignment: .leading)
        .background(
            Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusLine(_ state: LiveGimbalDebugState, slot: GimbalStickDebugSlot, now: Date)
        -> String
    {
        let yaw: String
        if let deg = state.yawDegrees {
            yaw = String(format: "%+.0f°", deg)
        } else {
            yaw = "—"
        }
        let get: String
        let wall = Date()
        let rx = Self.ageLabel(state.lastFlipReplyAt, now: wall)
        let tx = Self.ageLabel(state.lastFlipSendAt, now: wall)
        get = "rx \(rx) tx \(tx)"
        return """
            TT180 \(state.commanded180 ? "ON " : "off")  yaw180 \(state.rotated180 ? "ON " : "off")
            face \(state.face)  yaw \(yaw)  pend \(state.pending)
            Flip \(state.selfieFlip ? "ON " : "off")  (\(get))
            now  mirror \(state.appliedMirror ? "ON" : "off")  invert \(state.appliedInvert ? "ON" : "off")  (\(slot.title))
            auto mirror \(state.autoMirror ? "ON" : "off")  invert \(state.autoInvert ? "ON" : "off")
            extra-mirror = TT180 && Flip off
            """
    }

    private static func ageLabel(_ at: Date?, now: Date) -> String {
        guard let at else { return "—" }
        let age = max(0, now.timeIntervalSince(at))
        return age < 2.5 ? String(format: "%.1fs", age) : "stale"
    }

    private func forceButton(_ force: GimbalStickForce, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(force.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(force == .auto ? LiveDesign.muted : LiveDesign.text)
                .frame(width: 36, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            force == .auto ? Color.white.opacity(0.08) : Color.white.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }
}
