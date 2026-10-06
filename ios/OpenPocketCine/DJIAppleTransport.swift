import Foundation
import OpenCineDJIApple
import struct OpenCineCore.SavedCamera
import OpenPocketViewCore

// Transitional source names resolve to the shared native implementations.

extension DjiAppleTransportHost {
    /// Each connection receives its own value; logging retains Pocket's existing redaction/storage.
    static var pocket: Self {
        var host = Self(logSubsystem: "com.opencapture.openpocketcine", journal: { ControlLiveLog.line($0) },
            bluetoothGattJournal: persistPocketBluetoothGatt,
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

/// Preserve the existing raw GATT file separately from the app's redacted control journal.
private func persistPocketBluetoothGatt(_ text: String) {
    DispatchQueue.global(qos: .utility).async {
        guard
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("ble-gatt.log")
        else { return }
        let row = Data("\(ISO8601DateFormatter().string(from: Date())) \(text)\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: row)
            }
        } else {
            try? row.write(to: url)
        }
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
    if case DjiAppleDatalink.DatalinkError.localNetworkDenied = error {
        return StartupConnectionCopy.localNetworkDenied
    }
    return fallback ?? (error as? LocalizedError)?.errorDescription ?? "\(error)"
}
