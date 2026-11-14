import Foundation
import OpenCineApple
import OpenCineCore
import OpenCineDJIApple
import OpenPocketViewCore

/// The DJI member link Pocket supplies (spec's settled call): each tile's own datalink, identity
/// check, live view start, watchdog repair and Auto LUT, behind OpenCine's `MultiviewMemberLink`.
/// The session keeps what the shared coordinator will own: guards, address reservations,
/// discovery, the rejoin budget, the path-loss rule and the tile's copy and control host, which
/// it derives from the link's `onStatus`.
extension MultiviewSession.Tile: MultiviewMemberLink {
    typealias Camera = DjiAppleSighting

    var session: any OpenCineCore.CameraSession { control }

    var isPublishing: Bool { publishing }

    /// Longer than any DJI repair's own bound (the decoder repair's two 16 s windows, the UDP
    /// renegotiation's 15 s station deadline), so the race never cuts a DJI repair short.
    var repairDeadline: Duration { .seconds(60) }

    func probe(_ address: String, on network: StationNetwork) async -> Bool {
        guard let local = SharedWiFiPath().address(hotspot: network.hotspot) else { return false }
        return await DjiAppleNetworkDiscovery().probe(address, localAddress: local)
    }

    func open(
        _ camera: DjiAppleSighting, at address: String, expecting identity: [UInt8]?,
        on network: StationNetwork
    ) async throws -> [UInt8] {
        driver?.close()
        driver = nil
        controlLinkUp = false
        responses.removeAll()
        recordingObservation = nil
        publishing = false
        previewStarted = nil
        decoder.onHandoffNeedsIDR = nil
        pendingAssistHandoff = false
        enableSends = 0
        lastEnable = .distantPast
        if hasPicture { decoder.beginIDRHold() } else { decoder.reset() }
        onStatus?(.opening)
        let driver = DjiAppleDatalink(
            port: UInt16(camera.model.datalinkPort), tcpPoke: camera.model.tcpPoke,
            pairingToken: camera.model.pairingToken,
            stationHost: address, stationHotspot: network.hotspot,
            subscriptionKeys: Commands.subscriptionKeys(for: camera.model), host: .pocket)
        self.driver = driver
        driver.onStatusFrame = { [weak self, weak driver] frame in
            guard let tile = self, let driver, tile.driver === driver else { return }
            if frame.flags & 128 != 0 {
                if tile.responses.count > 128 { tile.responses.removeAll() }
                tile.responses[frame.seq] = frame
            }
            guard tile.controlLinkUp else { return }
            tile.updateSettings(frame)
            tile.liveModel?.session.receiveMultiview(frame)
            if frame.cmdSet == 2 && frame.cmdId == 0x80 && frame.payload.count >= 13 {
                var status = CameraStatus()
                CameraStatusDecoder.apply(frame, to: &status, model: camera.model)
                tile.recordingObservation = (status.isRecording, Date())
            }
        }
        try await driver.open(identityOnly: true)
        let identitySeq = driver.send(Commands.getWifiSsid(id: 0))
        let deadline = Date().addingTimeInterval(8)
        while responses[identitySeq] == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let reply = responses.removeValue(forKey: identitySeq),
            reply.cmdSet == 7, reply.cmdId == 7, identity.map({ reply.payload == $0 }) ?? true
        else {
            throw MultiviewFailure.message(
                "This network connection did not identify the selected camera.")
        }
        return reply.payload
    }

    func startPreview(_ camera: DjiAppleSighting) async throws {
        guard let driver else { throw CancellationError() }
        driver.completeRegistration()
        controlLinkUp = true
        onStatus?(.controlling)
        liveModel?.session.updateMultiview(camera: camera, driver: driver, status: latestSettings)
        ControlLiveLog.line("multiview: station camera identity verified")
        decoder.onHandoffNeedsIDR = { [weak self, weak driver] in
            guard let tile = self, let driver, tile.driver === driver, tile.controlLinkUp else {
                return
            }
            tile.pendingAssistHandoff = true
            tile.recoverAssistHandoff()
        }
        bindPreviewInput(driver)
        let nanoGate = camera.model.usesNanoLiveViewGate
        if nanoGate { driver.send(Commands.nanoLiveViewGate(start: true)) }
        if camera.model.sendsLiveViewPrepare {
            driver.send(Commands.liveViewPrepare())
        }
        driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
        lastEnable = Date()
        enableSends = 1
        publishing = true
        previewStarted = Date()
        if !hasPicture { onStatus?(.awaitingPicture) }
    }

    func keepalive() async { driver?.keepalive() }

