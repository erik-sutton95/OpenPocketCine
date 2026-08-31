import CoreHaptics
import GameController
import OpenPocketViewCore
import UIKit

/// Live-monitor gamepad: discussion #159 map. Left stick gimbal, L2/R2 analog
/// zoom, L1/R1 zoom-chip, Cross records, Circle recenters, Square 180,
/// Triangle tracks, D-pad ISO/shutter.
@MainActor
final class GimbalGamepadBridge {
    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var padActive = false
    private var zoomActive = false
    private var zoomAnchor = 1.0
    private var zoomCurrent = 1.0
    private var zoomY = 0.0
    private var zoomPump: Task<Void, Never>?
    private var aDown = false
    private var bDown = false
    private var xDown = false
    private var yDown = false
    private var l1Down = false
    private var r1Down = false
    private var dpadUp = false
    private var dpadDown = false
    private var dpadLeft = false
    private var dpadRight = false
    private var haptics: GamepadLimitHaptics?

    func attach(model: AppModel) {
        detach()
        self.model = model
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .GCControllerDidConnect, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.bindControllers() }
            },
            center.addObserver(
                forName: .GCControllerDidDisconnect, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.bindControllers() }
            },
        ]
        bindControllers()
    }

    func detach() {
        noteBlocked()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        haptics?.detach()
        haptics = nil
        model?.gamepadConnected = false
        model = nil
        aDown = false
        bDown = false
        xDown = false
        yDown = false
        l1Down = false
        r1Down = false
        dpadUp = false
        dpadDown = false
        dpadLeft = false
        dpadRight = false
        zoomActive = false
    }

    func noteBlocked() {
        if padActive {
            padActive = false
            model?.gimbalPadHeld = false
            model?.session.endGimbalStick()
        }
        stopZoomPump()
        if zoomActive {
            zoomActive = false
            model?.session.endZoomPinch()
        }
    }

    func pulseLimit(
        _ contact: GimbalLimitWatch.Contact, panSign: Double, tiltSign: Double, enabled: Bool
    ) {
        guard enabled, !contact.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        haptics?.pulse(contact: contact, panSign: panSign, tiltSign: tiltSign)
    }

    private var canDrive: Bool {
        guard let model else { return false }
        if model.session.isLocked { return false }
        if model.session.isBrowsingMedia { return false }
        if model.liveOperatorPanel != nil { return false }
        if model.isEditingChrome { return false }
        return model.isLive && model.session.datalink != nil
    }

    private func bindControllers() {
        let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        let gamepad = controller?.extendedGamepad
        haptics?.detach()
        haptics = controller.map(GamepadLimitHaptics.init)
        for item in GCController.controllers() {
            item.extendedGamepad?.valueChangedHandler = nil
        }
        let connected = gamepad != nil
        if connected != model?.gamepadConnected {
            model?.gamepadConnected = connected
            if let model {
                model.session.controlNote = connected ? "Gamepad connected" : "Gamepad disconnected"
            }
        }
        guard let gamepad else {
            noteBlocked()
            return
        }
        gamepad.valueChangedHandler = { [weak self] pad, _ in
            Task { @MainActor in self?.handle(pad) }
        }
        handle(gamepad)
    }

    private func edge(
        _ down: Bool, was: inout Bool, action: GamepadOperatorAction, on model: AppModel
    ) {
        if down, !was { model.session.handleGamepadAction(action) }
        was = down
    }

    private func handle(_ pad: GCExtendedGamepad) {
        guard canDrive, let model else {
            noteBlocked()
            aDown = pad.buttonA.isPressed
            bDown = pad.buttonB.isPressed
            xDown = pad.buttonX.isPressed
            yDown = pad.buttonY.isPressed
            l1Down = pad.leftShoulder.isPressed
            r1Down = pad.rightShoulder.isPressed
            dpadUp = pad.dpad.up.isPressed
            dpadDown = pad.dpad.down.isPressed
            dpadLeft = pad.dpad.left.isPressed
            dpadRight = pad.dpad.right.isPressed
            return
        }
        edge(pad.buttonA.isPressed, was: &aDown, action: GamepadOperatorMap.face(.a), on: model)
        edge(pad.buttonB.isPressed, was: &bDown, action: GamepadOperatorMap.face(.b), on: model)
        edge(pad.buttonX.isPressed, was: &xDown, action: GamepadOperatorMap.face(.x), on: model)
        edge(pad.buttonY.isPressed, was: &yDown, action: GamepadOperatorMap.face(.y), on: model)
        edge(
            pad.leftShoulder.isPressed, was: &l1Down, action: GamepadOperatorMap.shoulder(.left),
            on: model)
        edge(
            pad.rightShoulder.isPressed, was: &r1Down, action: GamepadOperatorMap.shoulder(.right),
            on: model)
        edge(pad.dpad.up.isPressed, was: &dpadUp, action: GamepadOperatorMap.dpad(.up), on: model)
        edge(
            pad.dpad.down.isPressed, was: &dpadDown, action: GamepadOperatorMap.dpad(.down),
            on: model)
        edge(
            pad.dpad.left.isPressed, was: &dpadLeft, action: GamepadOperatorMap.dpad(.left),
            on: model)
        edge(
            pad.dpad.right.isPressed, was: &dpadRight, action: GamepadOperatorMap.dpad(.right),
            on: model)

        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        let rest =
            GimbalStick.analogCurve(x) == 0 && GimbalStick.analogCurve(y) == 0
        if rest {
            if padActive {
                padActive = false
                model.gimbalPadHeld = false
                model.session.endGimbalStick()
            }
        } else {
            padActive = true
            model.gimbalPadHeld = true
            model.session.updateGimbalStick(
                x: x, y: y, sensitivity: model.gimbalStickSensitivity,
                assistMirror: model.assist.isVisible(.mirror))
        }

        zoomY = CamFov.triggerZoomAxis(
            left: Double(pad.leftTrigger.value),
            right: Double(pad.rightTrigger.value))
        if GimbalStick.linearThrow(zoomY) == 0 {
            stopZoomPump()
            if zoomActive {
                zoomActive = false
                model.session.endZoomPinch()
            }
        } else {
            if !zoomActive {
                zoomAnchor = model.session.zoomReadout
                zoomCurrent = zoomAnchor
                zoomActive = true
            }
            startZoomPump()
        }
    }

    private func startZoomPump() {
        guard zoomPump == nil else { return }
        zoomPump = Task { @MainActor [weak self] in
            let delay = Duration.milliseconds(
                Int((CamFov.zoomStepInterval * 1_000).rounded(.up)))
            self?.applyZoom(dt: CamFov.zoomStepInterval)
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                self.applyZoom(dt: dt)
            }
        }
    }

    private func stopZoomPump() {
        zoomPump?.cancel()
        zoomPump = nil
    }

    private func applyZoom(dt: TimeInterval) {
        guard zoomActive, let model, canDrive else {
            stopZoomPump()
            if zoomActive {
                zoomActive = false
                model?.session.endZoomPinch()
            }
            return
        }
        if model.session.zoomColorHopPending {
            let mag = zoomCurrent / max(zoomAnchor, CamFov.minFactor)
            model.session.updateZoomPinch(magnification: mag)
            return
        }
        zoomCurrent = CamFov.zoomStep(
            current: zoomCurrent, y: zoomY, dt: dt, max: model.session.zoomMax)
        let mag = zoomCurrent / max(zoomAnchor, CamFov.minFactor)
        model.session.updateZoomPinch(magnification: mag)
    }
}

