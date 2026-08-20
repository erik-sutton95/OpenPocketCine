import Foundation
import CoreBluetooth
import os
import OpenPocketViewCore

/// A camera seen in a BLE scan.
struct FoundCamera: Identifiable, Sendable {
    let id: UUID            // peripheral identifier (CoreBluetooth hides the MAC)
    let name: String
    let model: CameraModel
    let modelId: Int?

    /// A nameless first advert of a saved Nano must not resolve as a Pocket.
    func enriched(from saved: SavedCamera?) -> FoundCamera {
        let next = FoundCameraIdentity.enriched(
            name: name, modelId: modelId,
            savedName: saved?.advertisedName, savedModelId: saved?.modelId)
        guard next.name != name || next.modelId != modelId else { return self }
        return FoundCamera(
            id: id,
            name: next.name,
            model: CameraModel.resolve(modelId: next.modelId, name: next.name),
            modelId: next.modelId
        )
    }
}

/// CoreBluetooth side of the connection spine: scan for Osmo cameras, connect GATT
/// (service fff0, notify fff4, write fff5), arm app-pairing, write DUML frames to fff5 (paced,
/// without-response), and surface inbound frames. A faithful port of the Osmosis BLE flow.
///
/// Runs on a physical iPhone only — the Simulator has no Bluetooth. Not yet hardware-tested.
/// ponytail: one delegate class, callbacks/streams over any framework. Not @MainActor — the
/// CoreBluetooth delegate requirements are nonisolated; the manager's delegate queue is the main
/// queue (nil below), so every callback and every continuation still lands on the main thread.
final class BleLink: NSObject {
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    /// The only peripheral whose GATT events may drive pairing / GetSSID / notify.
    private var selectedId: UUID?
    private var fff4: CBCharacteristic?
    private var fff5: CBCharacteristic?

    private let serviceUUID = CBUUID(string: BleConstants.serviceFFF0)
    private let fff4UUID = CBUUID(string: BleConstants.charFFF4)
    private let fff5UUID = CBUUID(string: BleConstants.charFFF5)

    private var foundStream: AsyncStream<FoundCamera>.Continuation?
    private var frameStream: AsyncStream<Duml.Frame>.Continuation?
    private var poweredOn: CheckedContinuation<Void, Never>?
    private var readyCont: CheckedContinuation<Void, Error>?
    private var connectTimeout: DispatchWorkItem?
    private var pairingArmed = false
    private var fff4NotifySettled = false
    private var fff5NotifySettled = false

