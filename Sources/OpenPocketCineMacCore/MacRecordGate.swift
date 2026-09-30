import Foundation

/// One assigned camera at the moment a record command is considered.
public struct MacRecordCamera: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recording: Bool?
    public var statusAge: TimeInterval
    public var busy: Bool
    public var connected: Bool

    public init(
        id: UUID, recording: Bool?, statusAge: TimeInterval, busy: Bool, connected: Bool
    ) {
        self.id = id
        self.recording = recording
        self.statusAge = statusAge
        self.busy = busy
        self.connected = connected
    }

    public var fresh: Bool {
        connected && !busy && recording != nil && statusAge < MacRecordGate.freshLimit
    }
}

public enum MacRecordAction: Equatable, Sendable {
    case start
    case stop
    case skip
    case refuse
}

/// Record commands go out only when that camera's status is fresh. Group record refuses entirely
/// when any assigned camera is stale, and skips cameras already in the target state.
public enum MacRecordGate {
    public static let freshLimit: TimeInterval = 3

    public static func toggle(_ camera: MacRecordCamera) -> MacRecordAction {
        guard camera.fresh, let recording = camera.recording else { return .refuse }
        return recording ? .stop : .start
    }

    public struct Group: Equatable, Sendable {
        public var refused: Bool
        public var actions: [UUID: MacRecordAction]

        public init(refused: Bool, actions: [UUID: MacRecordAction]) {
            self.refused = refused
            self.actions = actions
        }
    }

    /// `stop` is the group action. True stops every camera that is recording.
    public static func group(_ cameras: [MacRecordCamera], stop: Bool) -> Group {
        guard !cameras.isEmpty, cameras.allSatisfy(\.fresh) else {
            return Group(
                refused: true,
                actions: Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, MacRecordAction.refuse) })
            )
        }
        var actions: [UUID: MacRecordAction] = [:]
        for camera in cameras {
            let recording = camera.recording == true
            if stop {
                actions[camera.id] = recording ? .stop : .skip
            } else {
                actions[camera.id] = recording ? .skip : .start
            }
        }
        return Group(refused: false, actions: actions)
    }
}

public enum MacRecordResult: Equatable, Sendable {
    case confirmed
    case rejected
    case unconfirmed
    case skipped
}

/// Group record keeps each camera's result. A partial failure is not rewritten as one outcome.
public struct MacGroupRecordReport: Equatable, Sendable {
    public var perTile: [UUID: MacRecordResult]
    public var summary: String

    public init(perTile: [UUID: MacRecordResult], summary: String) {
        self.perTile = perTile
        self.summary = summary
    }

    public static func make(_ perTile: [UUID: MacRecordResult], stop: Bool) -> MacGroupRecordReport {
        let acted = perTile.filter { $0.value != .skipped }
        let confirmed = acted.filter { $0.value == .confirmed }.count
        let summary: String
        if acted.isEmpty {
            summary = stop ? "Recording stopped" : "Recording"
        } else if confirmed == acted.count {
            summary =
                stop
                ? "Recording stopped"
                : "Recording on \(confirmed) \(confirmed == 1 ? "camera" : "cameras")"
        } else {
            summary = "\(confirmed) of \(acted.count) confirmed · check camera tiles"
        }
        return MacGroupRecordReport(perTile: perTile, summary: summary)
    }
}
