import Metal
import MetalKit
import MonitorUI
import QuartzCore
import SwiftUI
import UIKit

/// Outdoor HDR panel boost for live view and Metal scopes.
///
/// The camera picture stays Rec.709 / log; this does not change COLOR or
/// recording. WAVE / HISTO still measure decoded codes. When enabled, the
/// Metal present path writes extended-linear values above SDR white so an
/// HDR phone can drive the extra nits the panel reserves for HDR content.
enum LiveHDRDisplay {
    /// Peak linear ratio versus SDR white. Clamped to the screen's potential.
    static let requestedHeadroom: CGFloat = 3
    /// Bake stays 8-bit display-referred. Only the drawable is float EDR.
    static let bakePixelFormat: MTLPixelFormat = .bgra8Unorm

    /// Operator Setup toggle. Present path reads ``isEnabled``.
    nonisolated(unsafe) static var preferredEnabled = false
    /// Screen recording, AirPlay, or mirroring — SDR so the file is not HDR-boosted.
    nonisolated(unsafe) static var screenCaptured = false
    /// Effective: preferred and not captured. Feed, scopes and chrome read this.
    nonisolated(unsafe) static var isEnabled = false
    nonisolated(unsafe) static var presentGain: Float = 1
    nonisolated(unsafe) static var chromeActive = false

    static var chromeGain: Float { isEnabled ? presentGain : 1 }

    static func isEffective(preferred: Bool, screenCaptured: Bool) -> Bool {
        preferred && !screenCaptured
    }

    static func drawablePixelFormat(enabled: Bool = isEnabled) -> MTLPixelFormat {
        enabled ? .rgba16Float : .bgra8Unorm
    }

    /// `potentialHeadroom` is `UIScreen.potentialEDRHeadroom` (1 on SDR panels).
    static func displayGain(enabled: Bool, potentialHeadroom: CGFloat) -> Float {
        guard enabled else { return 1 }
        let cap = potentialHeadroom.isFinite ? max(potentialHeadroom, 1) : 1
        return Float(min(requestedHeadroom, cap))
    }

    static func setEnabled(_ enabled: Bool, screen: UIScreen? = UIScreen.main) {
        preferredEnabled = enabled
        apply(screen: screen)
    }

    static func setScreenCaptured(_ captured: Bool, screen: UIScreen? = UIScreen.main) {
        screenCaptured = captured
        apply(screen: screen)
    }

    static func setChromeActive(_ active: Bool) {
        chromeActive = active && isEnabled
        MonitorTheme.hdrGain = CGFloat(chromeGain)
    }

    private static func apply(screen: UIScreen?) {
        isEnabled = isEffective(preferred: preferredEnabled, screenCaptured: screenCaptured)
        chromeActive = isEnabled
        refreshGain(screen: screen)
        MonitorTheme.hdrGain = CGFloat(chromeGain)
    }

    static func chromeColor(
        red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1
    ) -> Color {
        MonitorTheme.edrSRGB(
            red: red, green: green, blue: blue, gain: CGFloat(chromeGain), alpha: alpha)
    }

    static func chromeColor(hex: UInt32, alpha: CGFloat = 1) -> Color {
        chromeColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
    }

    static func refreshGain(screen: UIScreen?) {
        presentGain = displayGain(
            enabled: isEnabled, potentialHeadroom: screen?.potentialEDRHeadroom ?? 1)
    }

    static func configure(_ layer: CAMetalLayer, screen: UIScreen? = nil) {
        refreshGain(screen: screen ?? UIScreen.main)
        let enabled = isEnabled
        let format = drawablePixelFormat(enabled: enabled)
        if layer.pixelFormat != format {
            layer.pixelFormat = format
        }
        // Runs on every feed present: write only changes so a steady layer stays clean.
        if layer.wantsExtendedDynamicRangeContent != enabled {
            layer.wantsExtendedDynamicRangeContent = enabled
        }
        let colorspaceName = enabled ? CGColorSpace.extendedLinearDisplayP3 : nil
        if layer.colorspace?.name != colorspaceName {
            layer.colorspace = colorspaceName.flatMap { CGColorSpace(name: $0) }
        }
        if #available(iOS 26.0, *) {
            let range: CALayer.DynamicRange = enabled ? .high : .automatic
            if layer.preferredDynamicRange != range {
                layer.preferredDynamicRange = range
            }
        }
    }

    static func configure(_ view: MTKView, screen: UIScreen? = nil) {
        let enabled = isEnabled
        let format = drawablePixelFormat(enabled: enabled)
        if view.colorPixelFormat != format {
            view.colorPixelFormat = format
        }
        if let layer = view.layer as? CAMetalLayer {
            configure(layer, screen: screen ?? view.window?.screen)
        }
    }

    static func configure(_ layer: CALayer, screen: UIScreen? = nil, enabled: Bool? = nil) {
        refreshGain(screen: screen ?? UIScreen.main)
        let on = enabled ?? isEnabled
        layer.wantsExtendedDynamicRangeContent = on
        if #available(iOS 26.0, *) {
            layer.preferredDynamicRange = on ? .high : .automatic
        }
    }
}

/// Enables EDR on the live window so SwiftUI HUD labels can exceed SDR white.
struct HDRChromeHost: UIViewRepresentable {
    var enabled: Bool

    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.enabled = enabled
        uiView.apply()
    }

    final class Probe: UIView {
        var enabled = false
        private weak var trackedWindow: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            let on = enabled && window != nil
            LiveHDRDisplay.setChromeActive(on)
            if let previous = trackedWindow, previous !== window {
                LiveHDRDisplay.configure(previous.layer, screen: previous.screen, enabled: false)
            }
            trackedWindow = window
            if let window {
                LiveHDRDisplay.configure(window.layer, screen: window.screen, enabled: on)
            }
        }
    }
}