    private var writeQueue: [Data] = []
    private var writing = false
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "ble")

    /// iOS `connect` has no public deadline and will sit on the next advertisement for ~30 s.
    /// A working GATT + notify + arm-pairing handshake finishes in 1–3 s; 10 s is fail-fast.
    private static let connectDeadline: TimeInterval = 10

    /// Inbound DUML frames from the camera (notifications on fff4/fff5).
    /// A new stream per `startFrameRouter` — finishing the lazy stream on disconnect
    /// left reconnect iterating a dead AsyncStream (pairing sat until timeout).
    var frames: AsyncStream<Duml.Frame> {
        AsyncStream { cont in
            frameStream?.finish()
            frameStream = cont
        }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)   // delegate on the main queue
    }

    func waitUntilPoweredOn() async {
        if central.state == .poweredOn { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if central.state == .poweredOn {
                c.resume()
            } else {
                poweredOn?.resume()
                poweredOn = c
            }
        }
    }

    /// Scan until cancelled; yields each distinct DJI camera as it's discovered.
    /// Unfiltered (Pocket 3 omits manufacturer data). Duplicates stay on until a peripheral
    /// classifies — the first advert is often nameless, and `AllowDuplicates: false` would
    /// hide the later named packet for the rest of the scan.
    func scan() -> AsyncStream<FoundCamera> {
        selectedId = nil
        disconnectForeignDJI(keeping: nil)
        peripherals.removeAll()
        return AsyncStream { cont in
            self.foundStream?.finish()
            self.foundStream = cont
            self.yieldAlreadyConnected()
            self.central.scanForPeripherals(withServices: nil,
                                            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func stopScan() { central.stopScan() }

    /// Connect GATT and resume once fff4/fff5 are notifying and pairing is armed.
    /// Scan stays up until `didConnect` — iOS uses the next advertisement to finish the link.
    func connect(_ camera: FoundCamera) async throws {
        guard let p = peripherals[camera.id] else { throw BleError.gone }
        selectedId = camera.id
        disconnectForeignDJI(keeping: camera.id)
        connected = p
        pairingArmed = false
        fff4NotifySettled = false
        fff5NotifySettled = false
        fff4 = nil; fff5 = nil
        p.delegate = self
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // A second connect (or disconnect mid-handshake) used to overwrite readyCont and leak
            // the previous continuation — SWIFT TASK CONTINUATION MISUSE on connect(_:).
            if let old = readyCont { old.resume(throwing: BleError.gone) }
            readyCont = c
            armConnectDeadline(p)
            central.connect(p, options: nil)
        }
    }

    /// Queue a DUML frame for fff5. Writes are without-response and paced ~120 ms apart, because
    /// back-to-back writes to fff5 drop (same constraint Osmosis hit on Android).
    func send(_ frame: Duml.Frame) {
        if !Self.isSessionPing(frame) {
            log.debug("fff5 write 0x\(String(format: "%02x/%02x", frame.cmdSet, frame.cmdId), privacy: .public) \(frame.payload.count)B")
        }
        writeQueue.append(Data(Duml.encode(frame)))
        pumpWrites()
    }

    /// `0x00/0x2B` is the 1 Hz BLE session ping. Logging it drowns the Xcode console.
    private static func isSessionPing(_ frame: Duml.Frame) -> Bool {
        frame.cmdSet == 0x00 && frame.cmdId == 0x2B
    }

    private func pumpWrites() {
        guard !writing, !writeQueue.isEmpty, let fff5, let p = connected,
            BlePeerPolicy.acceptsGATT(from: p.identifier, selected: selectedId)
        else { return }
        writing = true
        p.writeValue(writeQueue.removeFirst(), for: fff5, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.writing = false
            self?.pumpWrites()
        }
    }

    func disconnect() {
        finishConnect(BleError.gone)
        if let p = connected { central.cancelPeripheralConnection(p) }
        connected = nil; selectedId = nil; fff4 = nil; fff5 = nil
        pairingArmed = false; fff4NotifySettled = false; fff5NotifySettled = false
        disconnectForeignDJI(keeping: nil)
    }

    private func isSelected(_ peripheral: CBPeripheral) -> Bool {
        BlePeerPolicy.acceptsGATT(from: peripheral.identifier, selected: selectedId)
    }

    /// One DJI GATT at a time. A leftover Pocket link stays notifying and can
    /// answer pairing / GetSSID while we think we tapped the Nano.
    private func disconnectForeignDJI(keeping keep: UUID?) {
        if let current = connected, current.identifier != keep {
            current.delegate = nil
            central.cancelPeripheralConnection(current)
            connected = nil
            fff4 = nil
            fff5 = nil
            pairingArmed = false
            fff4NotifySettled = false
            fff5NotifySettled = false
        }
        for (id, p) in peripherals where id != keep {
            p.delegate = nil
            central.cancelPeripheralConnection(p)
        }
        for p in central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        where p.identifier != keep {
            p.delegate = nil
            central.cancelPeripheralConnection(p)
        }
    }

    enum BleError: LocalizedError {
        case gone, noService, timeout
        var errorDescription: String? {
            switch self {
            case .gone: "camera disappeared"
            case .noService: "camera has no DUML service"
            case .timeout: "Bluetooth connect timed out"
            }
        }
    }

    /// Resume `readyCont` exactly once. Every connect path (success, fail, disconnect, timeout)
    /// goes through here so the continuation cannot leak.
    private func finishConnect(_ error: Error?) {
        connectTimeout?.cancel(); connectTimeout = nil
        guard let c = readyCont else { return }
        readyCont = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    private func armConnectDeadline(_ peripheral: CBPeripheral) {
        connectTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.readyCont != nil else { return }
            self.stopScan()
            self.central.cancelPeripheralConnection(peripheral)
            self.finishConnect(BleError.timeout)
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectDeadline, execute: work)
    }

    /// `setNotifyValue` is a no-op (no callback) when the char has neither notify nor indicate.
    private func requestNotify(_ c: CBCharacteristic, on peripheral: CBPeripheral) {
        if c.properties.contains(.notify) || c.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: c)
        } else if c.uuid == fff4UUID {
            fff4NotifySettled = true
        } else if c.uuid == fff5UUID {
            fff5NotifySettled = true
        }
    }

    /// Cameras iOS already holds (previous session, Settings pairing) show up without waiting
    /// for the next advertisement.
    private func yieldAlreadyConnected() {
        for p in central.retrieveConnectedPeripherals(withServices: [serviceUUID]) {
            let adv: [String: Any] = p.name.map { [CBAdvertisementDataLocalNameKey: $0] } ?? [:]
            guard let camera = classify(p, adv) else { continue }
            if peripherals[p.identifier] == nil {
                peripherals[p.identifier] = p
                foundStream?.yield(camera)
            }
        }
    }
}

