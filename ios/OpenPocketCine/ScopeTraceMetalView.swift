import MetalKit
import MonitorUI

// Original geometry assertions now exercise the same owner used by the shipping plots.
typealias ScopeTraceMetal = MonitorScopeTraceMetal

@MainActor
func scopeDisplay(_ view: MTKView) -> MonitorScopeDisplayOptions {
    LiveHDRDisplay.configure(view)
    return MonitorScopeDisplayOptions(
        hdr: LiveHDRDisplay.isEnabled, gain: LiveHDRDisplay.presentGain)
}
