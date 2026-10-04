import Foundation
import OpenCineMedia

/// Compatibility source name; the shared Media owner holds the conform policy and goldens.
public typealias ConformPreview = OpenCineMedia.MonitorConformPreview

/// Decision for a tap on the letterboxed playback frame.
public enum PlaybackFrameTap: Equatable, Sendable {
    case restartPlayback
    case toggleTransport
    case ignore

    public static func action(chromeVisible: Bool, reachedEnd: Bool) -> PlaybackFrameTap {
        _ = chromeVisible
        if reachedEnd { return .restartPlayback }
        return .toggleTransport
    }
}

/// Letterbox the video raster in a container; OpenZCine `aspectFitRect`.
public enum PlaybackVideoLayout {
    public static func aspectFitRect(videoSize: CGSize, in container: CGRect) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, container.width > 0, container.height > 0
        else { return container }
        let scale = min(container.width / videoSize.width, container.height / videoSize.height)
        let width = videoSize.width * scale
        let height = videoSize.height * scale
        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height)
    }

    /// Parse a camera-listed `3840x2160` (or `3840×2160`) into a raster size.
    public static func size(fromResolution listed: String?) -> CGSize? {
        guard let listed else { return nil }
        let parts = listed.split { $0 == "x" || $0 == "X" || $0 == "×" || $0 == "*" }
        guard parts.count == 2,
            let width = Double(parts[0]),
            let height = Double(parts[1]),
            width > 1,
            height > 1
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
