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
