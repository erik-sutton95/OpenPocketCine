import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenCineMedia
import SwiftUI

/// A native source adapter. Panel chrome, placement, plots and options belong to the shared owner.
private struct AppScopeOverlay: View {
    @Environment(AppModel.self) private var model
    let tool: MonitorAssistSelection
    let canvas: CGRect
    let feed: CGRect
    let chromeClearance: EdgeInsets
    var body: some View {
        MonitorScopeOverlay(tool: tool, assist: model.assist, stores: .app, haptics: .app,
            canvas: canvas, feed: feed, chromeClearance: chromeClearance,
            readBundle: { model.monitorSamples.displayBundle }, configureDisplay: scopeDisplay)
    }
}

struct WaveformOverlay: View {
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()
    var body: some View {
        AppScopeOverlay(tool: .waveform, canvas: canvas, feed: feed, chromeClearance: chromeClearance)
    }
}

struct ParadeOverlay: View {
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()
    var body: some View {
        AppScopeOverlay(tool: .parade, canvas: canvas, feed: feed, chromeClearance: chromeClearance)
    }
}

struct HistogramOverlay: View {
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()
    var body: some View {
        AppScopeOverlay(tool: .histogram, canvas: canvas, feed: feed, chromeClearance: chromeClearance)
    }
}

struct VectorscopeOverlay: View {
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()
    var body: some View {
        AppScopeOverlay(tool: .vectorscope, canvas: canvas, feed: feed, chromeClearance: chromeClearance)
    }
}

struct TrafficLightsOverlay: View {
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets
    var body: some View {
        AppScopeOverlay(tool: .trafficLights, canvas: bounds, feed: feed, chromeClearance: chromeClearance)
    }
}
