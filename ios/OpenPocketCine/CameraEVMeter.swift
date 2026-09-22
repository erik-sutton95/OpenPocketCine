import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Fixed camera telemetry chrome. It has no assist state, gestures or pixel sampling.
enum CameraEVMeter {
    static func frame(in feed: CGRect, avoiding obstacle: CGRect? = nil) -> CGRect {
        guard feed.width >= 48, feed.height >= 60 else { return .zero }
        let x = feed.minX + 6
        var height = min(156, feed.height - 12)
        if let obstacle, obstacle.minX < x + 36, obstacle.maxX > x,
            obstacle.minY > feed.midY
        {
            // Preserve the center while leaving the collapsed assist controls clear.
            height = min(height, max(min(60, feed.height - 12), 2 * (obstacle.minY - feed.midY - 8)))
        }
        return CGRect(x: x, y: feed.midY - height / 2, width: 36, height: height)
    }
}

struct CameraEVMeterOverlay: View {
    @Environment(AppModel.self) private var model
    let feed: CGRect
    var avoiding: CGRect?

    var body: some View {
        let frame = CameraEVMeter.frame(in: feed, avoiding: avoiding)
        let reading = ExposureMeterReading(
            cameraValue: model.session.sessionRecovery.isRecovering || model.session.feedRecovering
                ? nil : model.session.status.meteredEv)
        MonitorExposureGauge(value: reading.label, needleFraction: reading.needleFraction)
            .frame(width: frame.width, height: frame.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EV meter")
            .accessibilityValue(reading.accessibilityValue)
            .accessibilityIdentifier("monitor.ev.meter")
            .position(x: frame.midX, y: frame.midY)
            .opacity(frame.isEmpty ? 0 : 1)
            .allowsHitTesting(false)
    }
}
