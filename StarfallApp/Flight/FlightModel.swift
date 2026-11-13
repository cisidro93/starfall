import Foundation
import RealityKit
import simd

/// Data-driven ship tuning specification decoded from JSON.
struct ShipSpec: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var shipClass: String
    var maxSpeed: Float
    var reverseMaxSpeed: Float
    var boostSpeed: Float
    var forwardAcceleration: Float
    var reverseAcceleration: Float
    var lateralAcceleration: Float
    var verticalAcceleration: Float
    var pitchRateDeg: Float
    var rollRateDeg: Float
    var yawRateDeg: Float
    var angularResponse: Float
    var linearDampingFA: Float
    var boostDuration: Float
    var boostCooldown: Float
    var boostAcceleration: Float

    static let starterKestrelJSON = """
    {
      "id": "sf1v_kestrel",
      "name": "SF-1V Kestrel",
      "shipClass": "Light Interceptor",
      "maxSpeed": 280.0,
      "reverseMaxSpeed": 140.0,
      "boostSpeed": 460.0,
      "forwardAcceleration": 78.0,
      "reverseAcceleration": 48.0,
      "lateralAcceleration": 56.0,
      "verticalAcceleration": 56.0,
      "pitchRateDeg": 75.0,
      "rollRateDeg": 135.0,
      "yawRateDeg": 36.0,
      "angularResponse": 8.0,
      "linearDampingFA": 2.4,
      "boostDuration": 2.2,
      "boostCooldown": 4.8,
      "boostAcceleration": 210.0
    }
    """

    static func loadStarterSpec() -> ShipSpec {
        let data = Data(starterKestrelJSON.utf8)
        if let decoded = try? JSONDecoder().decode(ShipSpec.self, from: data) {
            return decoded
        }
        return ShipSpec(
            id: "sf1v_kestrel",
            name: "SF-1V Kestrel",
            shipClass: "Light Interceptor",
            maxSpeed: 280.0,
            reverseMaxSpeed: 140.0,
            boostSpeed: 460.0,
            forwardAcceleration: 78.0,
            reverseAcceleration: 48.0,
            lateralAcceleration: 56.0,
            verticalAcceleration: 56.0,
            pitchRateDeg: 75.0,
            rollRateDeg: 135.0,
            yawRateDeg: 36.0,
            angularResponse: 8.0,
            linearDampingFA: 2.4,
            boostDuration: 2.2,
            boostCooldown: 4.8,
            boostAcceleration: 210.0
        )
    }
}

enum ShipCameraMode: String, Sendable {
    case cockpit = "COCKPIT"
    case chase = "CHASE"
}

/// RealityKit component storing the player's 6DOF Newtonian flight state.
struct FlightComponent: Component, Sendable {
    var spec: ShipSpec
    /// Linear velocity in world space (m/s).
    var velocity: SIMD3<Float> = .zero
    /// Local-space angular velocity (rad/s) around (pitch X, yaw Y, roll Z).
    var angularVelocity: SIMD3<Float> = .zero
    /// Current ship orientation in world space.
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    /// Remaining active boost burn time (s).
    var boostTimeRemaining: Float = 0.0
    /// Remaining boost capacitor cooldown time (s).
    var boostCooldownRemaining: Float = 0.0
    /// Local-frame G-force felt by the pilot (for cockpit camera & HUD feedback).
    var localGForce: SIMD3<Float> = .zero

    init(spec: ShipSpec = ShipSpec.loadStarterSpec()) {
        self.spec = spec
    }

    var speed: Float {
        simd_length(velocity)
    }

    var isBoosting: Bool {
        boostTimeRemaining > 0.0
    }

    var canBoost: Bool {
        boostCooldownRemaining <= 0.0 && boostTimeRemaining <= 0.0
    }

    /// 0...1 readiness of the boost capacitor.
    var boostChargeFraction: Float {
        guard spec.boostCooldown > 0 else { return 1.0 }
        return min(1.0, max(0.0, 1.0 - boostCooldownRemaining / spec.boostCooldown))
    }

    var forwardVector: SIMD3<Float> {
        orientation.act(SIMD3<Float>(0, 0, -1))
    }

    var rightVector: SIMD3<Float> {
        orientation.act(SIMD3<Float>(1, 0, 0))
    }

    var upVector: SIMD3<Float> {
        orientation.act(SIMD3<Float>(0, 1, 0))
    }
}

enum FlightPhysics {
    static let fixedTimeStep: Double = 1.0 / 60.0

