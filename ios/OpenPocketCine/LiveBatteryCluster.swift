import SwiftUI
import UIKit

/// OpenZCine `BatteryGaugeStack` / `BatteryIndicator` `.pillRow`.
/// Two identical battery pills (phone + camera). Charge tint is traffic-light
/// (`CameraBatteryGauge.Urgency`): green ≥41, yellow 21–40, red ≤20.
struct LiveBatteryCluster: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LiveBatteryRow(
                percent: phonePercent,
                deviceIcon: .smartphone,
                isCharging: phoneCharging,
                isCamera: false
            )
            LiveBatteryRow(
                percent: cameraPercent,
                deviceIcon: .camera,
                isCharging: model.session.status.charging,
                isCamera: true
            )
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phone and camera batteries")
    }

    private var phonePercent: Int {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return -1 }
        return Int((level * 100).rounded())
    }

    /// Only the 0x0D/0x02 percent. Never temperature or millivolts.
    private var cameraPercent: Int {
        let p = model.session.status.batteryPercent
        return (0...100).contains(p) ? p : -1
    }

    private var phoneCharging: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: true
        default: false
        }
    }
}

/// One compact gauge row: device icon beside a battery-shaped outline with the number inside.
private struct LiveBatteryRow: View {
    let percent: Int
    let deviceIcon: OpcIcon
    var isCharging: Bool
    var isCamera: Bool

    var body: some View {
        HStack(spacing: 5) {
            deviceIcon
                .foregroundStyle(LiveDesign.muted)
                .frame(width: 10, height: 10)
            HStack(spacing: 1) {
                if isCharging {
                    OpcIcon.zap
                        .frame(width: 7, height: 7)
                        .foregroundStyle(batteryTint)
                }
                Text(readout)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(batteryTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(width: 26, height: 15)
            .overlay {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(batteryTint.opacity(0.85), lineWidth: 1.2)
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(batteryTint.opacity(0.85))
                    .frame(width: 1.6, height: 6)
                    .offset(x: 3)
            }
        }
        .accessibilityLabel(isCamera ? "Camera battery" : "iPhone battery")
        .accessibilityValue(readout)
    }

    private var readout: String {
        percent >= 0 ? "\(percent)" : "—"
    }

    /// OpenZCine `CameraBatteryGauge.Urgency` on a 0–100 percent (ceil(p/20) bars):
    /// 3+ bars (≥41) nominal green, 2 bars (21–40) warning yellow, 1 bar (≤20) red.
    private var batteryTint: Color {
        if percent < 0 { return LiveDesign.faint }
        if percent <= 20 { return .red }
        if percent <= 40 { return .yellow }
        return LiveDesign.good
    }
}
