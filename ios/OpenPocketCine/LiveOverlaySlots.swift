import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorSystemCluster.settingsButton` (`MonitorUnified.swift` ~1098).
struct LiveSettingsButton: View {
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            LiveRailCircle(icon: .settings)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Open Operator Setup")
        .accessibilityIdentifier("monitor.system.settings")
    }
}

/// OpenZCine `MonitorSystemCluster.mediaButton` (`MonitorUnified.swift` ~1114).
struct LiveMediaButton: View {
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            LiveRailCircle(icon: .layers)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Open Media")
        .accessibilityIdentifier("monitor.system.media")
    }
}

/// Mimo's green (x) on the locked subject box.
struct LiveTrackingCancelButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.session.cancelSubjectTracking()
        } label: {
            OpcIcon.x
                .frame(width: 11, height: 11)
                .foregroundStyle(LiveDesign.background)
                .frame(
                    width: LiveTrackingChrome.cancelSize,
                    height: LiveTrackingChrome.cancelSize
                )
                .background(LiveDesign.good, in: Circle())
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Stop subject tracking")
        .accessibilityIdentifier("monitor.system.trackCancel")
    }
}

/// OpenZCine `dot.viewfinder` recenter — AF to centre and end tracking.
struct LiveFocusResetButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.session.resetFocusPoint()
        } label: {
            OpcIcon.crosshair
                .frame(width: 17, height: 17)
                .foregroundStyle(LiveDesign.text)
                .frame(
                    width: LiveChromeMetrics.focusResetSize,
                    height: LiveChromeMetrics.focusResetSize
                )
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Recenter focus")
        .accessibilityHint("Moves the focus box back to the center and ends subject tracking")
        .accessibilityIdentifier("monitor.system.focusReset")
    }
}

/// SET-relative yaw/pitch for the live debug rings.
struct HeadTrackAxisPose: Equatable {
    var yawDeg: Double
    var pitchDeg: Double
    var locked: Bool
}

/// Calibrate Head Lock starts tracking; STOP ends it.
struct LiveHeadTrackCalibrateButton: View {
    static let calibrateTitle = "Calibrate Head Lock"
    static let stopTitle = "STOP"

    var title: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(LiveType.ui(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(
            title == Self.stopTitle ? "Stop head tracking" : "Calibrate Head Lock"
        )
        .accessibilityHint(
            title == Self.stopTitle
                ? "Stops AirPods gimbal tracking" : "Sets the current heading as forward"
        )
        .accessibilityIdentifier("monitor.system.headTrackCalibrate")
    }
}

/// Rail circle with a Lucide glyph (no copyrighted rail assets, no SF Symbols).
private struct LiveRailCircle: View {
    let icon: OpcIcon

    var body: some View {
        let size = LiveChromeMetrics.auxiliaryButtonSize
        icon
            .frame(width: size * 0.36, height: size * 0.36)
            .foregroundStyle(LiveDesign.text.opacity(0.86))
            .frame(width: size, height: size)
            .liveChromeCircle()
    }
}
