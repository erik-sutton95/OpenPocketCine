import OpenCineAppKitApple
import OpenCineApple
import OpenCineCore
import OpenCineDJI
import OpenCineStreaming

/// Live streaming's host values: the keychain service, the route from the active connection setup,
/// the live feed's shape and the clean picture tap on the live decoder. Only "1080p from camera"
/// (`PocketCameraStreamSource`) sends camera commands, to start and end the camera's own stream.
extension AppModel {
    func makeLiveStream() -> LiveStreamCoordinator {
        LiveStreamCoordinator(
            host: LiveStreamHost(
                keychainService: "com.opencapture.openpocketcine.live-stream",
                route: { [weak self] in self?.liveStreamRoute },
                source: { [weak self] in self?.liveStreamSource },
                attachPicture: { [weak self] in self?.session.decoder.setCleanPictureTap($0) },
                // No permission gate of its own: the plain system request, after Go live is confirmed.
                microphoneAccess: { [weak self] in
                    self?.voiceControl.disarm()
                    return await LiveStreamHost.systemMicrophoneAccess()
                },
                camera: PocketCameraStreamSource(
                    camera: { [weak self] in self?.session.connectedCamera }, hostPath: SharedWiFiPath(),
                    release: { [weak self] in self?.releaseCameraForStream() ?? false },
                    resume: { [weak self] in self?.closeMultiview() },
                    confirmHotspot: { [weak self] network in await self?.askHotspot(network) ?? false },
                    settle: PocketCameraStreamSource.settleAfterRelease)))
    }

    /// The route only while a camera shows a live picture; the camera's own Wi-Fi blocks streaming.
    var liveStreamRoute: StreamConnectionRoute? {
        guard session.phase == .live else { return nil }
        return StreamConnectionRoute(session.connectionSetup.routeKind)
    }

    /// The wireless feed is 720p (upright when the camera is turned); its rate is not stated.
    var liveStreamSource: StreamSourceFormat? {
        guard session.phase == .live else { return nil }
        return session.isVerticalPicture
            ? StreamSourceFormat(width: 720, height: 1280, frameRate: nil)
            : StreamSourceFormat(width: 1280, height: 720, frameRate: nil)
    }
}

extension CameraConnectionSetup {
    /// The shared route vocabulary for this setup.
    var routeKind: RouteKind {
        switch self {
        case .cameraWiFi: .cameraAccessPoint
        case .wifi: .infrastructureNetwork
        case .phoneHotspot: .phoneHotspot
        }
    }
}
