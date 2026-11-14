import Foundation
import GameController
import Combine
import simd

@MainActor
final class ControllerInputManager: ObservableObject {
    @Published private(set) var state = InputStateComponent()
    @Published private(set) var controllerStatusText: String = "No Controller"
    @Published private(set) var isUsingVirtualController: Bool = false
    @Published private(set) var recentLogs: [String] = []
    @Published var deadZone: Float = 0.12
    @Published var responseExponent: Float = 2.10
    @Published var modernSteerMode: Bool = true
    @Published var touchLeftStick: SIMD2<Float> = .zero
    @Published var touchRightStick: SIMD2<Float> = .zero
    @Published var touchStrafeMode: Bool = false

    private var activeController: GCController?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    // Previous-tick button states for edge detection & input logging
    private var prevLB = false
    private var prevRB = false
    private var prevA = false
    private var pendingBoostRequest = false
    var touchPrimaryFireHeld = false
    var touchSecondaryFireHeld = false
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
        let physicalControllers = allControllers.filter { $0.extendedGamepad != nil }

        if let physical = physicalControllers.first {
            activeController = physical
            let vendor = physical.vendorName ?? "Game Controller"
            controllerStatusText = "\(vendor)"
        } else {
            activeController = nil
            controllerStatusText = isUsingVirtualController ? "Holo Touch Flight Sticks" : "Connect Pad (or tap Touch Pad)"
        }
    }

    func toggleVirtualController() {
        isUsingVirtualController.toggle()
        touchLeftStick = .zero
        touchRightStick = .zero
        if isUsingVirtualController {
            controllerStatusText = "Holo Touch Flight Sticks"
            appendLog("[HUD] Holo Touch Flight Sticks ON")
        } else {
            refreshControllers()
            appendLog("[HUD] Holo Touch Flight Sticks OFF")
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

    func toggleAutoTrack() {
        state.autoTrackEnabled.toggle()
        appendLog("[HUD] Target Auto-Track: \(state.autoTrackEnabled ? "ON" : "OFF")")
    }

    func requestBoost() {
        pendingBoostRequest = true
        appendLog("[HUD] Boost requested")
    }

    /// Polls the active controller on each simulation tick and updates `state`.
    func pollTick(deltaTime: TimeInterval) -> InputStateComponent {
        var next = state
        let dt = Float(min(max(deltaTime, 0.0), 0.1))
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
            let lx = InputStateComponent.applyStickCurve(touchLeftStick.x, deadZone: deadZone, exponent: responseExponent)
            let ly = InputStateComponent.applyStickCurve(touchLeftStick.y, deadZone: deadZone, exponent: responseExponent)
            let rx = InputStateComponent.applyStickCurve(touchRightStick.x, deadZone: deadZone, exponent: responseExponent)
            let ry = InputStateComponent.applyStickCurve(touchRightStick.y, deadZone: deadZone, exponent: responseExponent)

            next.pitch = ly
            next.yaw = lx
            if touchStrafeMode {
                next.roll = lx * 0.28
                next.lateralThrust = rx
                next.verticalThrust = ry
            } else {
                next.roll = abs(rx) > 0.05 ? rx : (lx * 0.28)
                next.lateralThrust = 0.0
                next.verticalThrust = 0.0
                if abs(ry) > 0.08 {
                    next.throttle = min(1.0, max(0.0, next.throttle + ry * dt * 0.75))
                }
            }
            next.lookYaw = 0.0
            next.lookPitch = 0.0
            next.primaryFireHeld = touchPrimaryFireHeld
            next.secondaryFireHeld = touchSecondaryFireHeld
            next.primaryFireValue = touchPrimaryFireHeld ? 1.0 : 0.0
            next.secondaryFireValue = touchSecondaryFireHeld ? 1.0 : 0.0
            state = next
            return next
        }
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

        let rawLX = min(1.0, max(-1.0, pad.leftThumbstick.xAxis.value + touchLeftStick.x))
        let rawLY = min(1.0, max(-1.0, pad.leftThumbstick.yAxis.value + touchLeftStick.y))
        let rawRX = min(1.0, max(-1.0, pad.rightThumbstick.xAxis.value + touchRightStick.x))
        let rawRY = min(1.0, max(-1.0, pad.rightThumbstick.yAxis.value + touchRightStick.y))

        let lx = InputStateComponent.applyStickCurve(rawLX, deadZone: deadZone, exponent: responseExponent)
        let ly = InputStateComponent.applyStickCurve(rawLY, deadZone: deadZone, exponent: responseExponent)
        let rx = InputStateComponent.applyStickCurve(rawRX, deadZone: deadZone, exponent: responseExponent)
        let ry = InputStateComponent.applyStickCurve(rawRY, deadZone: deadZone, exponent: responseExponent)

        if lbHeld {
            // Hold LB modifier layer:
            // Left stick -> Lateral + vertical 6DOF thrusters
            // Right stick -> Look around cockpit
            next.pitch = 0.0
            next.roll = 0.0
            next.yaw = 0.0
            next.lateralThrust = lx
            next.verticalThrust = ly
            next.lookYaw = rx
            next.lookPitch = ry
        } else if modernSteerMode {
            // Modern Steer Mode (Default):
            // Left Stick = Pitch (Y) + Yaw/Steer Nose (X) with gentle coordinated bank
            // Right Stick = Throttle Up/Down (Y) + Roll (X)
            next.pitch = ly
            next.yaw = lx
            next.roll = abs(rx) > 0.05 ? rx : (lx * 0.28)
            next.lateralThrust = 0.0
            next.verticalThrust = 0.0
            next.lookYaw = 0.0
            next.lookPitch = 0.0

            if abs(ry) > 0.08 {
                next.throttle = min(1.0, max(0.0, next.throttle + ry * dt * 0.75))
            }
        } else {
            // Classic Sim Mode:
            // Left Stick = Pitch (Y) + Roll (X)
            // Right Stick = Yaw (X) + Vertical Thrust (Y)
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
                next.throttle = min(1.0, max(0.0, next.throttle + next.throttleDelta * dt * 0.75))
            }
        } else {
            next.throttleDelta = 0.0
            next.primaryFireValue = max(rtVal, touchPrimaryFireHeld ? 1.0 : 0.0)
            next.secondaryFireValue = max(ltVal, touchSecondaryFireHeld ? 1.0 : 0.0)
            next.primaryFireHeld = rtVal > 0.25 || touchPrimaryFireHeld
            next.secondaryFireHeld = ltVal > 0.25 || touchSecondaryFireHeld

            if next.primaryFireHeld && !prevPrimaryFire {
                appendLog("[RT] Primary Pulse Lasers")
            }
            if next.secondaryFireHeld && !prevSecondaryFire {
                appendLog("[LT] Gimbal Multi-Cannons")
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
                appendLog("[\(glyph)] Target Lock")
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
                appendLog("[\(glyph)] Nav Map")
            }
        }
        prevY = yPressed

        // D-pad: Power pips (Default) vs Cockpit panel navigation (Hold LB)
        let dUp = pad.dpad.up.isPressed
        if dUp && !prevDpadUp {
            if lbHeld {
                next.panelNavigation = .up
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
            } else {
                next.pipWEP = true
                appendLog("[D-Right] +1 Pip WEP")
            }
        }
        prevDpadRight = dRight

        let menuPressed = pad.buttonMenu.isPressed
        if menuPressed && !prevMenu {
            next.pauseTriggered = true
        }
        prevMenu = menuPressed

        let optionsPressed = pad.buttonOptions?.isPressed ?? false
        if optionsPressed && !prevOptions {
            next.autoTrackEnabled.toggle()
            appendLog("[Options] Auto-Track: \(next.autoTrackEnabled ? "ON" : "OFF")")
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
