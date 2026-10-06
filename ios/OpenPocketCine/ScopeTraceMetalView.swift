import MetalKit
import MonitorUI
import OpenCineAppKitApple

@MainActor
func scopeDisplay(_ view: MTKView) -> MonitorScopeDisplayOptions {
    LiveHDRDisplay.app.configure(view)
    return MonitorScopeDisplayOptions(
        hdr: LiveHDRDisplay.app.isEnabled, gain: LiveHDRDisplay.app.presentGain)
}
