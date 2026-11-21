import Foundation
import OpenCineAppKitApple
import OpenCineApple
import OpenCineCore
import OpenCineDJI
import OpenCineDJIApple

/// "1080p from camera" for a Pocket: the camera publishes its own stream to this phone over a
/// saved shared network, and the shared live stream relays it. The camera is released from
/// monitoring the way Multiview takes the radio, and handed back to the normal connect flow when
/// the stream ends.
@MainActor final class PocketCameraStreamSource: LiveStreamCameraSource {
    private let camera: () -> DjiAppleSighting?
    private let savedNetworks: () -> [SharedNetworkStore.Network]
    private let hostPath: any StationHostPath
    private let release: () -> Bool
    private let resume: () -> Void
    private let confirmHotspot: (String) async -> Bool
    private let settle: () async throws -> Void
    /// The operator's answer about a hotspot that is off, kept for the run so a retry does not ask again.
    private var hotspotAnswer: Bool?
    /// The body chosen at Go live; kept while the monitoring session lets go of it.
    private var streaming: DjiAppleSighting?
    /// The last body that was connected, so the choice stays while the camera is between sessions.
    private var lastCamera: DjiAppleSighting?
    private var publisher: DJICameraStreamPublisher?

    init(
        camera: @escaping () -> DjiAppleSighting?,
        savedNetworks: @escaping () -> [SharedNetworkStore.Network] = MultiviewNetworkStore.savedNetworks,
        hostPath: any StationHostPath,
        release: @escaping () -> Bool, resume: @escaping () -> Void,
        confirmHotspot: @escaping (String) async -> Bool,
        settle: @escaping () async throws -> Void
    ) {
        self.camera = camera
        self.savedNetworks = savedNetworks
        self.hostPath = hostPath
        self.release = release
        self.resume = resume
        self.confirmHotspot = confirmHotspot
        self.settle = settle
    }

    /// Lets the monitoring link to the camera close before another link opens.
    static func settleAfterRelease() async throws {
        try await Task.sleep(for: .seconds(2))
    }

    private static func log(_ line: String) {
        ControlLiveLog.line("camera stream: \(line)")
    }

    private var body: DjiAppleSighting? {
        if let streaming { return streaming }
        if let current = camera() { lastCamera = current }
        return lastCamera
    }

    /// Only bodies proven on hardware: experimental ones need an experimental switch this app does
    /// not have yet.
    var publishing: CameraStreamPublishing? {
        guard let body, let capability = DJIStreamPublishing.capability(for: body.model), !capability.experimental
        else { return nil }
        return capability
    }

    var networks: [LiveStreamNetwork] {
        let saved = savedNetworks()
        return (saved.filter(\.hotspot) + saved.filter { !$0.hotspot }).map {
            LiveStreamNetwork(id: Self.id($0), name: $0.ssid, isHotspot: $0.hotspot)
        }
    }

    private static func id(_ network: SharedNetworkStore.Network) -> String {
        "\(network.ssid)|\(network.hotspot ? "hotspot" : "wifi")"
    }

    private func saved(_ network: LiveStreamNetwork) -> SharedNetworkStore.Network? {
        savedNetworks().first { Self.id($0) == network.id }
    }

    func prepare(_ network: LiveStreamNetwork) async throws -> String {
        guard let saved = saved(network) else { throw LiveStreamCameraError.refused("network not saved") }
        // A hotspot that is off: ask first, as the normal hotspot connect does, before the camera
        // spends its join retries on a network that is not there.
        if saved.hotspot, hostPath.address(hotspot: true) == nil {
            if hotspotAnswer == nil { hotspotAnswer = await confirmHotspot(saved.ssid) }
            guard hotspotAnswer == true else { throw LiveStreamCameraError.refused("hotspot off") }
        }
        if streaming == nil {
            guard let body else { throw LiveStreamCameraError.refused("no camera") }
            guard release() else { throw LiveStreamCameraError.refused("camera busy") }
            streaming = body
            try await settle()
        }
        if saved.hotspot {
            // The hotspot's bridge appears only once a client joins; iOS always serves it here.
            return hostPath.address(hotspot: true) ?? "172.20.10.1"
        }
        // `join` already waits for the phone to be on this network; any other address is not it.
        guard let address = try await hostPath.join(
            StationNetwork(ssid: saved.ssid, password: saved.password, hotspot: false))
        else { throw LiveStreamCameraError.refused("phone not on \(saved.ssid)") }
        return address
    }

    func startPublishing(to url: String, network: LiveStreamNetwork, frameRate: Int) async throws {
        guard let camera = streaming, let saved = saved(network) else {
            throw LiveStreamCameraError.refused("no camera")
        }
        let publisher: DJICameraStreamPublisher
        do {
            publisher = try await DJICameraStreamPublisher.connect(camera: camera, host: .pocket, log: Self.log)
        } catch {
            Self.log("Bluetooth connect failed: \(error)")
            throw LiveStreamCameraError.refused("bluetooth")
        }
        self.publisher = publisher
        let codec: LivestreamCommands.Codec = publishing?.preferredCodec == .hevc ? .hevc : .h264
        do {
            try await publisher.start(
                url: url, ssid: saved.ssid, password: saved.password, frameRate: frameRate, codec: codec)
        } catch DJICameraStreamError.noReply {
            throw LiveStreamCameraError.notResponding
        } catch let error as DJICameraStreamError {
            throw LiveStreamCameraError.refused("\(error)")
        }
    }

    func endPublishing() async {
        let publisher = publisher
        self.publisher = nil
        await publisher?.end()
    }

    func finished() {
        streaming = nil
        hotspotAnswer = nil
        resume()
    }
}

/// Whether the camera's own monitor is on screen: while its stream runs, and after the run until
/// the operator has read the notice it ended with (the camera's monitor is the only place it shows).
struct CameraMonitorPresence: Equatable {
    private(set) var shown = false

    mutating func update(active: Bool, endPending: Bool) {
        shown = active || (shown && endPending)
    }
}
