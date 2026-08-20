import Darwin
import Foundation
import Network
import NetworkExtension
import OpenPocketViewCore
import os

/// Joins the camera's SoftAP with the credentials read over BLE. Requires the
/// `com.apple.developer.networking.HotspotConfiguration` entitlement. The camera is an
/// internet-less AP at 192.168.2.1; iOS keeps cellular as the default route, so sockets that need
/// the camera must pin themselves to Wi-Fi (see DatalinkDriver's NWParameters).
///
/// `apply` success is not "associated with an address". First join is prompt + associate +
/// DHCP; second connect is already on the AP (`alreadyAssociated`) and `192.168.2.x` is there.
enum WiFiJoiner {
    enum JoinError: LocalizedError {
        case failed(String)
        case pathNotReady
        case stillOnOtherBody(String)
        var errorDescription: String? {
            switch self {
            case .failed(let s): s
            case .pathNotReady: "camera Wi-Fi joined but 192.168.2.x never appeared"
            case .stillOnOtherBody(let ssid):
                "couldn't switch from \(ssid) — tap Connect again"
            }
        }
    }

    private static let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "wifi")

    /// Leave the other Osmo SoftAP and join `ssid`. Pocket and Nano share
    /// `192.168.2.1`, so a leftover camera DHCP address is not a stop — apply
    /// the target hotspot and let iOS switch. Do not send the operator to Settings.
    static func joinCameraAP(
        ssid: String,
        passphrase: String,
        wpa3: Bool,
        knownOtherSSIDs: [String],
        persist: Bool = false
    ) async throws {
        var kick = Set(knownOtherSSIDs.filter { !$0.isEmpty && $0 != ssid })
        leave(ssids: Array(kick))
        await leaveOtherOsmoSoftAPs(except: ssid)

        var lastForeign: String?
        for attempt in 1...CameraSoftAPSwitch.maxJoinAttempts {
            try Task.checkCancellation()
            if let foreign = CameraSoftAPSwitch.ssidToKick(
                currentSSID: await currentSSID(), target: ssid)
            {
                log.info(
                    "wifi: kick \(foreign, privacy: .public) then join \(ssid, privacy: .public) #\(attempt)"
                )
                leave(ssid: foreign)
                kick.insert(foreign)
                lastForeign = foreign
            }
            leave(ssids: Array(kick))
            await leaveOtherOsmoSoftAPs(except: ssid)
            try? await Task.sleep(for: .milliseconds(250))
            try await join(ssid: ssid, passphrase: passphrase, wpa3: wpa3, persist: persist)
            try await waitUntilCameraPathReady()
            let now = await currentSSID()
            if CameraSoftAPSwitch.isOnTarget(currentSSID: now, target: ssid) {
                log.info(
                    "wifi: on \(ssid, privacy: .public) (current=\(now ?? "nil", privacy: .public)) #\(attempt)"
                )
                return
            }
            lastForeign = now
            log.info(
                "wifi: still on \(now ?? "?", privacy: .public) after join \(ssid, privacy: .public) — retry"
            )
            if let now { leave(ssid: now) }
        }
        throw JoinError.stillOnOtherBody(lastForeign ?? "other camera")
    }

    static func currentSSID() async -> String? {
#if targetEnvironment(simulator)
        return nil
#else
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            NEHotspotNetwork.fetchCurrent { network in
                cont.resume(returning: network?.ssid)
            }
        }
