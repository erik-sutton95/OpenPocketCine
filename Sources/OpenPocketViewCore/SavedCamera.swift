import Foundation
import OpenCineCore

/// How a saved body is reached (#406). Every record has camera Wi-Fi. Wi-Fi (a router)
/// and Hotspot (this phone's) are OpenZCine-style extra setups that move the camera off
/// its own access point onto that network.
public enum CameraConnectionSetup: String, Codable, CaseIterable, Sendable {
    case cameraWiFi
    case wifi
    case phoneHotspot

    public var title: String {
        switch self {
        case .cameraWiFi: "Camera Wi-Fi"
        case .wifi: "Wi-Fi"
        case .phoneHotspot: "Hotspot"
        }
    }

    /// The camera leaves its access point (station role) for this setup.
    public var movesCamera: Bool { self != .cameraWiFi }
}

/// SoftAP creds are per body. A session-global last-SSID would join the
/// Pocket AP when connecting a Nano (both use `192.168.2.1`).
/// A live BLE name that differs from the cached SSID is a renamed SoftAP
/// (#257) — join that name; do not keep the old Keychain SSID.
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

    /// BLE local name when it is usable as a SoftAP SSID. Nameless first
    /// adverts (`DJI camera`) are not — Pocket BLE name follows the Wi-Fi name.
    public static func liveAdvertisedSSID(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !FoundCameraIdentity.isGenericName(trimmed) else { return nil }
        return trimmed
    }

    public static func resolve(
        cameraId: UUID,
        savedSSID: String?,
        memory: Memory?,
        keychainSSID: String?,
        keychainPassword: String?,
        advertisedName: String? = nil
    ) -> Result {
        let memoryMatches = memory?.cameraId == cameraId
        let memSsid = memoryMatches ? memory?.ssid : nil
        let memPass = memoryMatches ? memory?.password : nil
        let cachedSsid = [memSsid, keychainSSID, savedSSID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let password = [memPass, keychainPassword]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let live = liveAdvertisedSSID(advertisedName)
        let ssid: String?
        if let live, let cachedSsid, live != cachedSsid {
            ssid = live
        } else {
            ssid = cachedSsid
        }
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

    /// GetSSID fallback / SoftAP join must not use another saved body's SSID: its camera Wi-Fi
    /// network or its advertised name.
    public static func isSSIDOwnedByAnotherCamera(
        _ ssid: String, cameraId: String, saved: [SavedCamera]
    ) -> Bool {
        let needle = ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        func same(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
        return saved.contains { other in
            other.id != cameraId
                && (same(other.advertisedName)
                    || same(other.routes.first { $0.kind == .cameraAccessPoint }?.network))
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
        if isGenericName(incomingName) {
            return isGenericName(existingName) && existingModelId == nil && incomingModelId != nil
        }
        if isGenericName(existingName) { return true }
        let existing = existingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incomingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing != incoming { return true }
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
