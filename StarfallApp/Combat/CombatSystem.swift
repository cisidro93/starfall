import Foundation
import RealityKit
import UIKit
import simd
import StarfallGalaxy

enum DroneBehaviorState: String, Sendable {
    case orbitPatrol = "ORBIT PATROL"
    case strafeAttack = "STRAFE RUN"
    case evadeWeave = "EVASIVE WEAVE"
    case destroyed = "DESTROYED"
}

enum OverviewCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "ALL"
    case hostiles = "HOSTILES"
    case miningLoot = "MINING/LOOT"
    case navTraffic = "NAV/TRAFFIC"

    var id: String { rawValue }
}

struct OverviewContactItem: Identifiable, Sendable {
    let id: String
    let name: String
    let typeBadge: String
    let category: OverviewCategory
    let distanceMetres: Double
    let distanceText: String
    let worldPosition: SIMD3<Double>
    let isHostile: Bool
    let isCanister: Bool
    let isAsteroid: Bool
    let isStation: Bool
    let droneIndex: Int?
    let waypointID: String?
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

    var shieldDamageMitigation: Float {
        max(0.42, 1.0 - Float(sysPips) * 0.13)
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
    let isBoss: Bool
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
    var attackCooldown: Float = 2.0

    static let subsystems = [
        "CHASSIS / HULL",
        "SHIELD EMITTER",
        "VECTOR THRUSTERS",
        "PULSE EMITTER"
    ]

    init(
        id: String,
        callsign: String,
        isBoss: Bool,
        patrolCenter: SIMD3<Double>,
        orbitPhaseOffset: Float,
        rootEntity: Entity,
        shieldBubbleEntity: ModelEntity,
        explosionEntity: ModelEntity
    ) {
        self.id = id
        self.callsign = callsign
        self.isBoss = isBoss
        self.patrolCenter = patrolCenter
        self.orbitPhaseOffset = orbitPhaseOffset
        self.worldPosition = patrolCenter + SIMD3<Double>(Double(cos(orbitPhaseOffset)) * 130.0, 0.0, Double(sin(orbitPhaseOffset)) * 130.0)
        self.rootEntity = rootEntity
        self.shieldBubbleEntity = shieldBubbleEntity
        self.explosionEntity = explosionEntity
    }

    var isAlive: Bool {
        state != .destroyed && hull > 0.0
    }
}

@MainActor
final class MineableAsteroidInstance {
    let id: String
    let name: String
    let commodityID: String
    let commodityLabel: String
    let rootEntity: Entity
    let spinAxis: SIMD3<Float>
    let spinSpeed: Float

    var worldPosition: SIMD3<Double>
    var integrity: Float = 100.0
    var droppedHalfCanister: Bool = false
    var respawnTimer: Float = 0.0
    var spinAngle: Float = 0.0

    init(
        id: String,
        name: String,
        commodityID: String,
        commodityLabel: String,
        worldPosition: SIMD3<Double>,
        rootEntity: Entity,
        spinAxis: SIMD3<Float>,
        spinSpeed: Float
    ) {
        self.id = id
        self.name = name
        self.commodityID = commodityID
        self.commodityLabel = commodityLabel
        self.worldPosition = worldPosition
        self.rootEntity = rootEntity
        self.spinAxis = spinAxis
        self.spinSpeed = spinSpeed
    }

    var isIntact: Bool {
        respawnTimer <= 0.0 && integrity > 0.0
    }
}

@MainActor
final class LootCanisterInstance {
    let id: String
    let rootEntity: Entity
    var commodityID: String = "painite_ore"
    var label: String = "Core Crystal Ore"
    var isMiningOre: Bool = true
    var worldPosition: SIMD3<Double> = .zero
    var isActive: Bool = false
    var bobPhase: Float = 0.0

    init(id: String, rootEntity: Entity) {
        self.id = id
        self.rootEntity = rootEntity
    }
}

@MainActor
final class FriendlyTrafficInstance {
    let id: String
    let callsign: String
    let roleBadge: String
    let rootEntity: Entity
    let pointA: SIMD3<Double>
    let pointB: SIMD3<Double>
    let speed: Float
    var worldPosition: SIMD3<Double>
    var headingToB: Bool = true

    init(
        id: String,
        callsign: String,
        roleBadge: String,
        rootEntity: Entity,
        pointA: SIMD3<Double>,
        pointB: SIMD3<Double>,
        speed: Float
    ) {
        self.id = id
        self.callsign = callsign
        self.roleBadge = roleBadge
        self.rootEntity = rootEntity
        self.pointA = pointA
        self.pointB = pointB
        self.speed = speed
        self.worldPosition = pointA
    }
}

@MainActor
final class CombatSystemManager {
    var drones: [CombatDroneInstance] = []
    var asteroids: [MineableAsteroidInstance] = []
    var canisters: [LootCanisterInstance] = []
    var friendlyShips: [FriendlyTrafficInstance] = []

    var lockedDroneIndex: Int? = 0
    var lockedAsteroidIndex: Int? = nil
    var selectedSubsystemIndex: Int = 0
    var distributor = PowerDistributorState()

    // Player combat stats
    var playerShields: Float = 100.0
    var playerHull: Float = 100.0
    var playerShieldHitTimer: Float = 0.0
    var weaponCapacitor: Float = 100.0
    var laserVisualTimer: Float = 0.0
    var cannonVisualTimer: Float = 0.0
    var cannonCooldown: Float = 0.0
    var hitMarkerTimer: Float = 0.0
    var totalKills: Int = 0

    // Callbacks into CommanderProfile
    var onDroneKilled: ((String, Bool) -> Void)?
    var onCanisterScooped: ((String, String, Bool) -> Void)?
    var onPlayerDestroyedRescue: (() -> Void)?

    // Visual tracer entities attached to root
    private var leftLaserBeam: ModelEntity?
    private var rightLaserBeam: ModelEntity?
    private var cannonTracerBolt: ModelEntity?
    private var enemyLaserBolt: ModelEntity?
    private var enemyLaserTimer: Float = 0.0

    // Haptics
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notifyHaptic = UINotificationFeedbackGenerator()