#endif
    }

    static func join(
        ssid: String,
        passphrase: String,
        wpa3: Bool,
        persist: Bool = false
    ) async throws {
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        // Join-once drops the hotspot when the app leaves the foreground; saved
        // cameras need the config to survive Control Center / background.
        config.joinOnce = !persist
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            NEHotspotConfigurationManager.shared.apply(config) { error in
                if let error = error as NSError? {
                    // "already associated" is success, not a failure.
                    if error.domain == NEHotspotConfigurationErrorDomain,
                       error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                        c.resume(); return
                    }
                    c.resume(throwing: JoinError.failed(error.localizedDescription))
                } else {
                    c.resume()
                }
            }
        }
    }

    /// True when this phone has a DHCP address on the camera AP.
    /// Simulator has no SoftAP — treat as ready so connect UI can still run.
    static func isCameraPathReady() -> Bool {
#if targetEnvironment(simulator)
        return true
#else
        return CameraSoftAP.isPathReady(localIPv4s: ipv4Addresses())
#endif
    }

    /// Block until `192.168.2.2…254` exists. Second connect returns immediately.
    static func waitUntilCameraPathReady(timeout: TimeInterval = 15) async throws {
        if isCameraPathReady() { return }
        log.info("wifi: waiting for 192.168.2.x (first join / DHCP)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if isCameraPathReady() {
                try await Task.sleep(for: .milliseconds(200))
                if isCameraPathReady() {
                    log.info("wifi: camera path ready (\(ipv4Addresses().filter(CameraSoftAP.isAssociatedIPv4).joined(separator: ","), privacy: .public))")
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JoinError.pathNotReady
    }

    static func leave(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    static func leave(ssids: [String]) {
        for ssid in Set(ssids) where !ssid.isEmpty {
            leave(ssid: ssid)
        }
    }

    /// Pocket and Nano SoftAPs are both `192.168.2.1`. Drop every configured
    /// Osmo hotspot except the one we are about to join so iOS cannot stay
    /// on the other body. The other camera can stay powered on.
    static func leaveOtherOsmoSoftAPs(except keep: String) async {
        let configured = await configuredSSIDs()
        let extras = configured.filter { $0 != keep && CameraSoftAP.isOsmoSoftAPSSID($0) }
        if !extras.isEmpty {
            log.info("wifi: removing other Osmo SoftAPs \(extras.joined(separator: ","), privacy: .public)")
            leave(ssids: extras)
        }
    }

    static func configuredSSIDs() async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            NEHotspotConfigurationManager.shared.getConfiguredSSIDs { ssids in
                cont.resume(returning: ssids)
            }
        }
    }

    /// After leaving another body's SoftAP, wait until `192.168.2.x` is gone
    /// so the next join cannot inherit that path.
    static func waitUntilCameraPathGone(timeout: TimeInterval = 6) async {
        if !isCameraPathReady() { return }
        log.info("wifi: waiting for 192.168.2.x to drop after leaving the other AP")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return }
            if !isCameraPathReady() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log.info("wifi: 192.168.2.x still present after leave")
    }

    static func ipv4Addresses() -> [String] {
        interfaceAddresses().map(\.ipv4)
    }

    static func cameraLocalIPv4() -> String? {
        CameraSoftAP.cameraLocalIPv4(in: interfaceAddresses())
    }

    static func cameraInterfaceNames() -> [String] {
        CameraSoftAP.cameraInterfaceNames(in: interfaceAddresses())
    }

    static func interfaceAddresses() -> [CameraSoftAP.InterfaceAddress] {
        var addrs: [CameraSoftAP.InterfaceAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                                 nil, 0, NI_NUMERICHOST)
            if ok == 0 {
                addrs.append(.init(name: String(cString: ifa.pointee.ifa_name),
                                   ipv4: String(cString: host)))
            }
        }
        return addrs
    }

    /// NWInterface that owns `192.168.2.2…254`. Nil if the SoftAP is not in the
    /// default path — caller still binds `requiredLocalEndpoint` to that IPv4.
    static func resolveCameraInterface(timeout: TimeInterval = 2) async -> NWInterface? {
        let names = Set(cameraInterfaceNames())
        guard !names.isEmpty else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<NWInterface?, Never>) in
            let monitor = NWPathMonitor()
            let q = DispatchQueue(label: "opv.wifi.camera-if")
            var resumed = false
            let finish: (NWInterface?) -> Void = { iface in
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                cont.resume(returning: iface)
            }
            monitor.pathUpdateHandler = { path in
                if let iface = path.availableInterfaces.first(where: { names.contains($0.name) }) {
                    finish(iface)
                }
            }
            monitor.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) {
                let iface = monitor.currentPath.availableInterfaces.first { names.contains($0.name) }
                finish(iface)
            }
        }
    }
}
