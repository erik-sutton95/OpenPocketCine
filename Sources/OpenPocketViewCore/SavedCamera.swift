import Foundation

/// One Pocket we’ve already connected to. One record per body — Pocket has a single
/// BLE → camera-AP path, so there are no OpenZCine-style multi-setup chips.
public struct SavedCamera: Codable, Equatable, Identifiable, Sendable {
    /// CoreBluetooth peripheral identifier (iOS hides the BLE MAC).
    public var id: UUID
    /// Advertised BLE local name at last connect (e.g. `OsmoPocket4P-AAAA`).
    public var advertisedName: String
    /// Resolved model display name (e.g. `Osmo Pocket 4 Pro`).
    public var modelName: String
    /// BLE model id when the advert carried one (`0x22` Pocket 4 Pro, `0x19` Nano).
    public var modelId: Int?
    /// Last camera-AP SSID, if we successfully read/joined it.
    public var lastSSID: String?
    public var lastConnectedAt: Date
    /// Operator-chosen name. The advertised name stays on `advertisedName`.
    public var customName: String?

    public init(
        id: UUID,
        advertisedName: String,
        modelName: String,
        lastSSID: String? = nil,
        lastConnectedAt: Date,
        customName: String? = nil,
        modelId: Int? = nil
    ) {
        self.id = id
        self.advertisedName = advertisedName
        self.modelName = modelName
        self.lastSSID = lastSSID
        self.lastConnectedAt = lastConnectedAt
        self.customName = customName
        self.modelId = modelId
    }

    public var displayName: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return advertisedName.isEmpty ? modelName : advertisedName
    }
}

/// SoftAP creds are per body. A session-global last-SSID would join the
/// Pocket AP when connecting a Nano (both use `192.168.2.1`).
public enum CameraWifiResolution {
    public struct Memory: Equatable, Sendable {
        public var cameraId: UUID
        public var ssid: String
        public var password: String

        public init(cameraId: UUID, ssid: String, password: String) {
            self.cameraId = cameraId
            self.ssid = ssid
            self.password = password
        }
    }

    public struct Result: Equatable, Sendable {
        public var ssid: String?
        public var password: String?
        public var source: String
        public var skipBle: Bool
    }

    public static func resolve(
        cameraId: UUID,
        savedSSID: String?,
        memory: Memory?,
        keychainSSID: String?,
        keychainPassword: String?
    ) -> Result {
        let memoryMatches = memory?.cameraId == cameraId
        let memSsid = memoryMatches ? memory?.ssid : nil
        let memPass = memoryMatches ? memory?.password : nil
        let ssid = [memSsid, keychainSSID, savedSSID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let password = [memPass, keychainPassword]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let memoryHit = memoryMatches && !(memSsid ?? "").isEmpty && !(memPass ?? "").isEmpty
        let keychainHit = !(keychainSSID ?? "").isEmpty && !(keychainPassword ?? "").isEmpty
        let source: String
        if memoryHit {
            source = "memory"
        } else if keychainHit {
            source = "keychain"
        } else {
            source = "none"
        }
        let skipBle =
            !(password ?? "").isEmpty && !(ssid ?? "").isEmpty && (memoryHit || keychainHit)
        return Result(ssid: ssid, password: password, source: source, skipBle: skipBle)
    }

    /// GetSSID fallback / SoftAP join must not use another saved body's SSID.
    public static func isSSIDOwnedByAnotherCamera(
        _ ssid: String, cameraId: UUID, saved: [SavedCamera]
    ) -> Bool {
        let needle = ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return saved.contains { other in
            guard other.id != cameraId else { return false }
            if other.lastSSID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == needle
            {
                return true
            }
            return other.advertisedName.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == needle
        }
    }
}

/// First BLE advert is often nameless. Keep the row, then replace it when a
/// later packet carries a real name or model id.
public enum FoundCameraIdentity {
    public static func isGenericName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return true }
        let compact = n.lowercased()
        return compact == "dji camera" || compact == "dji osmo camera"
    }

    public static func shouldReplace(
        existingName: String, existingModelId: Int?,
        incomingName: String, incomingModelId: Int?
    ) -> Bool {
        if isGenericName(existingName), !isGenericName(incomingName) { return true }
        if existingModelId == nil, incomingModelId != nil { return true }
        return false
    }

    /// First advert is often nameless. A saved record of that same peripheral
    /// already knows the body — use it so a Nano tap does not resolve as Pocket.
    public static func enriched(
        name: String,
        modelId: Int?,
        savedName: String?,
        savedModelId: Int?
    ) -> (name: String, modelId: Int?) {
        var nextName = name
        var nextId = modelId
        if isGenericName(nextName), let saved = savedName, !isGenericName(saved) {
            nextName = saved
        }
        if nextId == nil { nextId = savedModelId }
        return (nextName, nextId)
    }

    /// Scan-row title. A nameless first advert still shows Pocket vs Nano from model id.
    public static func listTitle(advertisedName: String, modelName: String) -> String {
        isGenericName(advertisedName) ? modelName : advertisedName
    }

    public static func listSubtitle(advertisedName: String, modelName: String) -> String {
        let family = CameraBodyFamily.resolve(modelId: nil, name: modelName)
        let kind: String
        switch family {
        case .pocket: kind = "Pocket"
        case .nano: kind = "Nano"
        case .other: kind = modelName
        }
        if isGenericName(advertisedName) || advertisedName == modelName {
            return "\(kind) · nearby"
        }
        return "\(kind) · \(modelName) · nearby"
    }
}

