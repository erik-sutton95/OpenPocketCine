import Foundation

/// One control holder. Host reclaim is `clear()`. Dropped holder with a `watcherID` parks 20 s.
public struct WatcherRelayControlLease: Equatable, Sendable {
    public static let defaultWindowSeconds: TimeInterval = 20

    public var holderName: String
    public var holderWatcherID: String?
    public let windowSeconds: TimeInterval

    private struct Parked: Equatable, Sendable {
        var watcherID: String
        var name: String
        var until: Date
    }

    private var parked: Parked?

    public init(
        holderName: String = "Host",
        windowSeconds: TimeInterval = WatcherRelayControlLease.defaultWindowSeconds
    ) {
        self.holderName = holderName
        self.windowSeconds = windowSeconds
    }

    public var hostHolds: Bool { holderWatcherID == nil }

    public func token(forWatcherID id: String?) -> WatcherRelayControlToken {
        WatcherRelayControlToken(
            holderName: holderName,
            holderIsRecipient: holderWatcherID != nil && holderWatcherID == id)
    }

    public mutating func grant(name: String, watcherID: String?) {
        holderName = name
        let id = watcherID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        holderWatcherID = id.isEmpty ? nil : id
        parked = nil
    }

    public mutating func reclaim(hostName: String) {
        holderName = hostName
        holderWatcherID = nil
        parked = nil
    }

    /// Dropped socket. Anonymous watcher releases immediately.
    @discardableResult
    public mutating func park(watcherID: String?, name: String, now: Date) -> Bool {
        guard holderWatcherID == watcherID else { return false }
        guard let watcherID, !watcherID.isEmpty else {
            reclaim(hostName: "Host")
            return false
        }
        parked = Parked(
            watcherID: watcherID, name: name, until: now.addingTimeInterval(windowSeconds))
        holderName = "Host"
        holderWatcherID = nil
        return true
    }

    @discardableResult
    public mutating func claim(watcherID: String?, name: String, now: Date) -> Bool {
        guard let watcherID, !watcherID.isEmpty else { return false }
        guard let parked, now < parked.until, parked.watcherID == watcherID else { return false }
        grant(name: name.isEmpty ? parked.name : name, watcherID: watcherID)
        return true
    }

    public mutating func clear() {
        parked = nil
        holderWatcherID = nil
        holderName = "Host"
    }

    public func shouldProxy(commandFrom watcherID: String?) -> Bool {
        guard let watcherID, !watcherID.isEmpty else { return false }
        return holderWatcherID == watcherID
    }
}
