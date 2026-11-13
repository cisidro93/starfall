import Foundation
import RealityKit
import UIKit
import simd

enum DroneBehaviorState: String, Sendable {
    case orbitPatrol = "ORBIT PATROL"
    case strafeAttack = "STRAFE RUN"
    case evadeWeave = "EVASIVE WEAVE"
    case destroyed = "DESTROYED"
}

struct PowerDistributorState: Sendable {
    var sysPips: Int = 2
    var engPips: Int = 2
    var wepPips: Int = 2

    mutating func allocateSYS() {
        guard sysPips < 4 else { return }
        if wepPips >= engPips && wepPips > 0 {
            wepPips -= 1
            sysPips += 1
        } else if engPips > 0 {
            engPips -= 1
            sysPips += 1
        }
    }

    mutating func allocateENG() {
        guard engPips < 4 else { return }
        if sysPips >= wepPips && sysPips > 0 {
            sysPips -= 1
            engPips += 1
        } else if wepPips > 0 {
            wepPips -= 1
            engPips += 1
        }
    }

    mutating func allocateWEP() {
        guard wepPips < 4 else { return }
        if sysPips >= engPips && sysPips > 0 {
            sysPips -= 1
            wepPips += 1
        } else if engPips > 0 {
            engPips -= 1
            wepPips += 1
        }
    }

    mutating func reset() {
        sysPips = 2
        engPips = 2
        wepPips = 2
    }

    var shieldRegenMultiplier: Float {
        0.45 + Float(sysPips) * 0.30
    }

    var engineSpeedMultiplier: Float {
        0.84 + Float(engPips) * 0.08
    }

    var boostRechargeMultiplier: Float {
        0.55 + Float(engPips) * 0.25
    }

    var weaponRechargeMultiplier: Float {
        0.45 + Float(wepPips) * 0.32
    }
}

@MainActor
final class CombatDroneInstance {
    let id: String
    let callsign: String
    let rootEntity: Entity
    let shieldBubbleEntity: ModelEntity
    let explosionEntity: ModelEntity
    let patrolCenter: SIMD3<Double>
    let orbitPhaseOffset: Float

    var worldPosition: SIMD3<Double>
    var velocity: SIMD3<Float> = .zero
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var shields: Float = 100.0
    var hull: Float = 100.0
    var state: DroneBehaviorState = .orbitPatrol
    var shieldHitFlashTimer: Float = 0.0
    var respawnTimer: Float = 0.0
    var aiClock: Float = 0.0

    static let subsystems = [
        "CHASSIS / HULL",
        "SHIELD EMITTER",
        "VECTOR THRUSTERS",
        "PULSE EMITTER"
    ]

    init(
        id: String,
        callsign: String,
        patrolCenter: SIMD3<Double>,
        orbitPhaseOffset: Float,
        rootEntity: Entity,
        shieldBubbleEntity: ModelEntity,
        explosionEntity: ModelEntity
    ) {
        self.id = id
        self.callsign = callsign
        self.patrolCenter = patrolCenter
        self.orbitPhaseOffset = orbitPhaseOffset
        self.worldPosition = patrolCenter + SIMD3<Double>(Double(cos(orbitPhaseOffset)) * 140.0, 0.0, Double(sin(orbitPhaseOffset)) * 140.0)
        self.rootEntity = rootEntity
        self.shieldBubbleEntity = shieldBubbleEntity
        self.explosionEntity = explosionEntity
    }

    var isAlive: Bool {
        state != .destroyed && hull > 0.0
    }
}

@MainActor
final class CombatSystemManager {
    var drones: [CombatDroneInstance] = []
    var lockedDroneIndex: Int? = 0
    var selectedSubsystemIndex: Int = 0
    var distributor = PowerDistributorState()

    // Player combat stats
    var playerShields: Float = 100.0
    var playerHull: Float = 100.0
    var weaponCapacitor: Float = 100.0
    var laserVisualTimer: Float = 0.0
    var cannonVisualTimer: Float = 0.0
    var cannonCooldown: Float = 0.0
    var hitMarkerTimer: Float = 0.0
    var totalKills: Int = 0

