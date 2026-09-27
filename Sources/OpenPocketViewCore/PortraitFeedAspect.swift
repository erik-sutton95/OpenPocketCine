import Foundation

/// Which aspect the portrait feed renders at (operator pinch, persisted).
public enum PortraitFeedAspect: String, Codable, Equatable, Sendable {
    /// Full-width strip; whole image visible (16:9 letterboxed within the portrait width).
    case fit16x9
    /// Fills topBar→systemBar; center-crop zoom.
    case fill
}
