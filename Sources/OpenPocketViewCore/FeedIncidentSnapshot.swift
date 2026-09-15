import Foundation

/// Schema for typed feed-incident bundles. Bump when grouping fields change.
public enum FeedIncidentSchema {
    public static let version = 1
}

/// Bounded origin of a feed session. Legacy records without the field are `unknown`.
public enum FeedIncidentTestSource: String, Equatable, Sendable, Codable {
    case manual
    case automation
    case faultInjection
    case verification
    case unknown

    public var rank: Int {
        switch self {
        case .unknown: return 0
        case .manual: return 1
        case .automation: return 2
        case .faultInjection: return 3
        case .verification: return 4
        }
    }

    public static func parse(_ raw: String?) -> FeedIncidentTestSource {
        guard let raw else { return .unknown }
        return FeedIncidentTestSource(rawValue: raw) ?? .unknown
    }

    /// Current-run derivation only. Never apply this to cached reports.
    public static func derive(
        verification: Bool,
        injectionActivated: Bool,
        automation: Bool
    ) -> FeedIncidentTestSource {
        if verification { return .verification }
        if injectionActivated { return .faultInjection }
        if automation { return .automation }
        return .manual
    }
}

/// Artifact identity distinct from marketing version/build. Token length holds
/// `ios-`/`android-` plus 32 hex characters.
public enum FeedIncidentBuildIdentity {
    public static let maxLength = 64

    public static func parse(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "unknown" }
        return FeedIncidentPrivacy.token(trimmed, max: maxLength)
    }
}

/// Bounds for the incident recorder. These are capture limits, not live budgets.
public enum FeedIncidentBounds {
    public static let preludeSeconds: TimeInterval = 60
    public static let aftermathSeconds: TimeInterval = 30
    public static let stallThreshold: TimeInterval = FeedWatchdog.stallThreshold
    public static let stringLength = 96
    public static let ringCount = 60
    public static let breadcrumbRing = 32
    public static let repairRing = 32
    public static let duringCount = 60
    public static let errorClasses = 16
}

/// Retention for on-device incident spool. First cap reached wins.
public struct FeedIncidentLimits: Equatable, Sendable {
    public var maxBundles: Int
    public var maxBundleBytes: Int
    public var maxSpoolBytes: Int
    public var ttl: TimeInterval

    public init(
        maxBundles: Int = 20,
        maxBundleBytes: Int = 262_144,
        maxSpoolBytes: Int = 10_485_760,
        ttl: TimeInterval = 604_800
    ) {
        self.maxBundles = max(1, maxBundles)
        self.maxBundleBytes = max(1_024, maxBundleBytes)
        self.maxSpoolBytes = max(self.maxBundleBytes, maxSpoolBytes)
        self.ttl = max(1, ttl)
    }

    public static let production = FeedIncidentLimits()
}

/// Ephemeral live-session identity. No camera serial or operator identifier.
public struct FeedIncidentSessionContext: Equatable, Sendable {
    public var sessionID: String
    public var appVersion: String
    public var appBuild: String
    public var sourceRevision: String
    public var osName: String
    public var osVersion: String
    public var hardwareClass: String
    public var cameraFamily: String
    public var cameraFirmware: String?
    public var decoderGeneration: Int
    public var socketGeneration: Int
    public var testSource: FeedIncidentTestSource
    public var buildIdentity: String

