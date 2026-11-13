import Foundation
import GameController
import Combine

@MainActor
final class ControllerInputManager: ObservableObject {
    @Published private(set) var state = InputStateComponent()
    @Published private(set) var controllerStatusText: String = "No Controller"
    @Published private(set) var isUsingVirtualController: Bool = false
    @Published private(set) var recentLogs: [String] = []
    @Published var deadZone: Float = 0.10
    @Published var responseExponent: Float = 1.80

    private var activeController: GCController?
    private var virtualController: GCVirtualController?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    // Previous-tick button states for edge detection & input logging
    private var prevLB = false
    private var prevRB = false
    private var prevA = false
    private var pendingBoostRequest = false
    private var prevB = false
    private var prevX = false
    private var prevY = false
    private var prevDpadUp = false
    private var prevDpadDown = false
    private var prevDpadLeft = false
    private var prevDpadRight = false
    private var prevMenu = false
    private var prevOptions = false
    private var prevPrimaryFire = false
    private var prevSecondaryFire = false

    init() {
        InputStateComponent.registerComponent()
        setupNotifications()
        refreshControllers()
    }

    private func setupNotifications() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let name = (notification.object as? GCController)?.vendorName ?? "Controller"
            MainActor.assumeIsolated {
                self?.appendLog("Connected: \(name)")
                self?.refreshControllers()
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let name = (notification.object as? GCController)?.vendorName ?? "Controller"
            MainActor.assumeIsolated {
                self?.appendLog("Disconnected: \(name)")
                self?.refreshControllers()
            }
        }