    // Visual tracer entities attached to root
    private var leftLaserBeam: ModelEntity?
    private var rightLaserBeam: ModelEntity?
    private var cannonTracerBolt: ModelEntity?

    // Haptics
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notifyHaptic = UINotificationFeedbackGenerator()

    func setupCombatEntities(into root: Entity) {
        guard drones.isEmpty else { return }

        let patrolCenter = SIMD3<Double>(-520.0, 90.0, -680.0)
        let specs: [(String, String, Float)] = [
            ("drone_1", "SF-D1 WASP", 0.0),
            ("drone_2", "SF-D2 HORNET", 2.09),
            ("drone_3", "SF-D3 MANTIS", 4.18)
        ]

        for (id, name, phase) in specs {
            let (entity, shieldSphere, explosionSphere) = Self.makeDroneEntity(name: name)
            root.addChild(entity)
            let instance = CombatDroneInstance(
                id: id,
                callsign: name,
                patrolCenter: patrolCenter,
                orbitPhaseOffset: phase,
                rootEntity: entity,
                shieldBubbleEntity: shieldSphere,
                explosionEntity: explosionSphere
            )
            entity.components.set(WorldPositionComponent(instance.worldPosition))
            drones.append(instance)
        }

        // Build Forsaken Relay Hulk & Salvage Beacon at (480, -75, -560)
        let derelict = Self.makeDerelictRelayHulkEntity(worldPosition: SIMD3<Double>(480.0, -75.0, -560.0))
        root.addChild(derelict)

        // Build Earth Orbital Nav Beacon at (140, 110, -320)
        let beacon = Self.makeNavBeaconEntity(worldPosition: SIMD3<Double>(140.0, 110.0, -320.0))
        root.addChild(beacon)

        // Build Weapon Beam & Tracer visuals
        let beamMesh = MeshResource.generateBox(size: SIMD3<Float>(0.14, 0.14, 180.0), cornerRadius: 0.05)
        let beamMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.95, blue: 1.0, alpha: 1.0))
        let lBeam = ModelEntity(mesh: beamMesh, materials: [beamMat])
        let rBeam = ModelEntity(mesh: beamMesh, materials: [beamMat])
        lBeam.isEnabled = false
        rBeam.isEnabled = false
        root.addChild(lBeam)
        root.addChild(rBeam)
        leftLaserBeam = lBeam
        rightLaserBeam = rBeam

        let boltMesh = MeshResource.generateSphere(radius: 0.45)
        let boltMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1.0))
        let bolt = ModelEntity(mesh: boltMesh, materials: [boltMat])
        bolt.isEnabled = false
        root.addChild(bolt)
        cannonTracerBolt = bolt
    }

    func stepCombat(
        dt: Float,
        input: InputStateComponent,
        playerWorldPos: SIMD3<Double>,
        playerVelocity: SIMD3<Float>,
        playerOrientation: simd_quatf,
        originFrame: FloatingOriginFrame
    ) {
        // 1. Handle Power Distributor D-pad triggers
        if input.pipSYS { distributor.allocateSYS() }
        if input.pipENG { distributor.allocateENG() }
        if input.pipWEP { distributor.allocateWEP() }
        if input.pipReset { distributor.reset() }

        // 2. Handle Target Lock [X] & Subsystem Cycle [LB + X]
        if input.targetAheadTriggered {
            selectTargetNearestBoresight(playerWorldPos: playerWorldPos, playerOrientation: playerOrientation)
            lightImpact.impactOccurred()
        }
        if input.nextSubsystemTriggered {
            selectedSubsystemIndex = (selectedSubsystemIndex + 1) % CombatDroneInstance.subsystems.count
            lightImpact.impactOccurred()
        }

        // 3. Recharge player shields & weapon capacitor via SYS and WEP pips
        playerShields = min(100.0, playerShields + 4.2 * distributor.shieldRegenMultiplier * dt)
        weaponCapacitor = min(100.0, weaponCapacitor + 14.0 * distributor.weaponRechargeMultiplier * dt)

        // 4. Step AI drones
        let forwardFloat = playerOrientation.act(SIMD3<Float>(0, 0, -1))
        for drone in drones {
            stepSingleDrone(
                drone: drone,
                dt: dt,
                playerWorldPos: playerWorldPos,
                originFrame: originFrame
            )
        }

        // 5. Handle Player Weapons (RT = Fixed Pulse Lasers, LT = Gimballed Multi-Cannons)
        cannonCooldown = max(0.0, cannonCooldown - dt)
        hitMarkerTimer = max(0.0, hitMarkerTimer - dt)

        let playerLocal = originFrame.localPosition(for: playerWorldPos)

        // Primary Fire (RT): Fixed Dual Pulse Lasers
        if input.primaryFireHeld && weaponCapacitor >= 4.0 {
            weaponCapacitor = max(0.0, weaponCapacitor - 22.0 * dt)
            laserVisualTimer = 0.06

            let leftMuzzle = playerLocal + playerOrientation.act(SIMD3<Float>(-1.85, -0.15, -92.0))
            let rightMuzzle = playerLocal + playerOrientation.act(SIMD3<Float>(1.85, -0.15, -92.0))
            leftLaserBeam?.position = leftMuzzle
            leftLaserBeam?.orientation = playerOrientation
            leftLaserBeam?.isEnabled = true
            rightLaserBeam?.position = rightMuzzle
            rightLaserBeam?.orientation = playerOrientation
            rightLaserBeam?.isEnabled = true

            // Ray-cone hit check against alive drones (fixed tight 4.5° cone)
            for (idx, drone) in drones.enumerated() where drone.isAlive {
                let deltaD = drone.worldPosition - playerWorldPos
                let dist = Float(simd_length(deltaD))
                guard dist < 950.0 && dist > 1.0 else { continue }
                let dirToDrone = SIMD3<Float>(Float(deltaD.x), Float(deltaD.y), Float(deltaD.z)) / dist
                let cosAngle = simd_dot(forwardFloat, dirToDrone)
                if cosAngle > 0.996 { // ~5 degrees
                    applyDamage(to: drone, index: idx, shieldDmg: 58.0 * dt, hullDmg: 28.0 * dt)
                }
            }
        } else {
            laserVisualTimer = max(0.0, laserVisualTimer - dt)
            if laserVisualTimer <= 0.0 {
                leftLaserBeam?.isEnabled = false
                rightLaserBeam?.isEnabled = false
            }
        }

        // Secondary Fire (LT): Gimballed Multi-Cannons (wider 14° auto-tracking cone around lead vector)
        if input.secondaryFireHeld && weaponCapacitor >= 2.0 {
            weaponCapacitor = max(0.0, weaponCapacitor - 11.0 * dt)
            cannonVisualTimer = 0.05

            var aimDir = forwardFloat
            if let lockedIdx = lockedDroneIndex, lockedIdx < drones.count, drones[lockedIdx].isAlive {
                let drone = drones[lockedIdx]
                let deltaD = drone.worldPosition - playerWorldPos
                let dist = max(1.0, Float(simd_length(deltaD)))
                let leadTime = dist / 680.0
                let relVel = drone.velocity - playerVelocity
                let leadDelta = SIMD3<Float>(Float(deltaD.x), Float(deltaD.y), Float(deltaD.z)) + relVel * leadTime
                let leadDir = simd_normalize(leadDelta)
                if simd_dot(forwardFloat, leadDir) > 0.955 { // within ~17° gimbal cone
                    aimDir = leadDir
                }
            }

            let tracerDist: Float = 45.0 + Float(( Int(cannonCooldown * 1000) % 70 ))
            cannonTracerBolt?.position = playerLocal + aimDir * tracerDist
            cannonTracerBolt?.isEnabled = true

            if cannonCooldown <= 0.0 {
                cannonCooldown = 0.11
                lightImpact.impactOccurred(intensity: 0.65)

                for (idx, drone) in drones.enumerated() where drone.isAlive {
                    let deltaD = drone.worldPosition - playerWorldPos
                    let dist = Float(simd_length(deltaD))
                    guard dist < 850.0 && dist > 1.0 else { continue }
                    let dirToDrone = SIMD3<Float>(Float(deltaD.x), Float(deltaD.y), Float(deltaD.z)) / dist
                    if simd_dot(aimDir, dirToDrone) > 0.985 {
                        applyDamage(to: drone, index: idx, shieldDmg: 4.5, hullDmg: 11.5)
                    }
                }
            }
        } else {
            cannonVisualTimer = max(0.0, cannonVisualTimer - dt)
            if cannonVisualTimer <= 0.0 {
                cannonTracerBolt?.isEnabled = false
            }
        }
    }

    private func applyDamage(to drone: CombatDroneInstance, index: Int, shieldDmg: Float, hullDmg: Float) {
        hitMarkerTimer = 0.18
        if lockedDroneIndex == nil {
            lockedDroneIndex = index
        }
        if drone.shields > 0.0 {
            drone.shields = max(0.0, drone.shields - shieldDmg)
            drone.shieldHitFlashTimer = 0.18
            if drone.shields <= 25.0 {
                drone.state = .evadeWeave
            }
        } else {
            drone.hull = max(0.0, drone.hull - hullDmg)
            if drone.hull <= 0.0 {
                drone.state = .destroyed
                drone.respawnTimer = 6.0
                totalKills += 1
                heavyImpact.impactOccurred()
                notifyHaptic.notificationOccurred(.success)
            }
        }
    }

    private func stepSingleDrone(
        drone: CombatDroneInstance,
        dt: Float,
        playerWorldPos: SIMD3<Double>,
        originFrame: FloatingOriginFrame
    ) {
        drone.aiClock += dt

        if drone.state == .destroyed {
            drone.respawnTimer -= dt
            drone.shieldBubbleEntity.isEnabled = false
            if drone.respawnTimer > 4.8 {
                let burstProgress = (6.0 - drone.respawnTimer) / 1.2
                drone.explosionEntity.isEnabled = true
                drone.explosionEntity.scale = SIMD3<Float>(repeating: 1.0 + burstProgress * 9.0)
            } else {
                drone.explosionEntity.isEnabled = false
                drone.rootEntity.isEnabled = false
            }

            if drone.respawnTimer <= 0.0 {
                drone.shields = 100.0
                drone.hull = 100.0
                drone.state = .orbitPatrol
                drone.rootEntity.isEnabled = true
            }
            return
        }

        drone.explosionEntity.isEnabled = false
        drone.rootEntity.isEnabled = true

        // Shield hit flash decay & slow shield regeneration
        drone.shieldHitFlashTimer = max(0.0, drone.shieldHitFlashTimer - dt)
        drone.shieldBubbleEntity.isEnabled = drone.shieldHitFlashTimer > 0.0
        if drone.shieldHitFlashTimer <= 0.0 && drone.shields < 100.0 {
            drone.shields = min(100.0, drone.shields + 2.5 * dt)
        }

        // State transitions based on distance to player & shields
        let distToPlayer = simd_length(playerWorldPos - drone.worldPosition)
        if drone.shields < 30.0 {
            drone.state = .evadeWeave
        } else if distToPlayer < 520.0 {
            drone.state = .strafeAttack
        } else {
            drone.state = .orbitPatrol
        }

        let t = drone.aiClock * 0.55 + drone.orbitPhaseOffset
        let targetWorldPos: SIMD3<Double>
        let desiredSpeed: Float

        switch drone.state {
        case .orbitPatrol:
            targetWorldPos = drone.patrolCenter + SIMD3<Double>(
                Double(cos(t)) * 165.0,
                Double(sin(t * 1.4)) * 38.0,
                Double(sin(t)) * 165.0
            )
            desiredSpeed = 72.0

        case .strafeAttack:
            let strafeOffset = SIMD3<Double>(
                Double(cos(t * 1.5)) * 190.0,
                Double(sin(t * 2.1)) * 55.0,
                Double(sin(t * 1.5)) * 190.0
            )
            targetWorldPos = playerWorldPos + strafeOffset
            desiredSpeed = 95.0

        case .evadeWeave:
            let weaveOffset = SIMD3<Double>(
                Double(sin(t * 2.8)) * 240.0,
                Double(cos(t * 3.2)) * 95.0,
                Double(cos(t * 2.4)) * 240.0
            )
            targetWorldPos = drone.patrolCenter + weaveOffset
            desiredSpeed = 122.0

        case .destroyed:
            return
        }

        let toTarget = targetWorldPos - drone.worldPosition
        let dist = max(1.0, simd_length(toTarget))
        let dirDouble = toTarget / dist
        let desiredVel = SIMD3<Float>(Float(dirDouble.x), Float(dirDouble.y), Float(dirDouble.z)) * desiredSpeed

        drone.velocity += (desiredVel - drone.velocity) * min(1.0, dt * 2.8)
        drone.worldPosition += SIMD3<Double>(
            Double(drone.velocity.x) * Double(dt),
            Double(drone.velocity.y) * Double(dt),
            Double(drone.velocity.z) * Double(dt)
        )

        if simd_length_squared(drone.velocity) > 1.0 {
            let fwd = simd_normalize(drone.velocity)
            drone.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: fwd)
        }

        drone.rootEntity.components.set(WorldPositionComponent(drone.worldPosition))
        drone.rootEntity.position = originFrame.localPosition(for: drone.worldPosition)
        drone.rootEntity.orientation = drone.orientation
    }

    func selectTargetNearestBoresight(playerWorldPos: SIMD3<Double>, playerOrientation: simd_quatf) {
        let forward = playerOrientation.act(SIMD3<Float>(0, 0, -1))
        var bestIndex: Int?
        var bestDot: Float = -2.0

        for (idx, drone) in drones.enumerated() where drone.isAlive {
            let delta = drone.worldPosition - playerWorldPos
            let dist = max(1.0, Float(simd_length(delta)))
            let dir = SIMD3<Float>(Float(delta.x), Float(delta.y), Float(delta.z)) / dist
            let dot = simd_dot(forward, dir)
            if dot > bestDot {
                bestDot = dot
                bestIndex = idx
            }
        }
        lockedDroneIndex = bestIndex
    }

    func cycleNextTarget() {
        let aliveIndices = drones.enumerated().compactMap { $0.element.isAlive ? $0.offset : nil }
        guard !aliveIndices.isEmpty else {
            lockedDroneIndex = nil
            return
        }
        if let current = lockedDroneIndex, let pos = aliveIndices.firstIndex(of: current) {
            lockedDroneIndex = aliveIndices[(pos + 1) % aliveIndices.count]
        } else {
            lockedDroneIndex = aliveIndices[0]
        }
        lightImpact.impactOccurred()
    }

    // MARK: - 3D Entity Builders

    private static func makeDroneEntity(name: String) -> (Entity, ModelEntity, ModelEntity) {
        let root = Entity()
        root.name = name

        let armorMat = SimpleMaterial(
            color: UIColor(red: 0.22, green: 0.24, blue: 0.29, alpha: 1.0),
            roughness: 0.35,
            isMetallic: true
        )
        let crimsonMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.22, blue: 0.18, alpha: 1.0))

        // Central aggressor fuselage
        let coreMesh = MeshResource.generateBox(size: SIMD3<Float>(2.4, 1.1, 4.8), cornerRadius: 0.3)
        let core = ModelEntity(mesh: coreMesh, materials: [armorMat])
        root.addChild(core)

        // Swept interceptor wings
        let wingMesh = MeshResource.generateBox(size: SIMD3<Float>(7.2, 0.22, 2.2), cornerRadius: 0.08)
        let wings = ModelEntity(mesh: wingMesh, materials: [armorMat])
        wings.position = SIMD3<Float>(0, 0, 0.3)
        root.addChild(wings)

        // Glowing crimson visor & thruster eye
        let eyeMesh = MeshResource.generateSphere(radius: 0.65)
        let eye = ModelEntity(mesh: eyeMesh, materials: [crimsonMat])
        eye.position = SIMD3<Float>(0, 0.15, -2.1)
        root.addChild(eye)

        let thrusterGlow = ModelEntity(mesh: eyeMesh, materials: [crimsonMat])
        thrusterGlow.position = SIMD3<Float>(0, 0.0, 2.5)
        root.addChild(thrusterGlow)

        // Translucent cyan shield bubble (flashes when hit)
        let shieldMesh = MeshResource.generateSphere(radius: 4.5)
        var shieldMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.85, blue: 1.0, alpha: 1.0))
        shieldMat.blending = .transparent(opacity: .init(floatLiteral: 0.36))
        let shieldSphere = ModelEntity(mesh: shieldMesh, materials: [shieldMat])
        shieldSphere.isEnabled = false
        root.addChild(shieldSphere)

        // Orange-amber explosion fireball sphere
        let expMesh = MeshResource.generateSphere(radius: 1.8)
        var expMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1.0))
        expMat.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        let expSphere = ModelEntity(mesh: expMesh, materials: [expMat])
        expSphere.isEnabled = false
        root.addChild(expSphere)

        return (root, shieldSphere, expSphere)
    }

    private static func makeDerelictRelayHulkEntity(worldPosition: SIMD3<Double>) -> Entity {
        let hulkRoot = Entity()
        hulkRoot.name = "ForsakenRelayHulk"
        hulkRoot.components.set(WorldPositionComponent(worldPosition))

        let rustedHull = SimpleMaterial(
            color: UIColor(red: 0.30, green: 0.25, blue: 0.22, alpha: 1.0),
            roughness: 0.72,
            isMetallic: true
        )
        let brokenPanel = SimpleMaterial(
            color: UIColor(red: 0.15, green: 0.22, blue: 0.34, alpha: 1.0),
            roughness: 0.45,
            isMetallic: true
        )
        let beaconGlow = UnlitMaterial(color: UIColor(red: 0.20, green: 0.95, blue: 0.82, alpha: 1.0))

        // Shattered main truss spine
        let spineMesh = MeshResource.generateBox(size: SIMD3<Float>(8.0, 8.0, 46.0), cornerRadius: 1.0)
        let spine = ModelEntity(mesh: spineMesh, materials: [rustedHull])
        spine.orientation = simd_quatf(angle: 0.35, axis: simd_normalize(SIMD3<Float>(1, 0.5, 0.2)))
        hulkRoot.addChild(spine)

        // Torn solar array wings
        let panelMesh = MeshResource.generateBox(size: SIMD3<Float>(38.0, 0.6, 12.0))
        let panelA = ModelEntity(mesh: panelMesh, materials: [brokenPanel])
        panelA.position = SIMD3<Float>(-14.0, 4.0, -6.0)
        panelA.orientation = simd_quatf(angle: -0.42, axis: SIMD3<Float>(0, 1, 1))
        hulkRoot.addChild(panelA)

        let panelB = ModelEntity(mesh: panelMesh, materials: [brokenPanel])
        panelB.position = SIMD3<Float>(16.0, -5.0, 8.0)
        panelB.orientation = simd_quatf(angle: 0.55, axis: SIMD3<Float>(1, 0, 1))
        hulkRoot.addChild(panelB)

        // Salvage transponder beacon core
        let beaconMesh = MeshResource.generateSphere(radius: 1.8)
        let beacon = ModelEntity(mesh: beaconMesh, materials: [beaconGlow])
        beacon.position = SIMD3<Float>(0, 6.0, 0)
        hulkRoot.addChild(beacon)

        return hulkRoot
    }

    private static func makeNavBeaconEntity(worldPosition: SIMD3<Double>) -> Entity {
        let root = Entity()
        root.name = "EarthOrbitalNavBeacon"
        root.components.set(WorldPositionComponent(worldPosition))

        let goldMat = SimpleMaterial(
            color: UIColor(red: 0.90, green: 0.68, blue: 0.25, alpha: 1.0),
            roughness: 0.25,
            isMetallic: true
        )
        let cyanGlow = UnlitMaterial(color: UIColor(red: 0.15, green: 0.92, blue: 1.0, alpha: 1.0))

        let pylonMesh = MeshResource.generateBox(size: SIMD3<Float>(1.4, 9.0, 1.4), cornerRadius: 0.3)
        let pylon = ModelEntity(mesh: pylonMesh, materials: [goldMat])
        root.addChild(pylon)

        let coreMesh = MeshResource.generateSphere(radius: 1.6)
        let core = ModelEntity(mesh: coreMesh, materials: [cyanGlow])
        root.addChild(core)

        return root
    }
}
