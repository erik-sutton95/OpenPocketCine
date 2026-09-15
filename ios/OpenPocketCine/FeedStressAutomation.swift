import CoreFoundation
import Darwin
import Foundation
import OpenPocketViewCore
import UIKit
import os

/// Debug-only live-feed stress seam. Release is a no-op. No operator chrome.
///
/// Present counters are admission, not display scanout:
/// `noteIdentityEnqueue` = AVSampleBufferDisplayLayer enqueue;
/// `noteMetalPresent` = Metal GPU completion; `notePresent()` splits by `#fileID`.
enum FeedStressAutomation {
    private static let enabled = ProcessInfo.processInfo.environment["OPV_FEED_STRESS"] == "1"

    static var isEnabled: Bool { enabled }

    static var injectionDidActivate: Bool {
        #if DEBUG
            return FeedStressRuntime.shared.injectionDidActivate
        #else
            return false
        #endif
    }

    static func installIfRequested() {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.installIfRequested()
        #endif
    }

    static func noteSourceObserved(videoPackets: Int, accessUnits: Int) {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteSourceObserved(
                videoPackets: videoPackets, accessUnits: accessUnits)
        #endif
    }

    static func noteSourceDelivered(videoPackets: Int, accessUnits: Int) {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteSourceDelivered(
                videoPackets: videoPackets, accessUnits: accessUnits)
        #endif
    }

    static func noteDecodeSubmit() {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteDecodeSubmit()
        #endif
    }

    static func noteDecoded() {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteDecoded()
        #endif
    }

    /// Call-site `#fileID` selects enqueue vs Metal. Not scanout.
    static func notePresent(file: StaticString = #fileID) {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.notePresent(file: file)
        #endif
    }

    static func noteIdentityEnqueue() {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteIdentityEnqueue()
        #endif
    }

    static func noteMetalPresent() {
        #if DEBUG
            guard enabled else { return }
            FeedStressRuntime.shared.noteMetalPresent()
        #endif
    }

    static func shouldDropPacket(seq: UInt64) -> Bool {
        #if DEBUG
            guard enabled else { return false }
            return FeedStressRuntime.shared.shouldDropPacket(seq: seq)
        #else
            return false
        #endif
    }

    /// Always 0. Do not sleep on the UDP ACK queue.
    static func packetDelayNanoseconds() -> UInt64 { 0 }

    /// Call before decode-success accounting. True means swallow this output.
    static func shouldSilenceOutput(now: TimeInterval = ProcessInfo.processInfo.systemUptime)
        -> Bool
    {
        #if DEBUG
            guard enabled else { return false }
            return FeedStressRuntime.shared.shouldSilenceOutput(now: now)
        #else
            return false
        #endif
    }

    static func snapshotLine() -> String {
        #if DEBUG
            guard enabled else { return "" }
            return FeedStressRuntime.shared.snapshotLine()
        #else
            return ""
        #endif
    }
}

