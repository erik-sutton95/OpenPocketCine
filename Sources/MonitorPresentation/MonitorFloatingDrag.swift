/// A floating window's interaction-local placement transaction. Native gesture
/// owners supply clamped positions; persistence belongs to the release boundary.
public struct MonitorFloatingDrag<Position: Equatable> {
    public private(set) var origin: Position?
    public private(set) var preview: Position?

    public init() {}

    public mutating func begin(at position: Position) {
        origin = position
        preview = nil
    }

    public mutating func move(to position: Position) {
        guard origin != nil, preview != position else { return }
        preview = position
    }

    public mutating func end(store: (Position) -> Void) {
        let final = preview
        cancel()
        if let final { store(final) }
    }

    public mutating func cancel() {
        origin = nil
        preview = nil
    }
}