    public init(
        sessionID: String,
        appVersion: String,
        appBuild: String,
        sourceRevision: String,
        osName: String,
        osVersion: String,
        hardwareClass: String,
        cameraFamily: String,
        cameraFirmware: String? = nil,
        decoderGeneration: Int = 0,
        socketGeneration: Int = 0,
        testSource: FeedIncidentTestSource = .unknown,
        buildIdentity: String = "unknown"
    ) {
        self.sessionID = FeedIncidentPrivacy.token(sessionID)
        self.appVersion = FeedIncidentPrivacy.token(appVersion, max: 32)
        self.appBuild = FeedIncidentPrivacy.token(appBuild, max: 32)
        self.sourceRevision = FeedIncidentPrivacy.token(sourceRevision, max: 64)
        self.osName = FeedIncidentPrivacy.token(osName, max: 16)
        self.osVersion = FeedIncidentPrivacy.token(osVersion, max: 64)
        self.hardwareClass = FeedIncidentPrivacy.token(hardwareClass, max: 32)
        self.cameraFamily = FeedIncidentPrivacy.token(cameraFamily, max: 32)
        self.cameraFirmware = cameraFirmware.map { FeedIncidentPrivacy.token($0, max: 32) }
        self.decoderGeneration = max(0, decoderGeneration)
        self.socketGeneration = max(0, socketGeneration)
        self.testSource = testSource
        self.buildIdentity = FeedIncidentBuildIdentity.parse(buildIdentity)
    }
}

public enum FeedIncidentKind: String, Equatable, Sendable, Codable {
    case freshInputStaleOutput
    case decoderError
    case presentStalled
    case assistStalled
    case transportStall
    case unexpectedDisconnect
}

public enum FeedIncidentFailingStage: String, Equatable, Sendable, Codable {
    case packet
    case accessUnit
    case decodeAccept
    case decodedOutput
    case assistOutput
    case presentation
}

public enum FeedIncidentOutcome: String, Equatable, Sendable, Codable {
    case open
    case recovered
    case interrupted
    case exhausted
    case suppressed
}

public enum FeedIncidentSuppression: String, Equatable, Sendable, Codable {
    case none
    case disconnected
    case playback
    case background
    case neverEstablished
}

public enum FeedDecoderErrorOrigin: String, Equatable, Sendable, Codable {
    case none
    case sync
    case callback
    case create
}

public enum FeedIncidentBreadcrumbKind: String, Equatable, Sendable, Codable {
    case settingsEnter
    case settingsExit
    case assistChange
    case sceneActivity
    case surfaceAttach
    case surfaceDetach
    case decoderCreate
    case decoderInvalidate
    case pathChange
    case cameraCommand
}

public enum FeedRepairPhase: String, Equatable, Sendable, Codable {
    case requested
    case blocked
    case locallySent
    case peerResponse
    case pictureRestored
}

public struct FeedIncidentRates: Equatable, Sendable, Codable {
    public var packetHz: Double
    public var accessUnitHz: Double
    public var decodeSubmitHz: Double
    public var decodeAcceptHz: Double
    public var decodedOutputHz: Double
    public var assistOutputHz: Double
    public var presentHz: Double
    public var ackHz: Double

    public init(
        packetHz: Double = 0,
        accessUnitHz: Double = 0,
        decodeSubmitHz: Double = 0,
        decodeAcceptHz: Double = 0,
        decodedOutputHz: Double = 0,
        assistOutputHz: Double = 0,
        presentHz: Double = 0,
        ackHz: Double = 0
    ) {
        self.packetHz = FeedIncidentPrivacy.rate(packetHz)
        self.accessUnitHz = FeedIncidentPrivacy.rate(accessUnitHz)
        self.decodeSubmitHz = FeedIncidentPrivacy.rate(decodeSubmitHz)
        self.decodeAcceptHz = FeedIncidentPrivacy.rate(decodeAcceptHz)
        self.decodedOutputHz = FeedIncidentPrivacy.rate(decodedOutputHz)
        self.assistOutputHz = FeedIncidentPrivacy.rate(assistOutputHz)
        self.presentHz = FeedIncidentPrivacy.rate(presentHz)
        self.ackHz = FeedIncidentPrivacy.rate(ackHz)
    }
}

public struct FeedIncidentAges: Equatable, Sendable, Codable {
    public var packetAge: TimeInterval?
    public var accessUnitAge: TimeInterval?
    public var decodeAcceptAge: TimeInterval?
    public var decodedOutputAge: TimeInterval?
    public var assistOutputAge: TimeInterval?
    public var presentAge: TimeInterval?

