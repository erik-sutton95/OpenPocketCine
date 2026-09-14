import Foundation
import OpenPocketViewCore
import os

/// Timing only: never participates in decoder, assist or recovery decisions.
/// Fixed-size counters cross the VT/assist/main queues; publication stays at 1 Hz.
final class LiveDecodeMetrics: @unchecked Sendable {
    private struct State {
        var submitted: DeliveryCadence
        var accepted: DeliveryCadence
        var decoded: DeliveryCadence
        var assistInput: DeliveryCadence
        var assistOutput: DeliveryCadence
        var adopted: DeliveryCadence
        var lastOutputAt: TimeInterval?
        var totalOutputs = 0
        var totalSubmissions = 0
        var totalAccepted = 0
        var totalAssistOutputs = 0
        var lastAcceptedAt: TimeInterval?
        var lastAssistOutputAt: TimeInterval?
        var decodeMax: TimeInterval = 0
        var assistMax: TimeInterval = 0
        var mainMax: TimeInterval = 0

        init(at now: TimeInterval) {
            submitted = DeliveryCadence(startedAt: now)
            accepted = DeliveryCadence(startedAt: now)
            decoded = DeliveryCadence(startedAt: now)
            assistInput = DeliveryCadence(startedAt: now)
            assistOutput = DeliveryCadence(startedAt: now)
            adopted = DeliveryCadence(startedAt: now)
        }
    }

    private let state = OSAllocatedUnfairLock(
        initialState: State(at: ProcessInfo.processInfo.systemUptime))

    func reset() {
        state.withLock { $0 = State(at: ProcessInfo.processInfo.systemUptime) }
    }

    func submitted() {
        state.withLock {
            $0.submitted.note(at: ProcessInfo.processInfo.systemUptime)
            $0.totalSubmissions += 1
        }
    }

    func decoded(at now: TimeInterval, submittedAt: TimeInterval) {
        state.withLock {
            $0.decoded.note(at: now)
            $0.lastOutputAt = now
            $0.totalOutputs += 1
            $0.decodeMax = max($0.decodeMax, now - submittedAt)
        }
    }

    func accepted() {
        state.withLock {
            $0.accepted.note(at: ProcessInfo.processInfo.systemUptime)
            $0.totalAccepted += 1
            $0.lastAcceptedAt = ProcessInfo.processInfo.systemUptime
        }
    }

    var outputAge: TimeInterval? {
        state.withLock { value in
            value.lastOutputAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) }
        }
    }

    var totals: (submitted: Int, accepted: Int, output: Int) {
        state.withLock { ($0.totalSubmissions, $0.totalAccepted, $0.totalOutputs) }
    }

    struct Snapshot {
        var submitted: Int
        var accepted: Int
        var output: Int
        var assistOutput: Int
        var acceptedAge: TimeInterval?
        var outputAge: TimeInterval?
        var assistOutputAge: TimeInterval?
    }

    var snapshot: Snapshot {
        state.withLock { value in
            let now = ProcessInfo.processInfo.systemUptime
            return Snapshot(
                submitted: value.totalSubmissions, accepted: value.totalAccepted,
                output: value.totalOutputs, assistOutput: value.totalAssistOutputs,
                acceptedAge: value.lastAcceptedAt.map { max(0, now - $0) },
                outputAge: value.lastOutputAt.map { max(0, now - $0) },
                assistOutputAge: value.lastAssistOutputAt.map { max(0, now - $0) })
        }
    }

    func assistInput() {
        state.withLock { $0.assistInput.note(at: ProcessInfo.processInfo.systemUptime) }
    }

    func assistOutput(at now: TimeInterval, submittedAt: TimeInterval) {
        state.withLock {
            $0.assistOutput.note(at: now)
            $0.totalAssistOutputs += 1
            $0.lastAssistOutputAt = now
            $0.assistMax = max($0.assistMax, now - submittedAt)
        }
    }

    func adopted(at now: TimeInterval, completedAt: TimeInterval) {
        state.withLock {
            $0.adopted.note(at: ProcessInfo.processInfo.systemUptime)
            $0.mainMax = max($0.mainMax, now - completedAt)
        }
    }

    func takeLine(vtActive: Bool) -> String {
        let snapshot = state.withLock { value in
            let now = ProcessInfo.processInfo.systemUptime
            let windows = [
                ("vtSubmit", value.submitted.takeWindow(at: now)),
                ("vtAccept", value.accepted.takeWindow(at: now)),
                ("vtOutput", value.decoded.takeWindow(at: now)),
                ("assistInput", value.assistInput.takeWindow(at: now)),
                ("assistOutput", value.assistOutput.takeWindow(at: now)),
                ("assistMain", value.adopted.takeWindow(at: now)),
            ]
            let delays = (value.decodeMax, value.assistMax, value.mainMax)
            value.decodeMax = 0
            value.assistMax = 0
            value.mainMax = 0
            return (windows, delays)
        }
        let fields = snapshot.0.compactMap { name, window -> String? in
            guard let window else { return nil }
            return "\(name)Hz=\(String(format: "%.1f", window.hertz)) "
                + "\(name)GapMs=\(Int(window.maximumGapMilliseconds))"
        }.joined(separator: " ")
        return "feed: decode vtActive=\(vtActive ? 1 : 0) \(fields) "
            + "vtMaxMs=\(Int(snapshot.1.0 * 1_000)) "
            + "assistMaxMs=\(Int(snapshot.1.1 * 1_000)) "
            + "assistMainMaxMs=\(Int(snapshot.1.2 * 1_000))"
    }
}
