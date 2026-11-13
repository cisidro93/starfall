import Foundation
import RealityKit

enum CockpitPanelDirection: String, Sendable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
}

/// RealityKit ECS component holding the current tick's mapped controller state.
struct InputStateComponent: Component, Sendable {
    // Continuous flight axes (-1...1)
    var pitch: Float = 0.0
    var roll: Float = 0.0
    var yaw: Float = 0.0
    var lateralThrust: Float = 0.0
    var verticalThrust: Float = 0.0

    // Cockpit free-look axes (-1...1, active while holding LB)
    var lookYaw: Float = 0.0
    var lookPitch: Float = 0.0

    // Triggers & throttle
    var isModifierHeld: Bool = false
    var primaryFireValue: Float = 0.0
    var secondaryFireValue: Float = 0.0
    var primaryFireHeld: Bool = false
    var secondaryFireHeld: Bool = false
    var throttleDelta: Float = 0.0
    var throttle: Float = 0.0

    // Ship state toggles controlled by mapped buttons
    var flightAssistEnabled: Bool = true
    var hardpointsDeployed: Bool = false
    var landingGearDeployed: Bool = false
    var cargoScoopDeployed: Bool = false

    // Single-tick edge-triggered actions
    var boostTriggered: Bool = false
    var targetAheadTriggered: Bool = false
    var nextSubsystemTriggered: Bool = false
    var galaxyMapTriggered: Bool = false
    var pipSYS: Bool = false
    var pipENG: Bool = false
    var pipWEP: Bool = false
    var pipReset: Bool = false
    var panelNavigation: CockpitPanelDirection? = nil
    var pauseTriggered: Bool = false
    var cameraToggleTriggered: Bool = false

    /// Applies radial/axial dead-zone and a smooth non-linear response curve.
    static func applyStickCurve(_ raw: Float, deadZone: Float = 0.10, exponent: Float = 1.8) -> Float {
        let absVal = abs(raw)
        guard absVal > deadZone else { return 0.0 }
        let normalized = min(1.0, (absVal - deadZone) / max(0.001, 1.0 - deadZone))
        let curved = pow(normalized, exponent)
        return raw >= 0.0 ? curved : -curved
    }
}