    func close() {
        driver?.close()
        driver = nil
        controlLinkUp = false
    }

    var autoLUT: MultiviewAutoLUT { autoLUT(for: autoLUTSource) }

    var autoLUTSource: LUTSource {
        LUTResolver.builtInAutoSource(
            colorMode: settings.colorMode, profile: camera?.model.captureProfile?.looks)
    }

    func autoLUT(for source: LUTSource) -> MultiviewAutoLUT {
        let conversion: String?
        if case .dji(let lut) = source { conversion = lut.title } else { conversion = nil }
        return MultiviewAutoLUT(colorMode: settings.colorMode?.label, conversion: conversion)
    }

    /// DJI's feed watchdog ladder on this tile's own link, once a second while it publishes.
    func repair(_ context: MultiviewRepairContext) -> MultiviewRepairStep {
        guard let driver else { return .handled }
        let now = Date()
        guard let snapshot = watchdogSnapshot(now: now, pathReady: context.pathReady) else {
            return .handled
        }
        if checkForegroundDecoder && FeedWatchdog.udpReceiveAlive(snapshot) {
            checkForegroundDecoder = false
            if decoder.displayLayer.status == .failed
                || decoder.displayLayer.requiresFlushToResumeDecoding
            {
                decoder.prepareAfterForeground()
                decoder.noteCompressedDiscontinuity()
                ControlLiveLog.line(
                    "multiview: foreground display resumed; watchdog owns references")
                return .handled
            }
        }
        let previousRecovery = recovery
        let action = recovery.action(snapshot)
        if decoder.awaitingIDR, decoder.canReleaseIDRHold,
            FeedWatchdog.shouldReleaseIDRHold(
                awaitingIDR: true, udpReceiveAlive: FeedWatchdog.udpReceiveAlive(snapshot),
                secondsSinceLastEnable: snapshot.secondsSinceLastEnable,
                hasPresentedPicture: decoder.lastPresentedAt != nil)
        {
            decoder.endIDRHold()
        }
        guard action != .none else { return .healthy }
        ControlLiveLog.line("multiview: repair action=\(action)")
        onStatus?(.reconnecting)
        if action == .resendLiveViewEnable {
            guard decoder.isPresentationReady, let camera else {
                recovery = previousRecovery
                return .handled
            }
            driver.reRegister()
            driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
            lastEnable = now
            enableSends += 1
            decoder.beginIDRHold()
            return .handled
        }
        if action == .rebuildVTSession {
            guard
                decoder.rebuildPresentationIfNeeded(
                    referenceLossOnly: snapshot.referenceRecoveryNeeded)
            else {
                recovery = previousRecovery
                return .handled
            }
            return .repair { [weak self, weak driver] in
                guard let tile = self, let driver else { return .done }
                let requestedAt = Date()
                var sentAt: Date?
                while context.running(), !Task.isCancelled, tile.driver === driver,
                    context.applicationActive(), context.foregroundUnchanged(),
                    Self.decoderRepairHasTime(requestedAt: requestedAt, sentAt: sentAt)
                {
                    if let sentAt, tile.hasFreshPicture(since: sentAt) {
                        tile.recovery.watchdog = FeedWatchdog()
                        ControlLiveLog.line("multiview: decoder repair restored fresh picture")
                        return .done
                    }
                    if sentAt == nil, context.applicationActive(), tile.decoder.isPresentationReady,
                        context.pathAvailable(), let camera = tile.camera
                    {
                        driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
                        tile.pendingAssistHandoff = false
                        tile.lastEnable = Date()
                        tile.enableSends += 1
                        sentAt = tile.lastEnable
                        ControlLiveLog.line("multiview: decoder repair enable, socket retained")
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard context.running(), !Task.isCancelled, tile.driver === driver else {
                    return .done
                }
                return tile.finishDecoderRepair(
                    previous: previousRecovery, sentAt: sentAt,
                    applicationActive: context.applicationActive(),
                    foregroundUnchanged: context.foregroundUnchanged()) ? .rejoin : .done
            }
        }
        if action == .fullSessionRejoin { return .repair { .rejoin } }
        return .repair { [weak self] in
            guard let tile = self else { return .done }
            do {
                try await driver.rebuildUDP(reason: "multiview watchdog")
                guard context.running(), tile.driver === driver, !Task.isCancelled,
                    let camera = tile.camera
                else { return .done }
                driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
                tile.lastEnable = Date()
                tile.enableSends += 1
                tile.decoder.beginIDRHold()
                return .done
            } catch {
                return context.running() && !Task.isCancelled ? .rejoin : .done
            }
        }
    }
}