    public init(
        packetAge: TimeInterval? = nil,
        accessUnitAge: TimeInterval? = nil,
        decodeAcceptAge: TimeInterval? = nil,
        decodedOutputAge: TimeInterval? = nil,
        assistOutputAge: TimeInterval? = nil,
        presentAge: TimeInterval? = nil
    ) {
        self.packetAge = FeedIncidentPrivacy.age(packetAge)
        self.accessUnitAge = FeedIncidentPrivacy.age(accessUnitAge)
        self.decodeAcceptAge = FeedIncidentPrivacy.age(decodeAcceptAge)
        self.decodedOutputAge = FeedIncidentPrivacy.age(decodedOutputAge)
        self.assistOutputAge = FeedIncidentPrivacy.age(assistOutputAge)
        self.presentAge = FeedIncidentPrivacy.age(presentAge)
    }
}

public struct FeedIncidentQueue: Equatable, Sendable, Codable {
    public var bytes: Int
    public var count: Int
    public var ageMilliseconds: Double
    public var incompleteAccessUnits: Int
    public var drops: Int

    public init(
        bytes: Int = 0,
        count: Int = 0,
        ageMilliseconds: Double = 0,
        incompleteAccessUnits: Int = 0,
        drops: Int = 0
    ) {
        self.bytes = max(0, bytes)
        self.count = max(0, count)
        self.ageMilliseconds = FeedIncidentPrivacy.rate(ageMilliseconds)
        self.incompleteAccessUnits = max(0, incompleteAccessUnits)
        self.drops = max(0, drops)
    }
}

public struct FeedIncidentDecoder: Equatable, Sendable, Codable {
    public var generation: Int
    public var formatGeneration: Int
    public var codec: String
    public var width: Int
    public var height: Int
    public var lastStatus: Int32?
    public var lastFlags: UInt32?
    public var origin: FeedDecoderErrorOrigin
    public var errorClass: String?
    public var errorCount: Int
    public var decoderFailed: Bool
    public var errorAge: TimeInterval?
    public var receivedIrap: Bool
    public var awaitingIrap: Bool
    public var hasDecodableReferences: Bool
    public var lastIrapAge: TimeInterval?
    public var lastSuccessfulOutputAge: TimeInterval?
    public var rebuildReason: String?

    public init(
        generation: Int = 0,
        formatGeneration: Int = 0,
        codec: String = "hevc",
        width: Int = 0,
        height: Int = 0,
        lastStatus: Int32? = nil,
        lastFlags: UInt32? = nil,
        origin: FeedDecoderErrorOrigin = .none,
        errorClass: String? = nil,
        errorCount: Int = 0,
        decoderFailed: Bool = false,
        errorAge: TimeInterval? = nil,
        receivedIrap: Bool = false,
        awaitingIrap: Bool = false,
        hasDecodableReferences: Bool = true,
        lastIrapAge: TimeInterval? = nil,
        lastSuccessfulOutputAge: TimeInterval? = nil,
        rebuildReason: String? = nil
    ) {
        self.generation = max(0, generation)
        self.formatGeneration = max(0, formatGeneration)
        self.codec = FeedIncidentPrivacy.token(codec, max: 16)
        self.width = max(0, width)
        self.height = max(0, height)
        self.lastStatus = lastStatus
        self.lastFlags = lastFlags
        self.origin = origin
        self.errorClass = errorClass.map { FeedIncidentPrivacy.token($0, max: 32) }
        self.errorCount = max(0, errorCount)
        self.decoderFailed = decoderFailed
        self.errorAge = FeedIncidentPrivacy.age(errorAge)
        self.receivedIrap = receivedIrap
        self.awaitingIrap = awaitingIrap
        self.hasDecodableReferences = hasDecodableReferences
        self.lastIrapAge = FeedIncidentPrivacy.age(lastIrapAge)
        self.lastSuccessfulOutputAge = FeedIncidentPrivacy.age(lastSuccessfulOutputAge)
        self.rebuildReason = rebuildReason.map { FeedIncidentPrivacy.token($0) }
    }
}

public struct FeedIncidentLifecycle: Equatable, Sendable, Codable {
    public var foreground: Bool
    public var settingsCovered: Bool
    public var playbackActive: Bool
    public var connected: Bool
    public var liveEstablished: Bool
    public var thermalState: String
    public var memoryWarning: Bool
    public var lowPower: Bool
    public var sceneActive: Bool
    public var assistState: String
    public var outputObservable: Bool
    public var presentationExpected: Bool