#if DEBUG

    private let feedStressBeginPrefix = "com.opencapture.opc.feed-stress.begin."
    private let feedStressPassPrefix = "com.opencapture.opc.feed-stress.pass."
    private let feedStressFailPrefix = "com.opencapture.opc.feed-stress.fail."
    private let feedStressArmInject = "com.opencapture.opc.feed-stress.arm-inject"
    private let feedStressDisarmInject = "com.opencapture.opc.feed-stress.disarm-inject"
    private let feedStressTeardown = "com.opencapture.opc.feed-stress.teardown"

    private let feedStressScenarios = [
        "settingsOpenClose", "assistToggles", "rotation", "cameraSettingChanges",
        "boundedJoystick", "lifecycleInterrupt", "briefRecord", "injectFault",
    ]

    private let feedStressDarwinCallback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        let key = name.map { $0.rawValue as String } ?? ""
        Unmanaged<FeedStressRuntime>.fromOpaque(observer).takeUnretainedValue()
            .handleDarwin(key)
    }

    private struct FeedStressCounters {
        var sourceObservedPackets = 0
        var sourceObservedAUs = 0
        var sourceDeliveredPackets = 0
        var sourceDeliveredAUs = 0
        var decodeSubmits = 0
        var decodedOutputs = 0
        var presents = 0
        var presentEnqueue = 0
        var presentMetal = 0
        var lastSourceObservedAt: TimeInterval?
        var lastSourceDeliveredAt: TimeInterval?
        var lastDecodeSubmitAt: TimeInterval?
        var lastDecodedAt: TimeInterval?
        var lastPresentAt: TimeInterval?
        var lastEnqueueAt: TimeInterval?
        var lastMetalAt: TimeInterval?
        var windowSourceHz = 0.0
        var windowDecodeHz = 0.0
        var windowPresentHz = 0.0
        var healthySince: TimeInterval?
        var injectArmedAt: TimeInterval?
        var silenceUntil: TimeInterval?
        var silenceConsumed = false
        var packetIndex: UInt64 = 0
        var burstLeft = 0
        var halt = ""
        var injectDrops = 0
        var injectSilences = 0
        var recording = false
        var cameraFamily = "unknown"
        var reconnect = "idle"
    }

    private struct FeedStressPlan {
        var lossProbability = 0.0
        var burstDropCount = 0
        var burstEveryN = 0
        var outputSilenceMs = 0
        var configured = false
    }

    private struct FeedStressBaseline {
        var captured = false
        var isoIndex: IsoIndex?
        var whiteBalance: WhiteBalance?
        var peaking = false
        var falseColor = false
        var waveform = false
        var lut = false
    }

    private struct FeedStressRNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func nextDouble() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }

    final class FeedStressRuntime: @unchecked Sendable {
        static let shared = FeedStressRuntime()

        private let lock = OSAllocatedUnfairLock(initialState: FeedStressCounters())
        private let io = DispatchQueue(label: "opc.feed-stress", qos: .utility)
        private var installed = false
        private var seed: UInt64 = 20_260_914
        private var limitS: TimeInterval = 300
        private var startedAt: TimeInterval = 0
        private var wallStart = Date()
        private var runId = ""
        private var directory: URL?
        private var plan = FeedStressPlan()
        private var rng: FeedStressRNG
        private var timer: DispatchSourceTimer?
        private var probe: FeedStressProbeView?
        private var baseline = FeedStressBaseline()
        private var restored = false
        private var prevDeliveredPackets = 0
        private var prevDecoded = 0
        private var prevPresents = 0
        private var reconnectAttempted = false
        private var didNotifyInjection = false
        @MainActor private var originalIdleTimerDisabled: Bool?

        private init() {
            rng = FeedStressRNG(state: 20_260_914)
        }

        func installIfRequested() {
            let env = ProcessInfo.processInfo.environment
            guard env["OPV_FEED_STRESS"] == "1" else { return }
            let first: Bool = lock.withLock { _ in
                guard !installed else { return false }
                installed = true
                seed = UInt64(env["OPV_FEED_STRESS_SEED"] ?? "") ?? 20_260_914
                limitS = TimeInterval(env["OPV_FEED_STRESS_LIMIT_S"] ?? "") ?? 300
                if limitS < 60 { limitS = 60 }
                if limitS > 1_800 { limitS = 1_800 }
                startedAt = ProcessInfo.processInfo.systemUptime
                wallStart = Date()
                rng = FeedStressRNG(state: seed == 0 ? 1 : seed)
                plan = Self.parsePlan(env["OPV_FEED_STRESS_INJECT"] ?? "")
                let stamp = ISO8601DateFormatter().string(from: wallStart)
                    .replacingOccurrences(of: ":", with: "")
                runId = "s\(seed)-\(stamp)"
                return true
            }
            guard first else { return }
            prepareDirectory()
            writeHeader()
            registerNotifications()
            startTicker()
            Task { @MainActor in
                self.originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
                UIApplication.shared.isIdleTimerDisabled = true
                self.attachProbe()
            }
        }

        func noteSourceObserved(videoPackets: Int, accessUnits: Int) {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.sourceObservedPackets += max(0, videoPackets)
                $0.sourceObservedAUs += max(0, accessUnits)
                if videoPackets > 0 || accessUnits > 0 { $0.lastSourceObservedAt = now }
            }
        }

        func noteSourceDelivered(videoPackets: Int, accessUnits: Int) {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.sourceDeliveredPackets += max(0, videoPackets)
                $0.sourceDeliveredAUs += max(0, accessUnits)
                if videoPackets > 0 || accessUnits > 0 { $0.lastSourceDeliveredAt = now }
            }
        }

        func noteDecodeSubmit() {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.decodeSubmits += 1
                $0.lastDecodeSubmitAt = now
            }
        }

        func noteDecoded() {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.decodedOutputs += 1
                $0.lastDecodedAt = now
            }
        }

        func notePresent(file: StaticString) {
            let fileID = "\(file)"
            if fileID.contains("LiveMonitorFx") {
                noteMetalPresent()
            } else if fileID.contains("HevcDecoder") {
                noteIdentityEnqueue()
            } else {
                let now = ProcessInfo.processInfo.systemUptime
                lock.withLock {
                    $0.presents += 1
                    $0.lastPresentAt = now
                }
            }
        }

        func noteIdentityEnqueue() {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.presentEnqueue += 1
                $0.presents += 1
                $0.lastEnqueueAt = now
                $0.lastPresentAt = now
            }
        }

        func noteMetalPresent() {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                $0.presentMetal += 1
                $0.presents += 1
                $0.lastMetalAt = now
                $0.lastPresentAt = now
            }
        }

        var injectionDidActivate: Bool {
            lock.withLock { $0.injectDrops > 0 || $0.injectSilences > 0 || $0.silenceConsumed }
        }

        func shouldDropPacket(seq: UInt64) -> Bool {
            let now = ProcessInfo.processInfo.systemUptime
            let dropped = lock.withLock { state -> Bool in
                guard plan.configured, injectActive(state, now: now) else { return false }
                state.packetIndex &+= 1
                if state.burstLeft > 0 {
                    state.burstLeft -= 1
                    state.injectDrops += 1
                    return true
                }
                if plan.burstEveryN > 0, plan.burstDropCount > 0,
                    state.packetIndex.isMultiple(of: UInt64(plan.burstEveryN))
                {
                    state.burstLeft = max(0, plan.burstDropCount - 1)
                    state.injectDrops += 1
                    return true
                }
                if plan.lossProbability > 0, rng.nextDouble() < plan.lossProbability {
                    state.injectDrops += 1
                    return true
                }
                _ = seq
                return false
            }
            if dropped { notifyInjectionActivated() }
            return dropped
        }

        func shouldSilenceOutput(now: TimeInterval) -> Bool {
            let silenced = lock.withLock { state -> Bool in
                guard plan.configured, injectActive(state, now: now) else { return false }
                guard plan.outputSilenceMs > 0 else { return false }
                if state.silenceUntil == nil, !state.silenceConsumed {
                    state.silenceUntil = now + TimeInterval(plan.outputSilenceMs) / 1_000
                    state.silenceConsumed = true
                }
                if let until = state.silenceUntil, now < until {
                    state.injectSilences += 1
                    return true
                }
                return false
            }
            if silenced { notifyInjectionActivated() }
            return silenced
        }

        private func notifyInjectionActivated() {
            let first: Bool = lock.withLock { _ in
                if didNotifyInjection { return false }
                didNotifyInjection = true
                return true
            }
            guard first else { return }
            FeedIncidentRuntime.noteTestSource(.faultInjection)
            ReliabilityReporting.noteCurrentTestSource(.faultInjection)
        }

        func snapshotLine() -> String {
            let now = ProcessInfo.processInfo.systemUptime
            let thermal = Self.thermalToken()
            return lock.withLock { state in
                self.refreshHealth(&state, now: now, thermal: thermal)
                return self.render(state, now: now, thermal: thermal)
            }
        }

        func handleDarwin(_ name: String) {
            io.async { [weak self] in
                self?.dispatchDarwin(name)
            }
        }

        private func injectActive(_ state: FeedStressCounters, now: TimeInterval) -> Bool {
            guard let armed = state.injectArmedAt else { return false }
            if now - armed > 8 { return false }
            guard let healthy = state.healthySince, now - healthy >= 30 else { return false }
            return true
        }

        private func refreshHealth(
            _ state: inout FeedStressCounters, now: TimeInterval, thermal: String
        ) {
            let sourceFresh =
                state.lastSourceDeliveredAt.map { now - $0 < 2.0 } == true
                || state.lastSourceObservedAt.map { now - $0 < 2.0 } == true
            let decodeFresh = state.lastDecodedAt.map { now - $0 < 2.0 } == true
            if sourceFresh && decodeFresh {
                if state.healthySince == nil { state.healthySince = now }
            } else if state.injectArmedAt == nil {
                state.healthySince = nil
            }
            if thermal == "serious" || thermal == "critical" {
                state.halt = "thermal"
            } else if now - startedAt >= limitS {
                state.halt = "time"
            }
            if let armed = state.injectArmedAt, now - armed > 8 {
                state.injectArmedAt = nil
            }
        }

        private func render(_ state: FeedStressCounters, now: TimeInterval, thermal: String)
            -> String
        {
            let age = { (mark: TimeInterval?) -> Int in
                guard let mark else { return -1 }
                return Int((now - mark) * 1_000)
            }
            let hook =
                (state.decodedOutputs > 0 || state.presents > 0
                    || state.sourceObservedPackets > 0)
                ? "counters" : "none"
            let armed = injectActive(state, now: now) ? 1 : 0
            return [
                "v=1",
                "srcObsP=\(state.sourceObservedPackets)",
                "srcObsAU=\(state.sourceObservedAUs)",
                "srcDelP=\(state.sourceDeliveredPackets)",
                "srcDelAU=\(state.sourceDeliveredAUs)",
                "decIn=\(state.decodeSubmits)",
                "decOut=\(state.decodedOutputs)",
                "pres=\(state.presents)",
                "presEnqueue=\(state.presentEnqueue)",
                "presMetal=\(state.presentMetal)",
                "presClaim=admission",
                "srcHz=\(String(format: "%.1f", state.windowSourceHz))",
                "decHz=\(String(format: "%.1f", state.windowDecodeHz))",
                "presHz=\(String(format: "%.1f", state.windowPresentHz))",
                "srcAgeMs=\(age(state.lastSourceDeliveredAt ?? state.lastSourceObservedAt))",
                "srcObsAgeMs=\(age(state.lastSourceObservedAt))",
                "decAgeMs=\(age(state.lastDecodedAt))",
                "presAgeMs=\(age(state.lastPresentAt))",
                "enqueueAgeMs=\(age(state.lastEnqueueAt))",
                "metalAgeMs=\(age(state.lastMetalAt))",
                "therm=\(thermal)",
                "rec=\(state.recording ? 1 : 0)",
                "hook=\(hook)",
                "inj=\(armed)",
                "injDrop=\(state.injectDrops)",
                "injSil=\(state.injectSilences)",
                "delayLimited=1",
                "halt=\(state.halt.isEmpty ? "0" : state.halt)",
                "t=\(String(format: "%.1f", now - startedAt))",
                "run=\(runId)",
                "family=\(state.cameraFamily)",
                "reconnect=\(state.reconnect)",
            ].joined(separator: " ")
        }

        private func startTicker() {
            let timer = DispatchSource.makeTimerSource(queue: io)
            timer.schedule(deadline: .now() + .milliseconds(400), repeating: .seconds(1))
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            timer.resume()
            self.timer = timer
        }

        private func tick() {
            Task { @MainActor [weak self] in
                self?.publishSnapshot()
            }
        }

        @MainActor
        private func publishSnapshot() {
            if probe == nil || probe?.superview == nil {
                attachProbe()
            }
            let recording = AppModelDiagnosticsAnchor.model?.session.status.isRecording ?? false
            let family: String = {
                if let model = AppModelDiagnosticsAnchor.model {
                    return String(describing: model.session.bodyFamily)
                }
                return "unknown"
            }()
            captureBaselineIfNeeded()
            reconnectPocket4ProIfNeeded()
            lock.withLock { state in
                state.recording = recording
                if family != "unknown" { state.cameraFamily = family }
                let srcDelta = state.sourceDeliveredPackets - self.prevDeliveredPackets
                let decDelta = state.decodedOutputs - self.prevDecoded
                let presDelta = state.presents - self.prevPresents
                state.windowSourceHz = Double(max(0, srcDelta))
                state.windowDecodeHz = Double(max(0, decDelta))
                state.windowPresentHz = Double(max(0, presDelta))
                self.prevDeliveredPackets = state.sourceDeliveredPackets
                self.prevDecoded = state.decodedOutputs
                self.prevPresents = state.presents
            }
            let line = snapshotLine()
            probe?.accessibilityValue = line
            append("snapshots.ndjson", line + "\n")
            let halt = lock.withLock { $0.halt }
            if !halt.isEmpty {
                runTeardown(reason: halt)
            }
        }

        @MainActor
        private func reconnectPocket4ProIfNeeded() {
            guard !reconnectAttempted else { return }
            guard let model = AppModelDiagnosticsAnchor.model else { return }
            if model.session.phase == .live {
                reconnectAttempted = true
                lock.withLock { $0.reconnect = "live" }
                return
            }
            let matches = model.savedCameras.filter(Self.isPocket4Pro)
            if matches.count != 1 {
                reconnectAttempted = true
                lock.withLock { $0.reconnect = matches.isEmpty ? "none" : "ambiguous" }
                return
            }
            reconnectAttempted = true
            lock.withLock { $0.reconnect = "requested" }
            model.reconnect(matches[0])
        }

        private static func isPocket4Pro(_ camera: SavedCamera) -> Bool {
            if let id = camera.modelId, id == 0x0022 { return true }
            let name = camera.modelName.lowercased().replacingOccurrences(of: " ", with: "")
            return name.contains("pocket4p") || name.contains("4pro")
        }

        @MainActor
        private func captureBaselineIfNeeded() {
            guard !baseline.captured else { return }
            guard let model = AppModelDiagnosticsAnchor.model else { return }
            guard model.session.phase == .live else { return }
            let status = model.session.status
            guard status.isoIndex != nil || status.iso > 0 else { return }
            baseline = FeedStressBaseline(
                captured: true,
                isoIndex: status.isoIndex,
                whiteBalance: status.whiteBalance,
                peaking: model.assist.isOn(.peaking),
                falseColor: model.assist.isOn(.falseColor),
                waveform: model.assist.isOn(.waveform),
                lut: model.assist.isOn(.lut)
            )
        }

        private func registerNotifications() {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passUnretained(self).toOpaque()
            var names = feedStressScenarios.flatMap {
                [feedStressBeginPrefix + $0, feedStressPassPrefix + $0, feedStressFailPrefix + $0]
            }
            names.append(contentsOf: [
                feedStressArmInject, feedStressDisarmInject, feedStressTeardown,
            ])
            for name in names {
                CFNotificationCenterAddObserver(
                    center, observer, feedStressDarwinCallback, name as CFString, nil,
                    .deliverImmediately)
            }
        }

        private func dispatchDarwin(_ name: String) {
            if name.hasPrefix(feedStressBeginPrefix) {
                mark("begin", String(name.dropFirst(feedStressBeginPrefix.count)), result: "")
            } else if name.hasPrefix(feedStressPassPrefix) {
                mark("end", String(name.dropFirst(feedStressPassPrefix.count)), result: "pass")
            } else if name.hasPrefix(feedStressFailPrefix) {
                mark("end", String(name.dropFirst(feedStressFailPrefix.count)), result: "fail")
            } else if name == feedStressArmInject {
                armInject()
            } else if name == feedStressDisarmInject {
                lock.withLock { $0.injectArmedAt = nil }
                mark("inject", "disarm", result: "")
            } else if name == feedStressTeardown {
                runTeardown(reason: "test")
            }
        }

        private func armInject() {
            let now = ProcessInfo.processInfo.systemUptime
            let ok = lock.withLock { state -> Bool in
                guard self.plan.configured else { return false }
                guard let healthy = state.healthySince, now - healthy >= 30 else { return false }
                state.injectArmedAt = now
                state.silenceUntil = nil
                state.silenceConsumed = false
                return true
            }
            mark("inject", ok ? "arm" : "arm-rejected", result: ok ? "pass" : "fail")
        }

        private func mark(_ kind: String, _ scenario: String, result: String) {
            let now = ProcessInfo.processInfo.systemUptime
            let line = snapshotLine()
            let row =
                "{\"t\":\(String(format: "%.1f", now - startedAt)),\"kind\":\"\(kind)\",\"scenario\":\"\(scenario)\",\"result\":\"\(result)\"}\n"
            append("events.ndjson", row)
            append("events.ndjson", "{\"snapshot\":\"\(line)\"}\n")
        }

        @MainActor
        private func attachProbe() {
            if let probe, probe.superview != nil { return }
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
                let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            else { return }
            let probe = FeedStressProbeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            probe.isUserInteractionEnabled = false
            probe.backgroundColor = .clear
            probe.isAccessibilityElement = true
            probe.accessibilityIdentifier = "feed.stress.snapshot"
            probe.accessibilityLabel = "Feed stress snapshot"
            probe.accessibilityValue = snapshotLine()
            window.addSubview(probe)
            self.probe = probe
        }

        private func runTeardown(reason: String) {
            let already = lock.withLock { state -> Bool in
                if self.restored { return true }
                self.restored = true
                if state.halt.isEmpty { state.halt = reason }
                state.injectArmedAt = nil
                state.burstLeft = 0
                state.silenceUntil = nil
                return false
            }
            if already { return }
            timer?.cancel()
            timer = nil
            Task { @MainActor in
                Self.stopMotionAndRestore(self.baseline)
                if let original = self.originalIdleTimerDisabled {
                    UIApplication.shared.isIdleTimerDisabled = original
                }
            }
            writeSummary(reason: reason)
        }

        @MainActor
        private static func stopMotionAndRestore(_ baseline: FeedStressBaseline) {
            guard let model = AppModelDiagnosticsAnchor.model else { return }
            let session = model.session
            session.endGimbalStick(cancelMove: true)
            guard baseline.captured else { return }
            if ProcessInfo.processInfo.environment["OPV_FEED_STRESS_RECORD"] == "1",
                session.status.isRecording
            {
                session.pressShutter()
            }
            session.endGimbalStick(cancelMove: true)
            if let iso = baseline.isoIndex, iso != session.status.isoIndex {
                session.setISO(iso)
            }
            if let wb = baseline.whiteBalance {
                switch wb.mode {
                case .auto:
                    session.setWhiteBalanceAuto(tint: wb.tint)
                case .custom:
                    session.setWhiteBalanceCustom(kelvin: wb.kelvin, tint: wb.tint)
                }
            }
            let wanted: [(LiveAssistTool, Bool)] = [
                (.peaking, baseline.peaking),
                (.falseColor, baseline.falseColor),
                (.waveform, baseline.waveform),
                (.lut, baseline.lut),
            ]
            for (tool, on) in wanted where model.assist.isOn(tool) != on {
                model.assist.toggle(tool)
            }
        }

        private func prepareDirectory() {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first
            guard let docs else { return }
            let dir = docs.appendingPathComponent("feed-stress", isDirectory: true)
                .appendingPathComponent(runId, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
        }

        private func writeHeader() {
            let bundle = Bundle.main
            let version =
                bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? ""
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            let revision =
                bundle.object(forInfoDictionaryKey: "OPCSourceRevision") as? String ?? "unknown"
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let osText = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            let inject =
                (ProcessInfo.processInfo.environment["OPV_FEED_STRESS_INJECT"] ?? "")
                .replacingOccurrences(of: "\"", with: "")
            let body = """
                {"seed":\(seed),"limitS":\(Int(limitS)),"runId":"\(runId)","app":"\(version)","build":"\(build)","revision":"\(revision)","os":"\(osText)","hw":"\(Self.machineIdentifier)","inject":"\(inject)","delayLimited":true,"presClaim":"admission","started":"\(ISO8601DateFormatter().string(from: wallStart))"}\n
                """
            append("header.json", body)
        }

        private func writeSummary(reason: String) {
            let line = snapshotLine()
            let body = """
                {"reason":"\(reason)","elapsedS":\(String(format: "%.1f", ProcessInfo.processInfo.systemUptime - startedAt)),"final":"\(line)"}\n
                """
            append("summary.json", body)
        }

        private func append(_ name: String, _ text: String) {
            guard let directory else { return }
            let url = directory.appendingPathComponent(name)
            io.async {
                let data = Data(text.utf8)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: url)
                }
            }
        }

        private static func parsePlan(_ raw: String) -> FeedStressPlan {
            var plan = FeedStressPlan()
            guard !raw.isEmpty else { return plan }
            plan.configured = true
            for part in raw.split(separator: ",") {
                let item = part.split(separator: ":", maxSplits: 3).map(String.init)
                guard let key = item.first else { continue }
                switch key {
                case "loss":
                    plan.lossProbability = Double(item.dropFirst().first ?? "0") ?? 0
                case "burst":
                    plan.burstDropCount = Int(item.dropFirst().first ?? "0") ?? 0
                    plan.burstEveryN = Int(item.dropFirst().dropFirst().first ?? "0") ?? 0
                case "outputSilenceMs":
                    plan.outputSilenceMs = Int(item.dropFirst().first ?? "0") ?? 0
                default:
                    break
                }
            }
            plan.lossProbability = min(max(plan.lossProbability, 0), 0.5)
            plan.burstDropCount = min(max(plan.burstDropCount, 0), 24)
            plan.burstEveryN = min(max(plan.burstEveryN, 0), 400)
            plan.outputSilenceMs = min(max(plan.outputSilenceMs, 0), 4_000)
            return plan
        }

        private static func thermalToken() -> String {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "nominal"
            case .fair: return "fair"
            case .serious: return "serious"
            case .critical: return "critical"
            @unknown default: return "unknown"
            }
        }

        private static var machineIdentifier: String {
            var info = utsname()
            uname(&info)
            return withUnsafePointer(to: &info.machine) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
        }
    }

    private final class FeedStressProbeView: UIView {}

#endif
