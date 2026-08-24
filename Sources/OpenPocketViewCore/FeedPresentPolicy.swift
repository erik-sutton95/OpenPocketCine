import Foundation

/// Present-path hygiene for live and playback.
///
/// Freeze is a flag, not a flush. Latest frame wins. A hidden Metal / GLES
/// drawable is a black well — unhide replace-grade *before* `nextDrawable`.
/// Overlay chrome may stay hidden until the bake lands so an opaque empty
/// layer cannot cover identity.
///
/// Shells own the GPU. This type is the shared predicate.
public enum FeedPresentPolicy: Sendable {
    /// No new present for this long is a freeze. Matches ``FeedWatchdog/stallThreshold``.
    /// UDP still alive + frozen canvas is a present hitch, not a recover enable.
    public static let freezeThreshold: TimeInterval = FeedWatchdog.stallThreshold

    /// Runtime LUT / peaking / zebra working width. Cubes are resolution-independent;
    /// convolution graphs must not run at a 4K original when the monitor is 720p.
    public static let maxWorkingWidth: Int = 1440

    /// Visible, enabled, attached view with a real drawable. Overlay may be hidden
    /// until the first bake — use ``shouldScheduleBake(enabled:hasDrawable:)`` there.
    public static func shouldRender(
        attached: Bool,
        enabled: Bool,
        hidden: Bool,
        hasDrawable: Bool
    ) -> Bool {
        attached && enabled && !hidden && hasDrawable
    }

    /// Schedule a bake. Hidden overlay is OK; replace unhides before the drawable.
    public static func shouldScheduleBake(enabled: Bool, hasDrawable: Bool) -> Bool {
        enabled && hasDrawable
    }

    /// MTKView / display-link skip: same timestamp as the last successful present.
    /// `timeNs == 0` means unknown — never skip.
    public static func isDuplicateFrameTime(_ timeNs: Int64, lastPresentedNs: Int64) -> Bool {
        timeNs != 0 && lastPresentedNs != 0 && timeNs == lastPresentedNs
    }

    public static func isFrozen(secondsSinceLastPresent: TimeInterval?) -> Bool {
        guard let age = secondsSinceLastPresent else { return false }
        return age >= freezeThreshold
    }

    /// Overlay bakes set `hasPresentedFrame`, but LUT must not treat that as
    /// replace-ownership (opaque Metal over identity).
    public static func replaceOwnsPicture(
        hasPresentedFrame: Bool,
        lastPresentWasOverlay: Bool
    ) -> Bool {
        hasPresentedFrame && !lastPresentWasOverlay
    }

    /// Unhide the processed feed before `nextDrawable` on replace-grade.
    /// Overlay stays hidden until the transparent bake lands.
    public static func unhideMetalBeforeBake(overlay: Bool) -> Bool {
        !overlay
    }

    /// Prefer the 720p LRF/XRF proxy for monitor grade. 4K original is export-only.
    public static func preferProxyForMonitorGrade(hasProxy: Bool) -> Bool {
        hasProxy
    }

    /// Keep the last sample through recover. Flush is disconnect or a failed layer
    /// that already has a replacement picture, never a stall.
    public static func shouldFlushDisplayedImage(
        disconnecting: Bool,
        layerFailed: Bool,
        nextFrameReady: Bool
    ) -> Bool {
        if disconnecting { return true }
        if layerFailed { return nextFrameReady }
        return false
    }
}

/// One live-enable / recover write in flight. Overlapping `0x09/0xa8` is a black well.
public struct SerialSessionGate: Equatable, Sendable {
    public private(set) var inFlight = false

    public init() {}

    /// `true` if this caller owns the slot. Pair with ``end()``.
    public mutating func begin() -> Bool {
        guard !inFlight else { return false }
        inFlight = true
        return true
    }

    public mutating func end() {
        inFlight = false
    }
}