    public init(
        foreground: Bool = true,
        settingsCovered: Bool = false,
        playbackActive: Bool = false,
        connected: Bool = false,
        liveEstablished: Bool = false,
        thermalState: String = "nominal",
        memoryWarning: Bool = false,
        lowPower: Bool = false,
        sceneActive: Bool = true,
        assistState: String = "off",
        outputObservable: Bool = true,
        presentationExpected: Bool = true
    ) {
        self.foreground = foreground
        self.settingsCovered = settingsCovered
        self.playbackActive = playbackActive
        self.connected = connected
        self.liveEstablished = liveEstablished
        self.thermalState = FeedIncidentPrivacy.token(thermalState, max: 16)
        self.memoryWarning = memoryWarning
        self.lowPower = lowPower
        self.sceneActive = sceneActive
        self.assistState = FeedIncidentPrivacy.token(assistState, max: 32)
        self.outputObservable = outputObservable
        self.presentationExpected = presentationExpected
    }
}

/// One-second allowlisted stage snapshot. No compressed payload, footage, or PII.
public struct FeedIncidentSnapshot: Equatable, Sendable, Codable {
    public var monotonicNow: TimeInterval
    public var wallClock: Date
    public var rates: FeedIncidentRates
    public var ages: FeedIncidentAges
    public var queue: FeedIncidentQueue
    public var decoder: FeedIncidentDecoder
    public var lifecycle: FeedIncidentLifecycle
    public var watchdogAction: String
    public var diagnoserFailure: String
    public var diagnoserRepair: String

    public init(
        monotonicNow: TimeInterval,
        wallClock: Date = Date(timeIntervalSince1970: 0),
        rates: FeedIncidentRates = FeedIncidentRates(),
        ages: FeedIncidentAges = FeedIncidentAges(),
        queue: FeedIncidentQueue = FeedIncidentQueue(),
        decoder: FeedIncidentDecoder = FeedIncidentDecoder(),
        lifecycle: FeedIncidentLifecycle = FeedIncidentLifecycle(),
        watchdogAction: String = "none",
        diagnoserFailure: String = "none",
        diagnoserRepair: String = "none"
    ) {
        self.monotonicNow = FeedIncidentPrivacy.stamp(monotonicNow)
        self.wallClock = wallClock
        self.rates = rates
        self.ages = ages
        self.queue = queue
        self.decoder = decoder
        self.lifecycle = lifecycle
        self.watchdogAction = FeedIncidentPrivacy.token(watchdogAction, max: 32)
        self.diagnoserFailure = FeedIncidentPrivacy.token(diagnoserFailure, max: 32)
        self.diagnoserRepair = FeedIncidentPrivacy.token(diagnoserRepair, max: 32)
    }
}

public struct FeedIncidentBreadcrumb: Equatable, Sendable, Codable {
    public var monotonicAt: TimeInterval
    public var kind: FeedIncidentBreadcrumbKind
    public var detail: String

    public init(
        monotonicAt: TimeInterval,
        kind: FeedIncidentBreadcrumbKind,
        detail: String = ""
    ) {
        self.monotonicAt = FeedIncidentPrivacy.stamp(monotonicAt)
        self.kind = kind
        self.detail = FeedIncidentPrivacy.token(detail, max: 32)
    }
}

/// Typed native SDK breadcrumb payload. Unknown values are dropped, not coerced.
public enum FeedIncidentNativeBreadcrumb: Sendable {
    public static let allowedValues: [String: Set<String>] = [
        "sceneState": ["active", "inactive"],
        "assistState": ["off", "identity", "replacement"],
        "path": ["unexpectedDisconnect"],
        "repairPhase": [
            "requested", "blocked", "locallySent", "peerResponse", "pictureRestored",
        ],
        "repairAction": ["decoder", "enable", "session", "endpoint", "rejoin"],
    ]

