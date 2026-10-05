import MetalKit
import MonitorUI

@MainActor
func scopeDisplay(_ view: MTKView) -> MonitorScopeDisplayOptions {
    LiveHDRDisplay.configure(view)
    return MonitorScopeDisplayOptions(
        hdr: LiveHDRDisplay.isEnabled, gain: LiveHDRDisplay.presentGain)
}