    /// Advances the ship's 6DOF Newtonian physics by one fixed 60 Hz step.
    static func stepFixedTick(
        flight: inout FlightComponent,
        input: InputStateComponent,
        worldPosition: inout WorldPositionComponent,
        dt: Float
    ) {
        let spec = flight.spec
        let previousVelocity = flight.velocity

        // 1. Boost timers
        if flight.boostTimeRemaining > 0.0 {
            flight.boostTimeRemaining = max(0.0, flight.boostTimeRemaining - dt)
        }
        if flight.boostCooldownRemaining > 0.0 {
            flight.boostCooldownRemaining = max(0.0, flight.boostCooldownRemaining - dt)
        }
        if input.boostTriggered && flight.canBoost {
            flight.boostTimeRemaining = spec.boostDuration
            flight.boostCooldownRemaining = spec.boostCooldown
        }

        // 2. Rotational 6DOF physics (Pitch = local +X, Yaw = local -Y, Roll = local -Z)
        let maxPitchRad = spec.pitchRateDeg * .pi / 180.0
        let maxRollRad = spec.rollRateDeg * .pi / 180.0
        let maxYawRad = spec.yawRateDeg * .pi / 180.0

        let targetAngular = SIMD3<Float>(
            input.pitch * maxPitchRad,
            -input.yaw * maxYawRad,
            -input.roll * maxRollRad
        )

        if input.flightAssistEnabled {
            // Flight Assist ON: smooth exponential convergence to commanded rotational rates.
            let blend = min(1.0, spec.angularResponse * dt)
            flight.angularVelocity += (targetAngular - flight.angularVelocity) * blend
        } else {
            // Flight Assist OFF: stick inputs apply raw rotational acceleration; releasing does not damp spin.
            let torqueScale: Float = 2.4
            flight.angularVelocity += targetAngular * torqueScale * dt
            flight.angularVelocity.x = min(max(flight.angularVelocity.x, -maxPitchRad * 1.25), maxPitchRad * 1.25)
            flight.angularVelocity.y = min(max(flight.angularVelocity.y, -maxYawRad * 1.25), maxYawRad * 1.25)
            flight.angularVelocity.z = min(max(flight.angularVelocity.z, -maxRollRad * 1.25), maxRollRad * 1.25)
        }

        let angSpeed = simd_length(flight.angularVelocity)
        if angSpeed > 0.00001 {
            let axis = flight.angularVelocity / angSpeed
            let deltaRot = simd_quatf(angle: angSpeed * dt, axis: axis)
            flight.orientation = simd_normalize(simd_mul(flight.orientation, deltaRot))
        }

        // 3. Linear 6DOF physics
        let forward = flight.forwardVector
        let right = flight.rightVector
        let up = flight.upVector

        let effectiveMaxSpeed: Float = flight.isBoosting
            ? spec.boostSpeed
            : (flight.speed > spec.maxSpeed ? max(spec.maxSpeed, flight.speed - 65.0 * dt) : spec.maxSpeed)

        if input.flightAssistEnabled {
            // Flight Assist ON: compute desired velocity vector in ship frame and accelerate toward it.
            let forwardCommandSpeed = flight.isBoosting
                ? spec.boostSpeed
                : (input.throttle * spec.maxSpeed)
            let lateralCommandSpeed = input.lateralThrust * (spec.maxSpeed * 0.65)
            let verticalCommandSpeed = input.verticalThrust * (spec.maxSpeed * 0.65)

            let desiredVelocity = forward * forwardCommandSpeed
                + right * lateralCommandSpeed
                + up * verticalCommandSpeed

            let velocityError = desiredVelocity - flight.velocity
            let forwardAccel = flight.isBoosting ? spec.boostAcceleration : spec.forwardAcceleration

            // Project error onto ship axes so each thruster bank respects its physical acceleration limit.
            let errFwd = simd_dot(velocityError, forward)
            let errRight = simd_dot(velocityError, right)
            let errUp = simd_dot(velocityError, up)

            let maxDeltaFwd = (errFwd >= 0 ? forwardAccel : spec.reverseAcceleration) * dt
            let maxDeltaRight = spec.lateralAcceleration * dt
            let maxDeltaUp = spec.verticalAcceleration * dt

            let stepFwd = min(max(errFwd * spec.linearDampingFA * dt, -maxDeltaFwd), maxDeltaFwd)
            let stepRight = min(max(errRight * spec.linearDampingFA * dt, -maxDeltaRight), maxDeltaRight)
            let stepUp = min(max(errUp * spec.linearDampingFA * dt, -maxDeltaUp), maxDeltaUp)

            flight.velocity += forward * stepFwd + right * stepRight + up * stepUp
        } else {
            // Flight Assist OFF: pure Newtonian thrust; existing velocity vector persists in space.
            let fwdThrust: Float
            if flight.isBoosting {
                fwdThrust = spec.boostAcceleration
            } else {
                fwdThrust = input.throttle * spec.forwardAcceleration
            }
            let accelWorld = forward * fwdThrust
                + right * (input.lateralThrust * spec.lateralAcceleration)
                + up * (input.verticalThrust * spec.verticalAcceleration)

            flight.velocity += accelWorld * dt
        }

        // Enforce per-ship speed cap
        let currentSpeed = simd_length(flight.velocity)
        if currentSpeed > effectiveMaxSpeed && currentSpeed > 0.001 {
            flight.velocity = (flight.velocity / currentSpeed) * effectiveMaxSpeed
        }

        // 4. Compute pilot local G-force for cockpit head motion
        let worldAccel = (flight.velocity - previousVelocity) / max(dt, 0.001)
        let invRot = flight.orientation.inverse
        let rawG = invRot.act(worldAccel) / 9.81
        flight.localGForce = flight.localGForce * 0.82 + rawG * 0.18

        // 5. Integrate double-precision world position
        worldPosition.position += SIMD3<Double>(
            Double(flight.velocity.x) * Double(dt),
            Double(flight.velocity.y) * Double(dt),
            Double(flight.velocity.z) * Double(dt)
        )
    }
}