    func setupCombatEntities(into root: Entity) {
        guard drones.isEmpty else { return }

        let patrolCenter = SIMD3<Double>(-220.0, 45.0, -480.0)
        let ussCenter = SIMD3<Double>(-420.0, 130.0, -380.0)
        let specs: [(String, String, Bool, SIMD3<Double>, Float)] = [
            ("drone_1", "SF-D1 WASP", false, patrolCenter, 0.0),
            ("drone_2", "SF-D2 HORNET", false, patrolCenter, 2.09),
            ("drone_3", "SF-D3 MANTIS", false, patrolCenter, 4.18),
            ("drone_boss", "ACE VORTEX-1 [DREAD]", true, ussCenter, 1.05)
        ]

        for (id, name, isBoss, center, phase) in specs {
            let (entity, shieldSphere, explosionSphere) = Self.makeDroneEntity(name: name, isBoss: isBoss)
            root.addChild(entity)
            let instance = CombatDroneInstance(
                id: id,
                callsign: name,
                isBoss: isBoss,
                patrolCenter: center,
                orbitPhaseOffset: phase,
                rootEntity: entity,
                shieldBubbleEntity: shieldSphere,
                explosionEntity: explosionSphere
            )
            entity.components.set(WorldPositionComponent(instance.worldPosition))
            drones.append(instance)
        }

        // 2. Build Procedural 3D Mineable Asteroid Belt at (-380, -35, -640) & USS Crystalline pocket
        setupAsteroidBelt(into: root)

        // 3. Build 3D Loot & Ore Canister Pool (with starter salvage near Derelict Hulk & USS)
        setupLootCanisterPool(into: root)

        // 4. Build Living Friendly Traffic (Authority Enforcer, Heavy Trade Freighter, Belt Mining Barge)
        setupFriendlyTraffic(into: root)

        // 5. Build Forsaken Relay Hulk & Salvage Beacon at (480, -75, -560)
        let derelict = Self.makeDerelictRelayHulkEntity(worldPosition: SIMD3<Double>(480.0, -75.0, -560.0))
        root.addChild(derelict)

        // 6. Build Orbital Nav Beacon at (140, 110, -320)
        let beacon = Self.makeNavBeaconEntity(worldPosition: SIMD3<Double>(140.0, 110.0, -320.0))
        root.addChild(beacon)

        // 7. Build Weapon Beam & Tracer visuals
        let beamMesh = MeshResource.generateBox(size: SIMD3<Float>(0.22, 0.22, 240.0), cornerRadius: 0.08)
        let beamMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.95, blue: 1.0, alpha: 1.0))
        let lBeam = ModelEntity(mesh: beamMesh, materials: [beamMat])
        let rBeam = ModelEntity(mesh: beamMesh, materials: [beamMat])
        lBeam.isEnabled = false
        rBeam.isEnabled = false
        root.addChild(lBeam)
        root.addChild(rBeam)
        leftLaserBeam = lBeam
        rightLaserBeam = rBeam

