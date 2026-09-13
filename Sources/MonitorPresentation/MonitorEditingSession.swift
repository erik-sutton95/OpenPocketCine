public enum MonitorEditingCancellation: Sendable {
    case interrupted
    case contextChanged
    case disappeared
}

/// Pairs one begin event with one completion event, including cancelled touches.
/// An invalidated touch cannot start another edit before that pointer lifts.
/// The host decides whether completion commits, resumes playback or just rests.
public struct MonitorEditingSession: Equatable, Sendable {
    public private(set) var isEditing = false
    private var cancelled = false

    public init() {}

    /// True only for the first event of a new editing session.
    public mutating func begin() -> Bool {
        guard !cancelled, !isEditing else { return false }
        isEditing = true
        return true
    }

    /// True only when an active session needs its matching completion event.
    public mutating func end() -> Bool {
        let wasEditing = isEditing
        isEditing = false
        cancelled = false
        return wasEditing
    }

    public mutating func cancel(pointerIsActive: Bool) -> Bool {
        let wasEditing = isEditing
        isEditing = false
        cancelled = pointerIsActive
        return wasEditing
    }
}
