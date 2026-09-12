import Foundation

/// Features offered by a connected backend. Shared screens depend on these
/// capabilities, never on a manufacturer or protocol enum.
public struct MonitorCapabilities: Equatable, Sendable {
    public var gimbal: Bool
    public var zoom: Bool
    public var focus: Bool
    public var iris: Bool
    public var audio: Bool
    public var headTracking: Bool
    public var clipDelete: Bool
    public var clipStar: Bool
    public var requiresInternetHop: Bool

    public init(
        gimbal: Bool = false, zoom: Bool = false, focus: Bool = false,
        iris: Bool = false, audio: Bool = false, headTracking: Bool = false,
        clipDelete: Bool = false, clipStar: Bool = false,
        requiresInternetHop: Bool = false
    ) {
        self.gimbal = gimbal
        self.zoom = zoom
        self.focus = focus
        self.iris = iris
        self.audio = audio
        self.headTracking = headTracking
        self.clipDelete = clipDelete
        self.clipStar = clipStar
        self.requiresInternetHop = requiresInternetHop
    }
}