        let boltMesh = MeshResource.generateSphere(radius: 0.65)
        let boltMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1.0))
        let bolt = ModelEntity(mesh: boltMesh, materials: [boltMat])
        bolt.isEnabled = false
        root.addChild(bolt)
        cannonTracerBolt = bolt

        let enemyBeamMesh = MeshResource.generateBox(size: SIMD3<Float>(0.32, 0.32, 180.0), cornerRadius: 0.10)
        let enemyBeamMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.18, blue: 0.20, alpha: 1.0))
        let eBolt = ModelEntity(mesh: enemyBeamMesh, materials: [enemyBeamMat])
        eBolt.isEnabled = false
        root.addChild(eBolt)
        enemyLaserBolt = eBolt
    }

    private func setupAsteroidBelt(into root: Entity) {
        let beltCenter = SIMD3<Double>(-380.0, -35.0, -640.0)
        let configs: [(String, String, String, SIMD3<Double>, Float, UIColor)] = [
            ("AST-01 TITANIUM", "titanium", "Titanium Ore", SIMD3<Double>(0, 0, 0), 9.5, UIColor(red: 0.52, green: 0.48, blue: 0.42, alpha: 1.0)),
            ("AST-02 CORE CRYSTAL", "painite_ore", "Core Crystal Ore", SIMD3<Double>(-65, 22, -45), 11.0, UIColor(red: 0.85, green: 0.32, blue: 0.24, alpha: 1.0)),
            ("AST-03 VOID OPAL", "void_opals", "Void Opal Crystals", SIMD3<Double>(58, -18, -52), 10.2, UIColor(red: 0.20, green: 0.88, blue: 0.96, alpha: 1.0)),
            ("AST-04 TITANIUM", "titanium", "Titanium Ore", SIMD3<Double>(-42, -28, 60), 8.8, UIColor(red: 0.48, green: 0.45, blue: 0.40, alpha: 1.0)),
            ("AST-05 CORE CRYSTAL", "painite_ore", "Core Crystal Ore", SIMD3<Double>(74, 30, 38), 12.0, UIColor(red: 0.88, green: 0.36, blue: 0.22, alpha: 1.0)),
            ("AST-06 VOID OPAL", "void_opals", "Void Opal Crystals", SIMD3<Double>(12, 42, -88), 9.6, UIColor(red: 0.22, green: 0.92, blue: 1.00, alpha: 1.0)),
            ("AST-07 TITANIUM", "titanium", "Titanium Ore", SIMD3<Double>(-88, 12, 18), 10.5, UIColor(red: 0.54, green: 0.50, blue: 0.44, alpha: 1.0)),
            ("AST-08 MOTHERLODE", "void_opals", "Void Opal Crystals", SIMD3<Double>(-40, 165, 240), 13.5, UIColor(red: 0.25, green: 0.95, blue: 1.00, alpha: 1.0))
        ]

        for (idx, cfg) in configs.enumerated() {
            let pos = beltCenter + cfg.3
            let entity = Self.makeAsteroidEntity(name: cfg.0, radius: cfg.4, veinColor: cfg.5)
            entity.components.set(WorldPositionComponent(pos))
            root.addChild(entity)

            let axis = simd_normalize(SIMD3<Float>(Float(idx % 3) + 0.3, 1.0, Float(idx % 2) - 0.5))
            let ast = MineableAsteroidInstance(
                id: "asteroid_\(idx)",
                name: cfg.0,
                commodityID: cfg.1,
                commodityLabel: cfg.2,
                worldPosition: pos,
                rootEntity: entity,
                spinAxis: axis,
                spinSpeed: 0.25 + Float(idx % 4) * 0.08
            )
            asteroids.append(ast)
        }
    }

    private func setupLootCanisterPool(into root: Entity) {
        for i in 0..<8 {
            let entity = Self.makeCanisterEntity(name: "LootCanister_\(i)")
            entity.isEnabled = false
            root.addChild(entity)
            let can = LootCanisterInstance(id: "canister_\(i)", rootEntity: entity)
            canisters.append(can)
        }

        // Seed 2 starter Ancient Salvage Core canisters near Forsaken Relay Hulk & USS
        spawnCanister(
            at: SIMD3<Double>(465.0, -68.0, -540.0),
            commodityID: "salvage_core",
            label: "Ancient Salvage Core",
            isMiningOre: false
        )
        spawnCanister(
            at: SIMD3<Double>(-405.0, 122.0, -365.0),
            commodityID: "salvage_core",
            label: "Ancient Salvage Core",
            isMiningOre: false
        )
    }

    private func setupFriendlyTraffic(into root: Entity) {
        let authEntity = Self.makeFriendlyShipEntity(
            name: "AUTH-ENFORCER 01",
            accentColor: UIColor(red: 0.18, green: 0.95, blue: 0.55, alpha: 1.0),
            scale: 2.3
        )
        root.addChild(authEntity)
        friendlyShips.append(
            FriendlyTrafficInstance(
                id: "friendly_auth_1",
                callsign: "AUTH-ENFORCER 01",
                roleBadge: "AUTHORITY POLICE",
                rootEntity: authEntity,
                pointA: SIMD3<Double>(-60.0, 25.0, -680.0),
                pointB: SIMD3<Double>(-200.0, 45.0, -480.0),
                speed: 46.0
            )
        )

        let haulerEntity = Self.makeFriendlyShipEntity(
            name: "CSV-DEMETER HAULER",
            accentColor: UIColor(red: 0.25, green: 0.85, blue: 1.00, alpha: 1.0),
            scale: 3.4
        )
        root.addChild(haulerEntity)
        friendlyShips.append(
            FriendlyTrafficInstance(
                id: "friendly_hauler_1",
                callsign: "CSV-DEMETER HAULER",
                roleBadge: "TRADE CONVOY",
                rootEntity: haulerEntity,
                pointA: SIMD3<Double>(140.0, 110.0, -320.0),
                pointB: SIMD3<Double>(0.0, 12.0, -760.0),
                speed: 32.0
            )
        )

        let minerEntity = Self.makeFriendlyShipEntity(
            name: "BARGE OPAL-7",
            accentColor: UIColor(red: 1.00, green: 0.78, blue: 0.22, alpha: 1.0),
            scale: 2.8
        )
        root.addChild(minerEntity)
        friendlyShips.append(
            FriendlyTrafficInstance(
                id: "friendly_miner_1",
                callsign: "BARGE OPAL-7",
                roleBadge: "MINING VESSEL",
                rootEntity: minerEntity,
                pointA: SIMD3<Double>(-340.0, -20.0, -600.0),
                pointB: SIMD3<Double>(-420.0, -40.0, -680.0),
                speed: 24.0
            )
        )
    }

    func spawnCanister(at position: SIMD3<Double>, commodityID: String, label: String, isMiningOre: Bool) {
        let slot = canisters.first(where: { !$0.isActive }) ?? canisters.first
        guard let can = slot else { return }
        can.commodityID = commodityID
        can.label = label
        can.isMiningOre = isMiningOre
        can.worldPosition = position
        can.isActive = true
        can.rootEntity.isEnabled = true
        can.rootEntity.components.set(WorldPositionComponent(position))
    }

    /// Manually tractor-scoops the nearest active canister within extended range (triggered from the EVE Overview).
    func tractorNearestCanister(playerWorldPos: SIMD3<Double>, maxRange: Double) -> Bool {
        var bestCan: LootCanisterInstance?
        var bestDist = maxRange
        for can in canisters where can.isActive {
            let d = simd_length(can.worldPosition - playerWorldPos)
            if d <= bestDist {
                bestDist = d
                bestCan = can
            }
        }
        guard let target = bestCan else { return false }
        target.isActive = false
        target.rootEntity.isEnabled = false
        onCanisterScooped?(target.commodityID, target.label, target.isMiningOre)
        return true
    }

    /// Returns the unit vector toward the locked target (drone or asteroid) in ship-local space (where forward is -Z).
    func lockedTargetShipLocalDirection(playerWorldPos: SIMD3<Double>, playerOrientation: simd_quatf) -> SIMD3<Float>? {
        if let aIdx = lockedAsteroidIndex, aIdx < asteroids.count, asteroids[aIdx].isIntact {
            let delta = asteroids[aIdx].worldPosition - playerWorldPos
            let len = simd_length(delta)
            guard len > 1.0 else { return nil }
            let unitWorld = SIMD3<Float>(Float(delta.x / len), Float(delta.y / len), Float(delta.z / len))
            return playerOrientation.inverse.act(unitWorld)
        }
        guard let idx = lockedDroneIndex, idx < drones.count, drones[idx].isAlive else { return nil }
        let delta = drones[idx].worldPosition - playerWorldPos
        let len = simd_length(delta)
        guard len > 1.0 else { return nil }
        let unitWorld = SIMD3<Float>(Float(delta.x / len), Float(delta.y / len), Float(delta.z / len))
        return playerOrientation.inverse.act(unitWorld)
    }

    func stepCombat(
        dt: Float,
        input: InputStateComponent,
        playerWorldPos: SIMD3<Double>,
        playerVelocity: SIMD3<Float>,
        playerOrientation: simd_quatf,
        originFrame: FloatingOriginFrame,
        weaponDamageMultiplier: Float = 1.0,
        shieldBonusMultiplier: Float = 1.0,
        tractorRangeMetres: Double = 140.0
    ) {
        // 1. Handle Power Distributor D-pad triggers
        if input.pipSYS { distributor.allocateSYS() }
        if input.pipENG { distributor.allocateENG() }
        if input.pipWEP { distributor.allocateWEP() }
        if input.pipReset { distributor.reset() }

        // 2. Handle Target Lock [X] & Subsystem Cycle [LB + X]
        if input.targetAheadTriggered {
            selectTargetNearestBoresight(playerWorldPos: playerWorldPos, playerOrientation: playerOrientation)
            CockpitAudioManager.shared.playTargetLock()
            lightImpact.impactOccurred()
        }
        if input.nextSubsystemTriggered {
            selectedSubsystemIndex = (selectedSubsystemIndex + 1) % CombatDroneInstance.subsystems.count
            lightImpact.impactOccurred()
        }

        if let idx = lockedDroneIndex, idx < drones.count, !drones[idx].isAlive {
            if let nextAlive = drones.firstIndex(where: { $0.isAlive }) {
                lockedDroneIndex = nextAlive
            }
        }

        // 3. Recharge player shields & weapon capacitor via SYS and WEP pips
        playerShieldHitTimer = max(0.0, playerShieldHitTimer - dt)
        playerShields = min(100.0, playerShields + 4.5 * distributor.shieldRegenMultiplier * shieldBonusMultiplier * dt)
        weaponCapacitor = min(100.0, weaponCapacitor + 16.5 * distributor.weaponRechargeMultiplier * dt)

        // 4. Step AI drones (including enemy return fire!)
        enemyLaserTimer = max(0.0, enemyLaserTimer - dt)
        if enemyLaserTimer <= 0.0 {
            enemyLaserBolt?.isEnabled = false
        }

        let forwardFloat = playerOrientation.act(SIMD3<Float>(0, 0, -1))
        for drone in drones {
            stepSingleDrone(
                drone: drone,
                dt: dt,
                playerWorldPos: playerWorldPos,
                originFrame: originFrame,
                shieldBonusMultiplier: shieldBonusMultiplier
            )
        }

        // 5. Step Mineable Asteroids
        for ast in asteroids {
            if ast.respawnTimer > 0.0 {
                ast.respawnTimer -= dt
                if ast.respawnTimer <= 0.0 {
                    ast.integrity = 100.0
                    ast.droppedHalfCanister = false
                    ast.rootEntity.isEnabled = true
                }
            } else {
                ast.spinAngle += ast.spinSpeed * dt
                ast.rootEntity.orientation = simd_quatf(angle: ast.spinAngle, axis: ast.spinAxis)
                ast.rootEntity.position = originFrame.localPosition(for: ast.worldPosition)
            }
        }

        // 6. Step Loot & Ore Canisters + Magnetic Tractor Beam Auto-Scoop
        for can in canisters where can.isActive {
            can.bobPhase += dt * 2.2
            let delta = playerWorldPos - can.worldPosition
            let dist = simd_length(delta)

            if dist <= tractorRangeMetres {
                // Pull canister toward ship with magnetic tractor beam
                let pullSpeed = max(55.0, Double(tractorRangeMetres) * 0.65)
                let stepDist = min(dist, pullSpeed * Double(dt))
                if dist < 16.0 {
                    can.isActive = false
                    can.rootEntity.isEnabled = false
                    onCanisterScooped?(can.commodityID, can.label, can.isMiningOre)
                    continue
                } else {
                    let dir = delta / max(1.0, dist)
                    can.worldPosition += dir * stepDist
                }
            }

            can.rootEntity.components.set(WorldPositionComponent(can.worldPosition))
            var localPos = originFrame.localPosition(for: can.worldPosition)
            localPos.y += sin(can.bobPhase) * 0.45
            can.rootEntity.position = localPos
            can.rootEntity.orientation = simd_quatf(angle: can.bobPhase * 0.8, axis: SIMD3<Float>(0, 1, 0))
        }

        // 7. Step Friendly Traffic (Authority Enforcer, Trade Convoy, Mining Barge)
        for ship in friendlyShips {
            let dest = ship.headingToB ? ship.pointB : ship.pointA
            let delta = dest - ship.worldPosition
            let dist = simd_length(delta)
            if dist < 24.0 {
                ship.headingToB.toggle()
            } else {
                let dir = delta / dist
                ship.worldPosition += dir * Double(ship.speed * dt)
                let fwd = SIMD3<Float>(Float(dir.x), Float(dir.y), Float(dir.z))
                ship.rootEntity.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: fwd)
            }
            ship.rootEntity.components.set(WorldPositionComponent(ship.worldPosition))
            ship.rootEntity.position = originFrame.localPosition(for: ship.worldPosition)
        }

        // 8. Handle Player Weapons with Gimbal Auto-Convergence (Drones & Mineable Asteroids)
        cannonCooldown = max(0.0, cannonCooldown - dt)
        hitMarkerTimer = max(0.0, hitMarkerTimer - dt)

        let playerLocal = originFrame.localPosition(for: playerWorldPos)

        var gimbalAimDir = forwardFloat
        var gimbalDroneIndex: Int?
        var gimbalAsteroidIndex: Int?
        var bestDot: Float = 0.925 // ~22° gimbal cone

        for (idx, drone) in drones.enumerated() where drone.isAlive {
            let deltaD = drone.worldPosition - playerWorldPos
            let dist = Float(simd_length(deltaD))
            guard dist < 1_150.0 && dist > 1.0 else { continue }
            let dirToDrone = SIMD3<Float>(Float(deltaD.x), Float(deltaD.y), Float(deltaD.z)) / dist
            let dot = simd_dot(forwardFloat, dirToDrone)
            let bonus: Float = (lockedDroneIndex == idx) ? 0.04 : 0.0
            if dot + bonus > bestDot {
                bestDot = dot + bonus
                gimbalAimDir = dirToDrone
                gimbalDroneIndex = idx
                gimbalAsteroidIndex = nil
            }
        }

        if gimbalDroneIndex == nil {
            for (idx, ast) in asteroids.enumerated() where ast.isIntact {
                let deltaA = ast.worldPosition - playerWorldPos
                let dist = Float(simd_length(deltaA))
                guard dist < 850.0 && dist > 1.0 else { continue }
                let dirToAst = SIMD3<Float>(Float(deltaA.x), Float(deltaA.y), Float(deltaA.z)) / dist
                let dot = simd_dot(forwardFloat, dirToAst)
                if dot > bestDot {
                    bestDot = dot
                    gimbalAimDir = dirToAst
                    gimbalAsteroidIndex = idx
                }
            }
        }

        let beamOrient = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: gimbalAimDir)

        // Primary Fire (RT): Gimbal-Assisted Dual Pulse Lasers (Combat & Thermal Mining)
        if input.primaryFireHeld && weaponCapacitor >= 2.5 {
            weaponCapacitor = max(0.0, weaponCapacitor - 17.0 * dt)
            laserVisualTimer = 0.06
            CockpitAudioManager.shared.playLaserPulse()

            let leftWingOrigin = playerLocal + playerOrientation.act(SIMD3<Float>(-2.1, -0.2, -2.0))
            let rightWingOrigin = playerLocal + playerOrientation.act(SIMD3<Float>(2.1, -0.2, -2.0))
            leftLaserBeam?.position = leftWingOrigin + gimbalAimDir * 120.0
            leftLaserBeam?.orientation = beamOrient
            leftLaserBeam?.isEnabled = true
            rightLaserBeam?.position = rightWingOrigin + gimbalAimDir * 120.0
            rightLaserBeam?.orientation = beamOrient
            rightLaserBeam?.isEnabled = true

            if let hitIdx = gimbalDroneIndex {
                applyDamage(
                    to: drones[hitIdx],
                    index: hitIdx,
                    shieldDmg: 72.0 * weaponDamageMultiplier * dt,
                    hullDmg: 38.0 * weaponDamageMultiplier * dt
                )
            } else if let astIdx = gimbalAsteroidIndex {
                applyMiningLaser(to: asteroids[astIdx], index: astIdx, damage: 46.0 * weaponDamageMultiplier * dt)
            }
        } else {
            laserVisualTimer = max(0.0, laserVisualTimer - dt)
            if laserVisualTimer <= 0.0 {
                leftLaserBeam?.isEnabled = false
                rightLaserBeam?.isEnabled = false
            }
        }

        // Secondary Fire (LT): Gimballed Multi-Cannons
        if input.secondaryFireHeld && weaponCapacitor >= 2.0 {
            weaponCapacitor = max(0.0, weaponCapacitor - 9.5 * dt)
            cannonVisualTimer = 0.05

            let tracerDist: Float = 38.0 + Float((Int(cannonCooldown * 1000) % 85))
            cannonTracerBolt?.position = playerLocal + gimbalAimDir * tracerDist
            cannonTracerBolt?.isEnabled = true

            if cannonCooldown <= 0.0 {
                cannonCooldown = 0.11
                CockpitAudioManager.shared.playCannonBurst()
                lightImpact.impactOccurred(intensity: 0.65)

                if let hitIdx = gimbalDroneIndex {
                    applyDamage(
                        to: drones[hitIdx],
                        index: hitIdx,
                        shieldDmg: 6.5 * weaponDamageMultiplier,
                        hullDmg: 15.5 * weaponDamageMultiplier
                    )
                } else if let astIdx = gimbalAsteroidIndex {
                    applyMiningLaser(to: asteroids[astIdx], index: astIdx, damage: 7.5 * weaponDamageMultiplier)
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
        lockedDroneIndex = index
        lockedAsteroidIndex = nil
        let scale: Float = drone.isBoss ? 0.55 : 1.0
        if drone.shields > 0.0 {
            drone.shields = max(0.0, drone.shields - shieldDmg * scale)
            drone.shieldHitFlashTimer = 0.20
            if drone.shields <= 25.0 {
                drone.state = .evadeWeave
            }
        } else {
            drone.hull = max(0.0, drone.hull - hullDmg * scale)
            if drone.hull <= 0.0 {
                drone.state = .destroyed
                drone.respawnTimer = drone.isBoss ? 14.0 : 6.0
                totalKills += 1
                CockpitAudioManager.shared.playExplosion()
                heavyImpact.impactOccurred()
                notifyHaptic.notificationOccurred(.success)
                // Spawn salvage canister at destroyed pirate position!
                spawnCanister(
                    at: drone.worldPosition,
                    commodityID: "salvage_core",
                    label: "Ancient Salvage Core",
                    isMiningOre: false
                )
                onDroneKilled?(drone.callsign, drone.isBoss)
            }
        }
    }

    private func applyMiningLaser(to asteroid: MineableAsteroidInstance, index: Int, damage: Float) {
        hitMarkerTimer = 0.16
        lockedAsteroidIndex = index
        asteroid.integrity = max(0.0, asteroid.integrity - damage)

        if asteroid.integrity <= 50.0 && !asteroid.droppedHalfCanister {
            asteroid.droppedHalfCanister = true
            let offset = SIMD3<Double>(Double.random(in: -14...14), Double.random(in: -10...10), Double.random(in: -14...14))
            spawnCanister(
                at: asteroid.worldPosition + offset,
                commodityID: asteroid.commodityID,
                label: asteroid.commodityLabel,
                isMiningOre: true
            )
            lightImpact.impactOccurred()
        }

        if asteroid.integrity <= 0.0 {
            asteroid.respawnTimer = 14.0
            asteroid.rootEntity.isEnabled = false
            let offset = SIMD3<Double>(Double.random(in: -12...12), Double.random(in: -8...8), Double.random(in: -12...12))
            spawnCanister(
                at: asteroid.worldPosition + offset,
                commodityID: asteroid.commodityID,
                label: asteroid.commodityLabel,
                isMiningOre: true
            )
            CockpitAudioManager.shared.playExplosion()
            heavyImpact.impactOccurred()
        }
    }

    private func stepSingleDrone(
        drone: CombatDroneInstance,
        dt: Float,
        playerWorldPos: SIMD3<Double>,
        originFrame: FloatingOriginFrame,
        shieldBonusMultiplier: Float
    ) {
        drone.aiClock += dt

        if drone.state == .destroyed {
            drone.respawnTimer -= dt
            drone.shieldBubbleEntity.isEnabled = false
            if drone.respawnTimer > (drone.isBoss ? 12.8 : 4.8) {
                let maxRespawn: Float = drone.isBoss ? 14.0 : 6.0
                let burstProgress = (maxRespawn - drone.respawnTimer) / 1.2
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

        drone.shieldHitFlashTimer = max(0.0, drone.shieldHitFlashTimer - dt)
        drone.shieldBubbleEntity.isEnabled = drone.shieldHitFlashTimer > 0.0
        if drone.shieldHitFlashTimer <= 0.0 && drone.shields < 100.0 {
            drone.shields = min(100.0, drone.shields + 2.2 * dt)
        }

        let distToPlayer = simd_length(playerWorldPos - drone.worldPosition)
        if drone.shields < 30.0 {
            drone.state = .evadeWeave
        } else if distToPlayer < 460.0 {
            drone.state = .strafeAttack
        } else {
            drone.state = .orbitPatrol
        }

        // Enemy Return Fire during Strafe Attack (< 420m)
        drone.attackCooldown = max(0.0, drone.attackCooldown - dt)
        if drone.state == .strafeAttack && distToPlayer < 420.0 && drone.attackCooldown <= 0.0 {
            drone.attackCooldown = drone.isBoss ? 1.85 : 2.65
            let playerLocal = originFrame.localPosition(for: playerWorldPos)
            let droneLocal = originFrame.localPosition(for: drone.worldPosition)
            let deltaLocal = playerLocal - droneLocal
            let len = max(1.0, simd_length(deltaLocal))
            let dirToPlayer = deltaLocal / len
            enemyLaserBolt?.position = (droneLocal + playerLocal) * 0.5
            enemyLaserBolt?.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: dirToPlayer)
            enemyLaserBolt?.isEnabled = true
            enemyLaserTimer = 0.14

            let rawDamage: Float = drone.isBoss ? 7.5 : 4.5
            let mitigated = (rawDamage * distributor.shieldDamageMitigation) / max(1.0, shieldBonusMultiplier)
            playerShieldHitTimer = 0.28
            CockpitAudioManager.shared.playShieldHit()

            if playerShields > 0.0 {
                playerShields = max(0.0, playerShields - mitigated)
            } else {
                playerHull = max(0.0, playerHull - mitigated * 0.75)
                if playerHull <= 0.0 {
                    playerShields = 100.0
                    playerHull = 100.0
                    onPlayerDestroyedRescue?()
                }
            }
        }

        let t = drone.aiClock * 0.32 + drone.orbitPhaseOffset
        let targetWorldPos: SIMD3<Double>
        let desiredSpeed: Float

        switch drone.state {
        case .orbitPatrol:
            targetWorldPos = drone.patrolCenter + SIMD3<Double>(
                Double(cos(t)) * 150.0,
                Double(sin(t * 1.1)) * 28.0,
                Double(sin(t)) * 150.0
            )
            desiredSpeed = 44.0

        case .strafeAttack:
            let strafeOffset = SIMD3<Double>(
                Double(cos(t * 1.1)) * 180.0,
                Double(sin(t * 1.4)) * 35.0,
                Double(sin(t * 1.1)) * 180.0
            )
            targetWorldPos = playerWorldPos + strafeOffset
            desiredSpeed = 54.0

        case .evadeWeave:
            let weaveOffset = SIMD3<Double>(
                Double(sin(t * 1.6)) * 210.0,
                Double(cos(t * 1.9)) * 55.0,
                Double(cos(t * 1.5)) * 210.0
            )
            targetWorldPos = drone.patrolCenter + weaveOffset
            desiredSpeed = 66.0

        case .destroyed:
            return
        }

        let toTarget = targetWorldPos - drone.worldPosition
        let dist = max(1.0, simd_length(toTarget))
        let dirDouble = toTarget / dist
        let desiredVel = SIMD3<Float>(Float(dirDouble.x), Float(dirDouble.y), Float(dirDouble.z)) * desiredSpeed

        drone.velocity += (desiredVel - drone.velocity) * min(1.0, dt * 2.2)
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
        lockedAsteroidIndex = nil
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
        lockedAsteroidIndex = nil
        CockpitAudioManager.shared.playTargetLock()
        lightImpact.impactOccurred()
    }

    /// Builds the live distance-sorted EVE Tactical Overview contact list across all local entities!
    func buildOverviewContacts(
        playerWorldPos: SIMD3<Double>,
        localWaypoints: [NavigationWaypoint]
    ) -> [OverviewContactItem] {
        var list: [OverviewContactItem] = []

        // 1. Active Loot & Ore Canisters (highest priority for quick tractoring)
        for can in canisters where can.isActive {
            let d = simd_length(can.worldPosition - playerWorldPos)
            list.append(
                OverviewContactItem(
                    id: can.id,
                    name: can.label.uppercased(),
                    typeBadge: can.isMiningOre ? "ORE CANISTER" : "SALVAGE CAN",
                    category: .miningLoot,
                    distanceMetres: d,
                    distanceText: NavigationWaypointManager.formatDistance(d),
                    worldPosition: can.worldPosition,
                    isHostile: false,
                    isCanister: true,
                    isAsteroid: false,
                    isStation: false,
                    droneIndex: nil,
                    waypointID: nil
                )
            )
        }

        // 2. Hostile Pirates
        for (idx, drone) in drones.enumerated() where drone.isAlive {
            let d = simd_length(drone.worldPosition - playerWorldPos)
            list.append(
                OverviewContactItem(
                    id: drone.id,
                    name: drone.callsign,
                    typeBadge: drone.isBoss ? "BOSS +25K CR" : "WANTED +12.5K",
                    category: .hostiles,
                    distanceMetres: d,
                    distanceText: NavigationWaypointManager.formatDistance(d),
                    worldPosition: drone.worldPosition,
                    isHostile: true,
                    isCanister: false,
                    isAsteroid: false,
                    isStation: false,
                    droneIndex: idx,
                    waypointID: nil
                )
            )
        }

        // 3. Mineable Asteroids (nearest 5 intact rocks)
        let sortedAsteroids = asteroids.filter(\.isIntact).sorted {
            simd_length($0.worldPosition - playerWorldPos) < simd_length($1.worldPosition - playerWorldPos)
        }
        for ast in sortedAsteroids.prefix(5) {
            let d = simd_length(ast.worldPosition - playerWorldPos)
            list.append(
                OverviewContactItem(
                    id: ast.id,
                    name: ast.name,
                    typeBadge: "ASTEROID \(Int(ast.integrity))%",
                    category: .miningLoot,
                    distanceMetres: d,
                    distanceText: NavigationWaypointManager.formatDistance(d),
                    worldPosition: ast.worldPosition,
                    isHostile: false,
                    isCanister: false,
                    isAsteroid: true,
                    isStation: false,
                    droneIndex: nil,
                    waypointID: nil
                )
            )
        }

        // 4. Local Sector Waypoints (Station, Belt, HazRES, Hulk, Nav Beacon, USS)
        for wp in localWaypoints {
            let d = simd_length(wp.worldPosition - playerWorldPos)
            list.append(
                OverviewContactItem(
                    id: wp.id,
                    name: wp.name.uppercased(),
                    typeBadge: wp.kind.rawValue,
                    category: .navTraffic,
                    distanceMetres: d,
                    distanceText: NavigationWaypointManager.formatDistance(d),
                    worldPosition: wp.worldPosition,
                    isHostile: false,
                    isCanister: false,
                    isAsteroid: false,
                    isStation: wp.kind == .station,
                    droneIndex: nil,
                    waypointID: wp.id
                )
            )
        }

        // 5. Friendly AI Traffic
        for ship in friendlyShips {
            let d = simd_length(ship.worldPosition - playerWorldPos)
            list.append(
                OverviewContactItem(
                    id: ship.id,
                    name: ship.callsign,
                    typeBadge: ship.roleBadge,
                    category: .navTraffic,
                    distanceMetres: d,
                    distanceText: NavigationWaypointManager.formatDistance(d),
                    worldPosition: ship.worldPosition,
                    isHostile: false,
                    isCanister: false,
                    isAsteroid: false,
                    isStation: false,
                    droneIndex: nil,
                    waypointID: nil
                )
            )
        }

        return list.sorted { $0.distanceMetres < $1.distanceMetres }
    }

    // MARK: - 3D Entity Builders

    private static func makeDroneEntity(name: String, isBoss: Bool) -> (Entity, ModelEntity, ModelEntity) {
        let root = Entity()
        root.name = name
        root.scale = SIMD3<Float>(repeating: isBoss ? 3.1 : 2.2)

        var armorMat = SimpleMaterial()
        let baseDroneTint = isBoss
            ? UIColor(red: 0.56, green: 0.24, blue: 0.28, alpha: 1.0)
            : UIColor(red: 0.58, green: 0.64, blue: 0.75, alpha: 1.0)
        if let hullTex = SolSceneBuilder.loadAssetTexture("tex_ship_hull_plating") {
            armorMat.color = .init(tint: baseDroneTint, texture: .init(hullTex))
        } else {
            armorMat.color = .init(tint: baseDroneTint)
        }
        armorMat.roughness = .init(floatLiteral: 0.32)
        armorMat.metallic = .init(floatLiteral: 0.85)
        let crimsonMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.22, blue: 0.18, alpha: 1.0))
        let amberMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1.0))

        let coreMesh = MeshResource.generateBox(size: SIMD3<Float>(2.6, 1.2, 5.2), cornerRadius: 0.35)
        let core = ModelEntity(mesh: coreMesh, materials: [armorMat])
        root.addChild(core)

        let wingMesh = MeshResource.generateBox(size: SIMD3<Float>(8.0, 0.26, 2.4), cornerRadius: 0.10)
        let wings = ModelEntity(mesh: wingMesh, materials: [armorMat])
        wings.position = SIMD3<Float>(0, 0, 0.3)
        root.addChild(wings)

        let tipMesh = MeshResource.generateSphere(radius: 0.42)
        let leftTip = ModelEntity(mesh: tipMesh, materials: [amberMat])
        leftTip.position = SIMD3<Float>(-4.0, 0, 0.3)
        root.addChild(leftTip)

        let rightTip = ModelEntity(mesh: tipMesh, materials: [amberMat])
        rightTip.position = SIMD3<Float>(4.0, 0, 0.3)
        root.addChild(rightTip)

        let eyeMesh = MeshResource.generateSphere(radius: 0.72)
        let eye = ModelEntity(mesh: eyeMesh, materials: [crimsonMat])
        eye.position = SIMD3<Float>(0, 0.18, -2.3)
        root.addChild(eye)

        let thrusterGlow = ModelEntity(mesh: eyeMesh, materials: [crimsonMat])
        thrusterGlow.position = SIMD3<Float>(0, 0.0, 2.7)
        root.addChild(thrusterGlow)

        let shieldMesh = MeshResource.generateSphere(radius: 4.8)
        var shieldMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.85, blue: 1.0, alpha: 1.0))
        shieldMat.blending = .transparent(opacity: .init(floatLiteral: 0.38))
        let shieldSphere = ModelEntity(mesh: shieldMesh, materials: [shieldMat])
        shieldSphere.isEnabled = false
        root.addChild(shieldSphere)

        let expMesh = MeshResource.generateSphere(radius: 2.0)
        var expMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1.0))
        expMat.blending = .transparent(opacity: .init(floatLiteral: 0.78))
        let expSphere = ModelEntity(mesh: expMesh, materials: [expMat])
        expSphere.isEnabled = false
        root.addChild(expSphere)

        return (root, shieldSphere, expSphere)
    }

    private static func makeFriendlyShipEntity(name: String, accentColor: UIColor, scale: Float) -> Entity {
        let root = Entity()
        root.name = name
        root.scale = SIMD3<Float>(repeating: scale)

        var hullMat = SimpleMaterial()
        if let hullTex = SolSceneBuilder.loadAssetTexture("tex_ship_hull_plating") {
            hullMat.color = .init(tint: UIColor(red: 0.65, green: 0.76, blue: 0.88, alpha: 1.0), texture: .init(hullTex))
        } else {
            hullMat.color = .init(tint: UIColor(red: 0.24, green: 0.30, blue: 0.38, alpha: 1.0))
        }
        hullMat.roughness = .init(floatLiteral: 0.35)
        hullMat.metallic = .init(floatLiteral: 0.85)
        let glowMat = UnlitMaterial(color: accentColor)

        let hullMesh = MeshResource.generateBox(size: SIMD3<Float>(3.2, 1.6, 6.8), cornerRadius: 0.45)
        let hull = ModelEntity(mesh: hullMesh, materials: [hullMat])
        root.addChild(hull)

        let wingMesh = MeshResource.generateBox(size: SIMD3<Float>(6.5, 0.3, 2.2), cornerRadius: 0.12)
        let wing = ModelEntity(mesh: wingMesh, materials: [hullMat])
        root.addChild(wing)

        let strobeMesh = MeshResource.generateSphere(radius: 0.55)
        let leftStrobe = ModelEntity(mesh: strobeMesh, materials: [glowMat])
        leftStrobe.position = SIMD3<Float>(-3.2, 0.0, 0.0)
        root.addChild(leftStrobe)

        let rightStrobe = ModelEntity(mesh: strobeMesh, materials: [glowMat])
        rightStrobe.position = SIMD3<Float>(3.2, 0.0, 0.0)
        root.addChild(rightStrobe)

        let engineGlow = ModelEntity(mesh: strobeMesh, materials: [glowMat])
        engineGlow.position = SIMD3<Float>(0.0, 0.0, 3.5)
        root.addChild(engineGlow)

        return root
    }

    private static func makeAsteroidEntity(name: String, radius: Float, veinColor: UIColor) -> Entity {
        let root = Entity()
        root.name = name

        var rockMat = SimpleMaterial()
        if let rockTex = SolSceneBuilder.loadAssetTexture("tex_moon_cratered") {
            rockMat.color = .init(tint: UIColor(red: 0.72, green: 0.68, blue: 0.64, alpha: 1.0), texture: .init(rockTex))
        } else {
            rockMat.color = .init(tint: UIColor(red: 0.32, green: 0.30, blue: 0.28, alpha: 1.0))
        }
        rockMat.roughness = .init(floatLiteral: 0.88)
        rockMat.metallic = .init(floatLiteral: 0.05)
        let crystalMat = UnlitMaterial(color: veinColor)

        let mainMesh = MeshResource.generateBox(
            size: SIMD3<Float>(radius * 1.6, radius * 1.2, radius * 1.4),
            cornerRadius: radius * 0.42
        )
        let mainRock = ModelEntity(mesh: mainMesh, materials: [rockMat])
        root.addChild(mainRock)

        let subMesh = MeshResource.generateBox(
            size: SIMD3<Float>(radius * 1.1, radius * 1.5, radius * 1.1),
            cornerRadius: radius * 0.35
        )
        let subRock = ModelEntity(mesh: subMesh, materials: [rockMat])
        subRock.orientation = simd_quatf(angle: 0.65, axis: simd_normalize(SIMD3<Float>(1, 1, 0.5)))
        root.addChild(subRock)

        // Glowing mineral crystal nodes on surface so mineable rocks stand out visually
        let crystalMesh = MeshResource.generateSphere(radius: radius * 0.32)
        let nodeA = ModelEntity(mesh: crystalMesh, materials: [crystalMat])
        nodeA.position = SIMD3<Float>(radius * 0.65, radius * 0.35, 0)
        root.addChild(nodeA)

        let nodeB = ModelEntity(mesh: crystalMesh, materials: [crystalMat])
        nodeB.position = SIMD3<Float>(-radius * 0.55, -radius * 0.30, radius * 0.45)
        root.addChild(nodeB)

        return root
    }

    private static func makeCanisterEntity(name: String) -> Entity {
        let root = Entity()
        root.name = name

        let coreGlow = UnlitMaterial(color: UIColor(red: 0.20, green: 1.00, blue: 0.78, alpha: 1.0))
        let frameMat = SimpleMaterial(
            color: UIColor(red: 0.92, green: 0.72, blue: 0.22, alpha: 1.0),
            roughness: 0.25,
            isMetallic: true
        )

        let bodyMesh = MeshResource.generateBox(size: SIMD3<Float>(2.2, 2.2, 3.8), cornerRadius: 0.6)
        let body = ModelEntity(mesh: bodyMesh, materials: [frameMat])
        root.addChild(body)

        let beaconMesh = MeshResource.generateSphere(radius: 1.6)
        let beacon = ModelEntity(mesh: beaconMesh, materials: [coreGlow])
        root.addChild(beacon)

        return root
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

        let spineMesh = MeshResource.generateBox(size: SIMD3<Float>(8.0, 8.0, 46.0), cornerRadius: 1.0)
        let spine = ModelEntity(mesh: spineMesh, materials: [rustedHull])
        spine.orientation = simd_quatf(angle: 0.35, axis: simd_normalize(SIMD3<Float>(1, 0.5, 0.2)))
        hulkRoot.addChild(spine)

        let panelMesh = MeshResource.generateBox(size: SIMD3<Float>(38.0, 0.6, 12.0))
        let panelA = ModelEntity(mesh: panelMesh, materials: [brokenPanel])
        panelA.position = SIMD3<Float>(-14.0, 4.0, -6.0)
        panelA.orientation = simd_quatf(angle: -0.42, axis: SIMD3<Float>(0, 1, 1))
        hulkRoot.addChild(panelA)

        let panelB = ModelEntity(mesh: panelMesh, materials: [brokenPanel])
        panelB.position = SIMD3<Float>(16.0, -5.0, 8.0)
        panelB.orientation = simd_quatf(angle: 0.55, axis: SIMD3<Float>(1, 0, 1))
        hulkRoot.addChild(panelB)

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