    public static func isAllowedMessage(_ message: String) -> Bool {
        FeedIncidentBreadcrumbKind(rawValue: message) != nil || message == "repair"
    }

    public static func details(kind: FeedIncidentBreadcrumbKind, detail: String) -> [String: String]
    {
        switch kind {
        case .sceneActivity:
            return sanitized(["sceneState": detail])
        case .assistChange:
            return sanitized(["assistState": detail])
        case .pathChange:
            return sanitized(["path": detail])
        case .settingsEnter, .settingsExit, .surfaceAttach, .surfaceDetach,
            .decoderCreate, .decoderInvalidate, .cameraCommand:
            return [:]
        }
    }

    public static func details(repair: FeedRepairRecord) -> [String: String] {
        sanitized([
            "repairPhase": repair.phase.rawValue,
            "repairAction": repair.action,
        ])
    }

    public static func sanitized(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in raw {
            let token = FeedIncidentPrivacy.token(value, max: 32)
            guard let allowed = allowedValues[key], allowed.contains(token) else { continue }
            out[key] = token
        }
        return out
    }
}

public struct FeedRepairRecord: Equatable, Sendable, Codable {
    public var monotonicAt: TimeInterval
    public var action: String
    public var phase: FeedRepairPhase
    public var reason: String?

    public init(
        monotonicAt: TimeInterval,
        action: String,
        phase: FeedRepairPhase,
        reason: String? = nil
    ) {
        self.monotonicAt = FeedIncidentPrivacy.stamp(monotonicAt)
        self.action = FeedIncidentPrivacy.token(action, max: 32)
        self.phase = phase
        self.reason = reason.map { FeedIncidentPrivacy.token($0, max: 32) }
    }
}

public struct FeedIncidentErrorCount: Equatable, Sendable, Codable {
    public var errorClass: String
    public var count: Int

    public init(errorClass: String, count: Int) {
        self.errorClass = FeedIncidentPrivacy.token(errorClass, max: 32)
        self.count = max(0, count)
    }
}

public struct FeedIncidentHeader: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var incidentID: String
    public var sessionID: String
    public var kind: FeedIncidentKind
    public var failingStage: FeedIncidentFailingStage
    public var errorClass: String?
    public var outcome: FeedIncidentOutcome
    public var startedAtWallClock: Date
    public var startedAtMonotonic: TimeInterval
    public var endedAtMonotonic: TimeInterval?
    public var firstFailureAt: TimeInterval
    public var worstGapSeconds: TimeInterval
    public var appVersion: String
    public var appBuild: String
    public var sourceRevision: String
    public var osName: String
    public var osVersion: String
    public var hardwareClass: String
    public var cameraFamily: String
    public var cameraFirmware: String?
    public var decoderGeneration: Int
    public var socketGeneration: Int
    public var evictions: Int
    public var assistState: String
    public var healthyExposureSeconds: TimeInterval
    /// Absent on legacy bundles. Do not fill from the current process.
    public var testSource: FeedIncidentTestSource? = nil
    public var buildIdentity: String? = nil

    public var processInterrupted: Bool { outcome == .interrupted }

    public var resolvedTestSource: FeedIncidentTestSource { testSource ?? .unknown }

    public var resolvedBuildIdentity: String { FeedIncidentBuildIdentity.parse(buildIdentity) }
}

public struct FeedIncidentBundle: Equatable, Sendable, Codable {
    public var header: FeedIncidentHeader
    public var prelude: [FeedIncidentSnapshot]
    public var during: [FeedIncidentSnapshot]
    public var aftermath: [FeedIncidentSnapshot]
    public var breadcrumbs: [FeedIncidentBreadcrumb]
    public var repairs: [FeedRepairRecord]
    public var aggregatedErrors: [FeedIncidentErrorCount]
}

/// Stable grouping keys for a future vendor event. Not an SDK payload.
public struct FeedIncidentGrouping: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var failingStage: String
    public var errorClass: String
    public var outcome: String
    public var release: String
    public var os: String
    public var hardwareClass: String
    public var cameraFirmware: String
    public var assistState: String
}

