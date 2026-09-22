import Foundation

/// Converts native waypoint projection into the live picture's horizontal space.
/// Used by both waypoint letters and the Motion Control curve in the shell.
public enum GimbalWaypointPresentation {
    /// The settled TT180 pan latch composes with MIRROR assist. Selfie Flip
    /// changes camera encoding and its decoder compensation together, so the
    /// decoder's extra-mirror flag is not the native-to-picture pan direction.
    public static func normalizedX(
        _ normalizedX: Double, poseInvertPan: Bool, assistMirror: Bool
    ) -> Double {
        (poseInvertPan != assistMirror) ? 1 - normalizedX : normalizedX
    }
}
