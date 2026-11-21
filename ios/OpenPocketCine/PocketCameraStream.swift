import Foundation
import OpenCineAppKitApple
import OpenCineApple
import OpenCineCore
import OpenCineDJI
import OpenCineDJIApple
import os

/// "1080p from camera" for a Pocket: the camera publishes its own stream to this phone over a
/// saved shared network, and the shared live stream relays it. The camera is released from
/// monitoring the way Multiview takes the radio, and handed back to the normal connect flow when
/// the stream ends.
@MainActor final class PocketCameraStreamSource: LiveStreamCameraSource {
    private static let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "camera-stream")

    private let camera: () -> DjiAppleSighting?
    private let savedNetworks: () -> [SharedNetworkStore.Network]
    private let hostPath: any StationHostPath
    private let release: () -> Void
    private let resume: () -> Void
    /// The body chosen at Go live; kept while the monitoring session lets go of it.
    private var streaming: DjiAppleSighting?
    /// The last body that was connected, so the choice stays while the camera is between sessions.
    private var lastCamera: DjiAppleSighting?
    private var publisher: DJICameraStreamPublisher?

    init(
        camera: @escaping () -> DjiAppleSighting?,
        savedNetworks: @escaping () -> [SharedNetworkStore.Network] = MultiviewNetworkStore.savedNetworks,
        hostPath: any StationHostPath,
        release: @escaping () -> Void, resume: @escaping () -> Void
    ) {
        self.camera = camera
        self.savedNetworks = savedNetworks
        self.hostPath = hostPath
        self.release = release
        self.resume = resume
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
        if streaming == nil {
            streaming = body
            release()
            // Let the monitoring link to the camera close before another link opens.
            try await Task.sleep(for: .seconds(2))
        }
        guard let saved = saved(network) else { throw LiveStreamCameraError.refused("network not saved") }
        if saved.hotspot {
            // The hotspot's bridge appears only once a client joins; iOS always serves it here.
            return hostPath.address(hotspot: true) ?? "172.20.10.1"
        }
        var address = try await hostPath.join(StationNetwork(ssid: saved.ssid, password: saved.password, hotspot: false))
        for _ in 0..<40 where address == nil {
            try await Task.sleep(for: .milliseconds(500))
            address = hostPath.address(hotspot: false)
        }
        guard let address else { throw LiveStreamCameraError.refused("phone not on \(saved.ssid)") }
        return address
    }

    func startPublishing(to url: String, network: LiveStreamNetwork, frameRate: Int) async throws {
        guard let camera = streaming, let saved = saved(network) else {
            throw LiveStreamCameraError.refused("no camera")
        }
        let log: (String) -> Void = { Self.log.info("\($0, privacy: .public)") }
        let publisher: DJICameraStreamPublisher
        do {
            publisher = try await DJICameraStreamPublisher.connect(camera: camera, host: .pocket, log: log)
        } catch {
            Self.log.error("camera stream: Bluetooth connect failed: \(String(describing: error), privacy: .public)")
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
        resume()
    }
}