public struct FeedIncidentVendorEnvelope: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var eventName: String
    public var grouping: FeedIncidentGrouping
    public var incidentID: String
    public var sessionID: String
    public var kind: String
    public var worstGapSeconds: TimeInterval
    public var healthyExposureSeconds: TimeInterval
    public var decoderGeneration: Int
    public var socketGeneration: Int
    public var testSource: String
    public var buildIdentity: String
}

public struct FeedIncidentVerdict: Equatable, Sendable {
    public var suppression: FeedIncidentSuppression
    public var kind: FeedIncidentKind?
    public var failingStage: FeedIncidentFailingStage?

    public var shouldRecord: Bool {
        suppression == .none && kind != nil && failingStage != nil
    }
}

/// Classifies an established-feed stall from allowlisted stage counters.
public enum FeedIncidentClassifier: Sendable {
    public static func suppression(of snapshot: FeedIncidentSnapshot) -> FeedIncidentSuppression? {
        let life = snapshot.lifecycle
        if life.playbackActive { return .playback }
        if !life.connected { return .disconnected }
        if !life.foreground || !life.sceneActive { return .background }
        if !life.liveEstablished { return .neverEstablished }
        return nil
    }

    public static func classify(_ snapshot: FeedIncidentSnapshot) -> FeedIncidentVerdict {
        if let suppression = suppression(of: snapshot) {
            return FeedIncidentVerdict(suppression: suppression, kind: nil, failingStage: nil)
        }

        let life = snapshot.lifecycle
        let threshold = FeedIncidentBounds.stallThreshold
        let packetFresh =
            FeedIncidentPrivacy.isFresh(snapshot.ages.packetAge, threshold: threshold)
            || snapshot.rates.packetHz >= 1
        let auFresh =
            FeedIncidentPrivacy.isFresh(snapshot.ages.accessUnitAge, threshold: threshold)
            || snapshot.rates.accessUnitHz >= 1
        let inputFresh = packetFresh || auFresh
        let outputStale =
            life.outputObservable
            && FeedIncidentPrivacy.isStale(
                age: snapshot.ages.decodedOutputAge,
                hertz: snapshot.rates.decodedOutputHz,
                flowingAlternative: snapshot.rates.decodeSubmitHz >= 1 || inputFresh,
                threshold: threshold)
        let outputFresh =
            life.outputObservable
            && FeedIncidentPrivacy.isFresh(snapshot.ages.decodedOutputAge, threshold: threshold)
        let presentStale =
            life.presentationExpected
            && FeedIncidentPrivacy.isStale(
                age: snapshot.ages.presentAge,
                hertz: snapshot.rates.presentHz,
                flowingAlternative: true,
                threshold: threshold)
        let assistStale = FeedIncidentPrivacy.isStale(
            age: snapshot.ages.assistOutputAge,
            hertz: snapshot.rates.assistOutputHz,
            flowingAlternative: outputFresh,
            threshold: threshold)

        if life.outputObservable && outputStale {
            let currentError = isCurrentDecoderFailure(snapshot.decoder)
            let acceptStale = FeedIncidentPrivacy.isStale(
                age: snapshot.ages.decodeAcceptAge,
                hertz: snapshot.rates.decodeAcceptHz,
                flowingAlternative: snapshot.rates.decodeSubmitHz >= 1,
                threshold: threshold)
            let stage: FeedIncidentFailingStage =
                acceptStale && snapshot.rates.decodeSubmitHz >= 1 ? .decodeAccept : .decodedOutput
            let kind: FeedIncidentKind
            if currentError {
                kind = .decoderError
            } else if inputFresh {
                kind = .freshInputStaleOutput
            } else {
                kind = .transportStall
            }
            return FeedIncidentVerdict(suppression: .none, kind: kind, failingStage: stage)
        }
        if (outputFresh || !life.outputObservable) && assistStale
            && snapshot.ages.assistOutputAge != nil
        {
            return FeedIncidentVerdict(
                suppression: .none, kind: .assistStalled, failingStage: .assistOutput)
        }
        if (outputFresh || !life.outputObservable) && presentStale {
            return FeedIncidentVerdict(
                suppression: .none, kind: .presentStalled, failingStage: .presentation)
        }
        if !inputFresh {
            if life.outputObservable && outputFresh {
                return FeedIncidentVerdict(suppression: .none, kind: nil, failingStage: nil)
            }
            if !life.outputObservable && life.presentationExpected
                && FeedIncidentPrivacy.isFresh(snapshot.ages.presentAge, threshold: threshold)
            {
                return FeedIncidentVerdict(suppression: .none, kind: nil, failingStage: nil)
            }
            return FeedIncidentVerdict(
                suppression: .none, kind: .transportStall,
                failingStage: packetFresh ? .accessUnit : .packet)
        }
        return FeedIncidentVerdict(suppression: .none, kind: nil, failingStage: nil)
    }