        GCController.startWirelessControllerDiscovery {}
    }

    private func refreshControllers() {
        let allControllers = GCController.controllers()
        let virtualGC = virtualController?.controller
        let physicalControllers = allControllers.filter { $0 !== virtualGC && $0.extendedGamepad != nil }

        if let physical = physicalControllers.first {
            // Physical pad found: disconnect touch fallback if active.
            if let vc = virtualController {
                vc.disconnect()
                virtualController = nil
                isUsingVirtualController = false
            }
            activeController = physical
            let vendor = physical.vendorName ?? "Game Controller"
            controllerStatusText = "\(vendor)"
        } else if let vc = virtualGC {
            activeController = vc
            isUsingVirtualController = true
            controllerStatusText = "Touch Virtual Pad"
        } else {
            activeController = nil
            isUsingVirtualController = false
            controllerStatusText = "Connect Pad (or tap Touch Pad)"
        }
    }

    private func startVirtualControllerFallback() {
        guard virtualController == nil else { return }
        let config = GCVirtualController.Configuration()
        config.elements = [
            GCInputLeftThumbstick,
            GCInputRightThumbstick,
            GCInputButtonA,
            GCInputButtonB,
            GCInputButtonX,
            GCInputButtonY,
            GCInputLeftShoulder,
            GCInputRightShoulder,
            GCInputLeftTrigger,
            GCInputRightTrigger,
            GCInputDirectionPad,
        ]
        let vc = GCVirtualController(configuration: config)
        virtualController = vc
        isUsingVirtualController = true
        controllerStatusText = "Touch Virtual Pad (Fallback)"
        vc.connect { [weak self] error in
            MainActor.assumeIsolated {
                if let error {
                    self?.appendLog("Virtual pad error: \(error.localizedDescription)")
                } else {
                    self?.activeController = vc.controller
                    self?.appendLog("Touch Virtual Pad ready")
                }
            }
        }
    }

    func toggleVirtualController() {
        if let vc = virtualController {
            vc.disconnect()
            virtualController = nil
            isUsingVirtualController = false
            activeController = nil
            controllerStatusText = "No Controller (Touch Pad Hidden)"
            appendLog("Touch Virtual Pad hidden")
        } else {
            startVirtualControllerFallback()
        }
    }

    func setThrottle(_ value: Float) {
        state.throttle = min(1.0, max(0.0, value))
        let pct = Int((state.throttle * 100.0).rounded())
        appendLog("[HUD] Throttle set to \(pct)%")
    }

    func toggleFlightAssist() {
        state.flightAssistEnabled.toggle()
        appendLog("[HUD] Flight Assist: \(state.flightAssistEnabled ? "ON" : "OFF")")
    }

    func requestBoost() {
        pendingBoostRequest = true
        appendLog("[HUD] Boost requested")
    }

    /// Polls the active controller on each simulation tick and updates `state`.
    func pollTick(deltaTime: TimeInterval) -> InputStateComponent {
        var next = state
        // Reset single-tick edge triggers
        next.boostTriggered = pendingBoostRequest
        pendingBoostRequest = false
        next.targetAheadTriggered = false
        next.nextSubsystemTriggered = false
        next.galaxyMapTriggered = false
        next.pipSYS = false
        next.pipENG = false
        next.pipWEP = false
        next.pipReset = false
        next.panelNavigation = nil
        next.pauseTriggered = false
        next.cameraToggleTriggered = false

        guard let pad = activeController?.extendedGamepad else {
            state = next
            return next
        }

        let dt = Float(min(max(deltaTime, 0.0), 0.1))
        let lbHeld = pad.leftShoulder.isPressed
        next.isModifierHeld = lbHeld

        if lbHeld != prevLB {
            let lbName = pad.leftShoulder.localizedName ?? "LB"
            appendLog(lbHeld ? "[\(lbName)] Modifier HELD" : "[\(lbName)] Modifier RELEASED")
            prevLB = lbHeld
        }

        let rbPressed = pad.rightShoulder.isPressed
        if rbPressed && !prevRB {
            let rbName = pad.rightShoulder.localizedName ?? "RB"
            next.cameraToggleTriggered = true
            appendLog("[\(rbName)] Toggle Camera View")
        }
        prevRB = rbPressed

        // Stick raw readings with dead-zone + response curve
        let lx = InputStateComponent.applyStickCurve(pad.leftThumbstick.xAxis.value, deadZone: deadZone, exponent: responseExponent)
        let ly = InputStateComponent.applyStickCurve(pad.leftThumbstick.yAxis.value, deadZone: deadZone, exponent: responseExponent)
        let rx = InputStateComponent.applyStickCurve(pad.rightThumbstick.xAxis.value, deadZone: deadZone, exponent: responseExponent)
        let ry = InputStateComponent.applyStickCurve(pad.rightThumbstick.yAxis.value, deadZone: deadZone, exponent: responseExponent)

        if lbHeld {
            // Hold LB modifier layer:
            // Left stick -> Lateral + vertical thrust
            // Right stick -> Look around cockpit
            next.pitch = 0.0
            next.roll = 0.0
            next.yaw = 0.0
            next.lateralThrust = lx
            next.verticalThrust = ly
            next.lookYaw = rx
            next.lookPitch = ry
        } else {
            // Default layer:
            // Left stick -> Pitch / roll
            // Right stick -> Yaw / vertical thrust
            next.pitch = ly
            next.roll = lx
            next.yaw = rx
            next.verticalThrust = ry
            next.lateralThrust = 0.0
            next.lookYaw = 0.0
            next.lookPitch = 0.0
        }

        // RT / LT: Primary/secondary fire (Default) vs Throttle up/down (Hold LB)
        let rtVal = pad.rightTrigger.value
        let ltVal = pad.leftTrigger.value

        if lbHeld {
            next.primaryFireValue = 0.0
            next.secondaryFireValue = 0.0
            next.primaryFireHeld = false
            next.secondaryFireHeld = false
            next.throttleDelta = rtVal - ltVal
            if abs(next.throttleDelta) > 0.05 {
                next.throttle = min(1.0, max(0.0, next.throttle + next.throttleDelta * dt * 0.65))
            }
        } else {
            next.throttleDelta = 0.0
            next.primaryFireValue = rtVal
            next.secondaryFireValue = ltVal
            next.primaryFireHeld = rtVal > 0.25
            next.secondaryFireHeld = ltVal > 0.25

            if next.primaryFireHeld && !prevPrimaryFire {
                appendLog("[RT] Primary Fire")
            }
            if next.secondaryFireHeld && !prevSecondaryFire {
                appendLog("[LT] Secondary Fire")
            }
            prevPrimaryFire = next.primaryFireHeld
            prevSecondaryFire = next.secondaryFireHeld
        }

        // Face buttons (A, B, X, Y)
        let aPressed = pad.buttonA.isPressed
        if aPressed && !prevA {
            let glyph = pad.buttonA.localizedName ?? "A"
            if lbHeld {
                next.hardpointsDeployed.toggle()
                appendLog("[LB + \(glyph)] Hardpoints: \(next.hardpointsDeployed ? "DEPLOYED" : "RETRACTED")")
            } else {
                next.boostTriggered = true
                appendLog("[\(glyph)] Boost!")
            }
        }
        prevA = aPressed

        let bPressed = pad.buttonB.isPressed
        if bPressed && !prevB {
            let glyph = pad.buttonB.localizedName ?? "B"
            if lbHeld {
                next.landingGearDeployed.toggle()
                appendLog("[LB + \(glyph)] Landing Gear: \(next.landingGearDeployed ? "DOWN" : "UP")")
            } else {
                next.flightAssistEnabled.toggle()
                appendLog("[\(glyph)] Flight Assist: \(next.flightAssistEnabled ? "ON" : "OFF")")
            }
        }
        prevB = bPressed

        let xPressed = pad.buttonX.isPressed
        if xPressed && !prevX {
            let glyph = pad.buttonX.localizedName ?? "X"
            if lbHeld {
                next.nextSubsystemTriggered = true
                appendLog("[LB + \(glyph)] Next Subsystem")
            } else {
                next.targetAheadTriggered = true
                appendLog("[\(glyph)] Target Ahead")
            }
        }
        prevX = xPressed

        let yPressed = pad.buttonY.isPressed
        if yPressed && !prevY {
            let glyph = pad.buttonY.localizedName ?? "Y"
            if lbHeld {
                next.cargoScoopDeployed.toggle()
                appendLog("[LB + \(glyph)] Cargo Scoop: \(next.cargoScoopDeployed ? "OPEN" : "CLOSED")")
            } else {
                next.galaxyMapTriggered = true
                appendLog("[\(glyph)] Galaxy / System Map")
            }
        }
        prevY = yPressed

        // D-pad: Power pips (Default) vs Cockpit panel navigation (Hold LB)
        let dUp = pad.dpad.up.isPressed
        if dUp && !prevDpadUp {
            if lbHeld {
                next.panelNavigation = .up
                appendLog("[LB + D-Up] Cockpit Panel UP")
            } else {
                next.pipENG = true
                appendLog("[D-Up] +1 Pip ENG")
            }
        }
        prevDpadUp = dUp

        let dDown = pad.dpad.down.isPressed
        if dDown && !prevDpadDown {
            if lbHeld {
                next.panelNavigation = .down
                appendLog("[LB + D-Down] Cockpit Panel DOWN")
            } else {
                next.pipReset = true
                appendLog("[D-Down] Reset Pips (2/2/2)")
            }
        }
        prevDpadDown = dDown

        let dLeft = pad.dpad.left.isPressed
        if dLeft && !prevDpadLeft {
            if lbHeld {
                next.panelNavigation = .left
                appendLog("[LB + D-Left] Cockpit Panel LEFT")
            } else {
                next.pipSYS = true
                appendLog("[D-Left] +1 Pip SYS")
            }
        }
        prevDpadLeft = dLeft

        let dRight = pad.dpad.right.isPressed
        if dRight && !prevDpadRight {
            if lbHeld {
                next.panelNavigation = .right
                appendLog("[LB + D-Right] Cockpit Panel RIGHT")
            } else {
                next.pipWEP = true
                appendLog("[D-Right] +1 Pip WEP")
            }
        }
        prevDpadRight = dRight

        // Menu / Options
        let menuPressed = pad.buttonMenu.isPressed
        if menuPressed && !prevMenu {
            next.pauseTriggered = true
            appendLog("[Menu] Pause")
        }
        prevMenu = menuPressed

        let optionsPressed = pad.buttonOptions?.isPressed ?? false
        if optionsPressed && !prevOptions {
            appendLog("[View] Cockpit Panels")
        }
        prevOptions = optionsPressed

        state = next
        return next
    }

    private func appendLog(_ entry: String) {
        print("[StarfallInput] \(entry)")
        recentLogs.insert(entry, at: 0)
        if recentLogs.count > 6 {
            recentLogs.removeLast(recentLogs.count - 6)
        }
    }
}
