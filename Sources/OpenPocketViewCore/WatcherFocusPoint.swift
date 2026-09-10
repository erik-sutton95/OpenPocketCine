import Foundation

/// Focus coordinates come from the fitted picture, never the screen or its chrome.
public enum WatcherFocusPoint {
    public struct Point: Equatable, Sendable {
        public var x: Int
        public var y: Int
    }
    public static func map(x: Double, y: Double, width: Double, height: Double, mirrored: Bool)
        -> Point?
    {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
            width > 0, height > 0, x >= 0, y >= 0, x <= width, y <= height
        else { return nil }
        let nx = x / width
        return Point(
            x: Int(((mirrored ? 1 - nx : nx) * 1000).rounded()),
            y: Int((y / height * 1000).rounded()))
    }
}