    /// Fresh decoded output and presentation when those stages are observable.
    /// A generation change or repair request is not recovery.
    public static func isRecovered(_ snapshot: FeedIncidentSnapshot) -> Bool {
        if suppression(of: snapshot) != nil { return false }
        let life = snapshot.lifecycle
        let threshold = FeedIncidentBounds.stallThreshold
        // With neither downstream stage observable, receipt of compressed
        // packets cannot prove picture recovery or healthy live exposure.
        guard life.outputObservable || life.presentationExpected else { return false }
        if life.outputObservable {
            guard
                FeedIncidentPrivacy.isFresh(
                    snapshot.ages.decodedOutputAge, threshold: threshold)
            else { return false }
        }
        if life.presentationExpected {
            guard
                FeedIncidentPrivacy.isFresh(snapshot.ages.presentAge, threshold: threshold)
            else { return false }
        }
        return true
    }

    public static func isCurrentDecoderFailure(_ decoder: FeedIncidentDecoder) -> Bool {
        if decoder.decoderFailed { return true }
        guard let errorAge = decoder.errorAge else { return false }
        if let success = decoder.lastSuccessfulOutputAge {
            return errorAge < success
        }
        return true
    }
}

public enum FeedIncidentFileNaming: Sendable {
    public static func incident(id: String) -> String {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "incident-\(safe.isEmpty ? "unknown" : safe).json"
    }

    public static func metricKit(
        kind: String, deliveredAt: Date, deliveryID: UUID, index: Int
    ) -> String {
        let safeKind = kind.filter { $0.isLetter || $0.isNumber }
        let kindName = safeKind.isEmpty ? "payload" : safeKind
        let millis = Int((deliveredAt.timeIntervalSince1970 * 1_000).rounded())
        return "metrickit-\(kindName)-\(millis)-\(deliveryID.uuidString)-\(max(0, index)).json"
    }
}

enum FeedIncidentPrivacy {
    static func token(_ raw: String, max: Int = FeedIncidentBounds.stringLength) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(trimmed.prefix(max))
        return PrivacyRedactor.redact(clipped)
    }

    static func rate(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        return value
    }

    static func stamp(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value >= 0 else { return 0 }
        return value
    }

    static func age(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func isFresh(_ age: TimeInterval?, threshold: TimeInterval) -> Bool {
        guard let age else { return false }
        return age < threshold
    }

    static func isStale(
        age: TimeInterval?,
        hertz: Double,
        flowingAlternative: Bool,
        threshold: TimeInterval
    ) -> Bool {
        if let age { return age >= threshold }
        return hertz == 0 && flowingAlternative
    }

    static func gapSeconds(for snapshot: FeedIncidentSnapshot, stage: FeedIncidentFailingStage)
        -> TimeInterval
    {
        let ages = snapshot.ages
        let chosen: TimeInterval?
        switch stage {
        case .packet: chosen = ages.packetAge
        case .accessUnit: chosen = ages.accessUnitAge
        case .decodeAccept: chosen = ages.decodeAcceptAge
        case .decodedOutput: chosen = ages.decodedOutputAge
        case .assistOutput: chosen = ages.assistOutputAge
        case .presentation: chosen = ages.presentAge
        }
        return age(chosen) ?? 0
    }
}

enum FeedIncidentCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
