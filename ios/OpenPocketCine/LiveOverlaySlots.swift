import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorSystemCluster.settingsButton` (`MonitorUnified.swift` ~1098).
struct LiveSettingsButton: View {
    @Environment(\.interfaceLocked) private var locked
    var size: CGFloat = LiveChromeMetrics.auxiliaryButtonSize
    var onOpen: () -> Void

    var body: some View {
        MonitorChromeButton(
            "Open Operator Setup", size: CGSize(width: size, height: size), action: onOpen
        ) {
            OpcIcon.settings.frame(width: size * 29 / 54, height: size * 29 / 54)
        }
        .disabled(locked)
        .accessibilityLabel("Open Operator Setup")
        .accessibilityIdentifier("monitor.system.settings")
    }
}

/// OpenZCine `MonitorSystemCluster.mediaButton` (`MonitorUnified.swift` ~1114).
struct LiveMediaButton: View {
    @Environment(\.interfaceLocked) private var locked
    var size: CGFloat = LiveChromeMetrics.auxiliaryButtonSize
    var onOpen: () -> Void

    var body: some View {
        MonitorChromeButton("Open Media", size: CGSize(width: size, height: size), action: onOpen) {
            OpcIcon.film.frame(width: size * 29 / 54, height: size * 29 / 54)
        }
        .disabled(locked)
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

/// SET-relative yaw/pitch for the live debug rings (head + gimbal).
struct HeadTrackAxisPose: Equatable {
    var yawDeg: Double
    var pitchDeg: Double
    var gimbalYawDeg: Double?
    var gimbalPitchDeg: Double?
    var locked: Bool
}

/// Compass Head Lock starts tracking; the same control becomes STOP.
struct LiveHeadTrackCalibrateButton: View {
    static let calibrateTitle = "Calibrate Head Lock"
    static let stopTitle = "STOP"

    var title: String
    var onTap: () -> Void

    private var isStop: Bool { title == Self.stopTitle }
    private var size: CGFloat { LiveChromeMetrics.zoomButtonSize }

    var body: some View {
        Button(action: onTap) {
            OpcIcon.compass
                .frame(width: 18, height: 18)
                .foregroundStyle(isStop ? LiveDesign.background : LiveDesign.text)
                .frame(width: size, height: size)
                .background { plateFill }
                .overlay { plateStroke }
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(isStop ? "Stop head tracking" : "Calibrate Head Lock")
        .accessibilityHint(
            isStop
                ? "Stops AirPods gimbal tracking" : "Sets the current heading as forward"
        )
        .accessibilityIdentifier("monitor.system.headTrackCalibrate")
    }

    @ViewBuilder private var plateFill: some View {
        if isStop {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LiveDesign.accent)
        } else {
            Circle().fill(.black.opacity(0.55))
        }
    }

    @ViewBuilder private var plateStroke: some View {
        if isStop {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LiveDesign.hairline, lineWidth: 1)
        } else {
            Circle().strokeBorder(LiveDesign.hairline, lineWidth: 1)
        }
    }
}