/// One DJI GATT at a time. Events from a leftover Pocket must not drive a Nano session.
public enum BlePeerPolicy {
    public static func acceptsGATT(from peripheral: UUID, selected: UUID?) -> Bool {
        guard let selected else { return false }
        return peripheral == selected
    }
}

/// Canonicalization and list edits for saved Pocket records. Persistence stays in the shell
/// (UserDefaults on iOS, SharedPreferences later on Android) so the core stays I/O-free.
public enum SavedCameras {
    /// Newest-first, one row per peripheral id. Keeps a prior custom name when a reconnect
    /// upserts the same body.
    public static func upserting(_ camera: SavedCamera, into records: [SavedCamera])
        -> [SavedCamera]
    {
        var merged = camera
        if let existing = records.first(where: { $0.id == camera.id }) {
            if merged.customName == nil { merged.customName = existing.customName }
            if merged.lastSSID == nil { merged.lastSSID = existing.lastSSID }
            if merged.advertisedName.isEmpty { merged.advertisedName = existing.advertisedName }
            if merged.modelId == nil { merged.modelId = existing.modelId }
        }
        let others = records.filter { $0.id != camera.id }
        return canonicalized([merged] + others)
    }

    public static func removing(_ id: UUID, from records: [SavedCamera]) -> [SavedCamera] {
        canonicalized(records.filter { $0.id != id })
    }

    public static func renaming(_ id: UUID, to name: String?, in records: [SavedCamera])
        -> [SavedCamera]
    {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = (trimmed?.isEmpty == false) ? trimmed : nil
        return canonicalized(
            records.map { record in
                guard record.id == id else { return record }
                var updated = record
                updated.customName = custom
                return updated
            })
    }

    public static func canonicalized(_ records: [SavedCamera]) -> [SavedCamera] {
        var seen = Set<UUID>()
        var unique: [SavedCamera] = []
        for record in records {
            guard seen.insert(record.id).inserted else { continue }
            unique.append(record)
        }
        return unique.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
    }
}

/// Empty store → first-pair wizard; otherwise the saved-camera home. Matches OpenZCine’s
/// `CameraStartupPolicy.launchDestination`.
public enum CameraStartupDestination: Equatable, Sendable {
    case addCamera
    case savedCameras
}

public enum CameraStartupPolicy {
    public static func launchDestination(savedCameras: [SavedCamera]) -> CameraStartupDestination {
        SavedCameras.canonicalized(savedCameras).isEmpty ? .addCamera : .savedCameras
    }
}

extension ConnectionPhase {
    /// Pocket first-pair wizard step (1...4): BLE scan → approve → join Wi-Fi → datalink.
    public var pocketWizardStep: Int {
        switch self {
        case .idle, .scanning, .failed: 1
        case .connectingGatt, .pairing, .awaitingApproval: 2
        case .readingWifiCreds, .joiningWifi: 3
        case .openingDatalink, .live: 4
        }
    }

    public static let pocketWizardStepCount = 4
}
