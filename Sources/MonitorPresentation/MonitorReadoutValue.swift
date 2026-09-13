import Foundation

/// Camera-independent values captured before a readout gesture begins. The
/// origin may be a visual fallback; an absent native selection stays absent.
public struct MonitorReadoutSnapshot: Hashable, Sendable {
    public let title: String
    public let options: [String]
    public let selection: String
    public let marked: Set<String>
    public let originIndex: Int

    public init(
        title: String, options: [String], selection: String, marked: Set<String> = [],
        fallbackIndex: Int = 0
    ) {
        self.title = title
        self.options = options
        self.selection = selection
        self.marked = marked
        originIndex =
            options.firstIndex(of: selection)
            ?? min(max(0, options.count - 1), max(0, fallbackIndex))
    }

    public func position(translation: Double) -> Double {
        MonitorDrumSelection.position(
            origin: originIndex, translation: translation, count: options.count)
    }

    public func selection(at position: Double) -> String {
        guard let index = index(at: position) else { return "" }
        if index == originIndex, !options.contains(selection) { return "" }
        return options[index]
    }

    /// A held origin is never an implicit selection, even when it looks like a
    /// valid fallback. A drag must finish on another detent to propose a write.
    public func changedValue(at position: Double) -> String? {
        guard let index = index(at: position), index != originIndex,
            options[index] != selection
        else { return nil }
        return options[index]
    }

    private func index(at position: Double) -> Int? {
        guard !options.isEmpty, position.isFinite else { return nil }
        return Int(min(Double(options.count - 1), max(0, position)).rounded())
    }
}

/// One immutable preview or release event. SourceIdentity belongs to the host:
/// the shared widget never interprets a camera ID, opcode, or native setting.
public struct MonitorReadoutValue<SourceIdentity: Hashable & Sendable>: Equatable, Sendable {
    public let id: UUID
    public let sourceIdentity: SourceIdentity
    public let snapshot: MonitorReadoutSnapshot
    public let position: Double

    public init(
        id: UUID, sourceIdentity: SourceIdentity, snapshot: MonitorReadoutSnapshot, position: Double
    ) {
        self.id = id
        self.sourceIdentity = sourceIdentity
        self.snapshot = snapshot
        self.position = position
    }

    public var selection: String { snapshot.selection(at: position) }
    public var changedValue: String? { snapshot.changedValue(at: position) }
}

public enum MonitorReadoutEvent<SourceIdentity: Hashable & Sendable>: Equatable, Sendable {
    case open(SourceIdentity)
    case preview(MonitorReadoutValue<SourceIdentity>)
    /// Lift closes the preview even when changedValue is nil. The host must
    /// revalidate its native source and ownership revision before writing.
    case commit(MonitorReadoutValue<SourceIdentity>, ownershipRevision: UInt64)
    /// Also delivered on invalidation while idle, to retire a host's delayed write.
    case cancel(UUID)
}
