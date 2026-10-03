import Foundation
import OpenCineDJIApple
import OpenPocketViewCore

// Transitional source names resolve to the shared native implementations.
typealias BleLink = DjiAppleBluetoothLink
typealias DatalinkDriver = DjiAppleDatalink
typealias WiFiJoiner = DjiAppleWiFiJoiner
typealias SharedWiFiPath = DjiAppleSharedWiFiPath
typealias FoundCamera = DjiAppleSighting

extension DjiAppleTransportHost {
    /// Each connection receives its own value; logging retains Pocket's existing redaction/storage.
    static var pocket: Self {
        var host = Self(logSubsystem: "com.opencapture.openpocketcine", journal: { ControlLiveLog.line($0) },
            localNetworkEvidence: { evidence, source in
                LocalNetworkAccess.note(evidence == .allowed ? .allowed : .denied, source: source)
            }, bluetoothDenied: StartupConnectionCopy.bluetoothDenied,
            bluetoothOff: StartupConnectionCopy.bluetoothOff,
            bluetoothNotReady: StartupConnectionCopy.bluetoothNotReady)
        #if DEBUG
            host.debugVideo = DjiAppleVideoTestHooks(
                sourceObserved: { FeedStressAutomation.noteSourceObserved(videoPackets: $0, accessUnits: $1) },
                sourceDelivered: { FeedStressAutomation.noteSourceDelivered(videoPackets: $0, accessUnits: $1) },
                shouldDropPacket: { FeedStressAutomation.shouldDropPacket(seq: $0) })
        #endif
        return host
    }
}

extension DjiAppleSighting {
    /// The app's saved record can enrich a nameless first advert without changing native identity.
    func enriched(from saved: SavedCamera?) -> Self {
        let next = FoundCameraIdentity.enriched(name: name, modelId: modelId,
            savedName: saved?.advertisedName, savedModelId: saved?.modelId)
        guard next.name != name || next.modelId != modelId else { return self }
        return Self(id: id, name: next.name,
            model: CameraModel.resolve(modelId: next.modelId, name: next.name,
                brand: CameraBrand.of(address: nil, name: next.name)), modelId: next.modelId)
    }
}

extension FeedIncidentQueue {
    init(_ queue: DjiAppleQueueObservation) {
        self.init(bytes: queue.bytes, count: queue.count, ageMilliseconds: queue.ageMilliseconds ?? 0,
            incompleteAccessUnits: queue.incompleteAccessUnits, drops: queue.drops)
    }
}

/// Permission classification stays typed; branded operator copy remains in app composition.
func djiConnectionFailureDescription(_ error: Error, fallback: String? = nil) -> String {
    if case DatalinkDriver.DatalinkError.localNetworkDenied = error {
        return StartupConnectionCopy.localNetworkDenied
    }
    return fallback ?? (error as? LocalizedError)?.errorDescription ?? "\(error)"
}