@MainActor
private final class GamepadLimitHaptics {
    private var defaultEngine: CHHapticEngine?
    private var leftEngine: CHHapticEngine?
    private var rightEngine: CHHapticEngine?

    init(controller: GCController) {
        guard let device = controller.haptics else { return }
        defaultEngine = start(device.createEngine(withLocality: .default))
        leftEngine = start(device.createEngine(withLocality: .leftHandle))
        rightEngine = start(device.createEngine(withLocality: .rightHandle))
    }

    func detach() {
        defaultEngine?.stop(completionHandler: nil)
        leftEngine?.stop(completionHandler: nil)
        rightEngine?.stop(completionHandler: nil)
        defaultEngine = nil
        leftEngine = nil
        rightEngine = nil
    }

    func pulse(contact: GimbalLimitWatch.Contact, panSign: Double, tiltSign: Double) {
        if contact.contains(.pan) {
            if panSign < 0 {
                play(on: leftEngine ?? defaultEngine)
            } else {
                play(on: rightEngine ?? defaultEngine)
            }
        }
        if contact.contains(.tilt) {
            play(on: defaultEngine)
        }
    }

    private func start(_ engine: CHHapticEngine?) -> CHHapticEngine? {
        guard let engine else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    private func play(on engine: CHHapticEngine?) {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
            ], relativeTime: 0)
        do {
            try engine.start()
            let player = try engine.makePlayer(
                with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: 0)
        } catch {}
    }
}
