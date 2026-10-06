import MonitorUI
import SwiftUI

/// OpenZCine `MonitorSystemCluster.lockButton` (`MonitorUnified.swift` ~1068).
struct LiveLockButton: View {
    @Binding var locked: Bool
    var size: CGFloat = LiveChromeMetrics.lockButtonSize

    var body: some View {
        MonitorChromeButton(
            locked ? "Unlock monitor controls" : "Lock monitor controls",
            size: CGSize(width: size, height: size), active: locked
        ) {
            locked.toggle()
        } label: {
            // Lucide's lock extends farther vertically than the reference
            // glyph; compensate optically without shrinking the 54pt tile.
            MonitorIcon.lock
                .frame(width: size * 26 / 54, height: size * 26 / 54)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: locked)
        .accessibilityLabel(locked ? "Unlock monitor controls" : "Lock monitor controls")
        .accessibilityHint("Prevents accidental camera and View Assist changes")
        .accessibilityIdentifier("monitor.system.lock")
    }
}