extension BleLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { poweredOn?.resume(); poweredOn = nil }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let camera = classify(peripheral, advertisementData) else { return }
        let first = peripherals[peripheral.identifier] == nil
        peripherals[peripheral.identifier] = peripheral
        if first {
            foundStream?.yield(camera)
            return
        }
        // Later advert often adds the BLE name / model the first packet lacked.
        foundStream?.yield(camera)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isSelected(peripheral) else {
            log.info("ble: ignore connect from foreign \(peripheral.identifier, privacy: .public)")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        stopScan()
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isSelected(peripheral) else { return }
        stopScan()
        finishConnect(error ?? BleError.gone)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Cancelling a leftover Pocket must not abort the Nano scan / handshake.
        guard isSelected(peripheral) else {
            log.info("ble: ignore disconnect from foreign \(peripheral.identifier, privacy: .public)")
            return
        }
        stopScan()
        finishConnect(error ?? BleError.gone)
        frameStream?.finish()
        selectedId = nil
    }

    /// Match a DJI Osmo by manufacturer-data company id (or name), decode the model, resolve caps.
    private func classify(_ peripheral: CBPeripheral, _ adv: [String: Any]) -> FoundCamera? {
        let advName = (adv[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        var modelId: Int?
        var isDji = false
        if let mfr = adv[CBAdvertisementDataManufacturerDataKey] as? Data, mfr.count >= 2 {
            let companyId = Int(mfr[0]) | (Int(mfr[1]) << 8)   // little-endian
            if BleConstants.isDjiCompanyId(companyId) {
                isDji = true
                modelId = BleAdvert.modelId([UInt8](mfr.dropFirst(2)))   // strip company id
            }
        }
        // The Pocket 3 often sends no manufacturer data — fall back to the name.
        let nameLooksDji = (advName?.lowercased()).map { n in
            ["osmo", "pocket", "nano", "dji", "action", "xtra", "edge"].contains { n.contains($0) }
        } ?? false
        guard isDji || nameLooksDji else { return nil }
        return FoundCamera(id: peripheral.identifier,
                           name: advName ?? "DJI camera",
                           model: CameraModel.resolve(modelId: modelId, name: advName),
                           modelId: modelId)
    }
}

extension BleLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isSelected(peripheral) else { return }
        if let error { finishConnect(error); return }
        guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            finishConnect(BleError.noService); return
        }
        peripheral.discoverCharacteristics([fff4UUID, fff5UUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isSelected(peripheral) else { return }
        if let error { finishConnect(error); return }
        for c in service.characteristics ?? [] {
            if c.uuid == fff4UUID { fff4 = c; requestNotify(c, on: peripheral) }
            if c.uuid == fff5UUID { fff5 = c; requestNotify(c, on: peripheral) }
        }
        if fff4 == nil || fff5 == nil { finishConnect(BleError.noService) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard isSelected(peripheral) else { return }
        // Wait for both CCCD callbacks (success or fail) so the arm-pairing write does not
        // collide with an in-flight ATT request. Do not require fff5.isNotifying — Osmosis
        // skips a missing CCCD, and requiring it hung "Connecting (Bluetooth)…" forever.
        if characteristic.uuid == fff4UUID { fff4NotifySettled = true }
        if characteristic.uuid == fff5UUID { fff5NotifySettled = true }
        guard !pairingArmed, fff4NotifySettled, fff5NotifySettled, let fff4, fff4.isNotifying else { return }
        pairingArmed = true
        peripheral.writeValue(Data([0x01, 0x00]), for: fff4, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isSelected(peripheral) else { return }
        if characteristic.uuid == fff4UUID {   // the arm-pairing write completed -> ready
            finishConnect(error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isSelected(peripheral) else { return }
        guard let value = characteristic.value else { return }
        for frame in DumlTransport.scanFrames([UInt8](value)) {
            if !Self.isSessionPing(frame) {
                log.debug("notify 0x\(String(format: "%02x/%02x", frame.cmdSet, frame.cmdId), privacy: .public) flags=\(frame.flags) \(frame.payload.count)B")
            }
            frameStream?.yield(frame)
        }
    }
}
