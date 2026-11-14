import SwiftUI
import RealityKit
import simd
import StarfallGalaxy

enum AutopilotFlightMode: Sendable {
    case manual
    case approach(name: String, targetPos: SIMD3<Double>)
    case orbit500m(name: String, centerPos: SIMD3<Double>)

    var statusText: String {
        switch self {
        case .manual:
            return ""
        case .approach(let name, _):
            return "AUTO: APPROACH \(name)"
        case .orbit500m(let name, _):
            return "AUTO: ORBIT 500M \(name)"
        }
    }
}

@MainActor
final class SceneController: ObservableObject {
    let rootEntity = Entity()
    let cameraEntity = Entity()
    var skyboxEntity: Entity?
    var builtShip: ShipEntityBuilder.BuiltShip?
    var solEnv: SolSceneBuilder.BuiltSolEnvironment?
    var updateSubscription: EventSubscription?

    let combat = CombatSystemManager()

    // Fixed 60 Hz simulation state
    @Published var flight = FlightComponent()
    var playerWorldPos = WorldPositionComponent(.zero)
    var originFrame = FloatingOriginFrame(originWorldPosition: .zero, thresholdMetres: 2_000.0)
    var fixedAccumulator: Double = 0.0
    var stationRotationAngle: Float = 0.0

    // EVE Tactical Autopilot state
    var autopilotMode: AutopilotFlightMode = .manual
    var orbitPhaseAngle: Float = 0.0

    // Frame Shift Drive (Supercruise & Hyperspace Witch-Space) state
    var fsdCountdown: Float = 0.0
    var pendingFSDWaypoint: NavigationWaypoint?
    var hyperspaceTimer: Float = 0.0
    var pendingHyperspaceSystem: SystemSummary?

    // Camera & viewport state for true perspective 3D->2D projection
    var cameraMode: ShipCameraMode = .cockpit
    var chaseOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var currentFOV: Float = 60.0
    var viewportSize: CGSize = CGSize(width: 1180, height: 820)
    var freeLookYaw: Float = 0.0
    var freeLookPitch: Float = 0.0
    var dragStartYaw: Float = 0.0
    var dragStartPitch: Float = 0.0
    var isDragging: Bool = false

    func setupSceneIfNeeded(commander: CommanderProfile, navManager: NavigationWaypointManager) {
        guard rootEntity.children.isEmpty else { return }
        WorldPositionComponent.registerComponent()
        PlanetaryBodyComponent.registerComponent()
        FlightComponent.registerComponent()
        InputStateComponent.registerComponent()

        rootEntity.name = "StarfallSpaceRoot"

        // 1. Starfield skybox
        let skybox = StarfieldGenerator.makeSkyboxEntity()
        rootEntity.addChild(skybox)
        skyboxEntity = skybox

        // 2. Sol / Current system environment
        let env = SolSceneBuilder.buildSolEnvironment(into: rootEntity)
        solEnv = env

        // 3. Combat drones, Asteroid Belt, Loot Canisters, Friendly Traffic & Weapon Tracers
        combat.setupCombatEntities(into: rootEntity)
        combat.onDroneKilled = { [weak commander] callsign, isBoss in
            commander?.recordPirateKill(callsign: callsign, isBoss: isBoss)
        }
        combat.onCanisterScooped = { [weak commander] commodityID, label, isMiningOre in
            commander?.collectCanister(commodityID: commodityID, label: label, isMiningOre: isMiningOre)
        }
        combat.onPlayerDestroyedRescue = { [weak self, weak commander, weak navManager] in
            guard let self, let commander, let navManager else { return }
            self.dockAtPrimaryStation(commander: commander, navManager: navManager)
            commander.postBanner("EMERGENCY ESCAPE POD RECOVERED • SHIP RESTORED AT \(navManager.primaryStationName.uppercased())", duration: 5.0)
        }

        // 4. Player starfighter (built from Commander's active Shipyard hull)
        rebuildPlayerShip(hull: commander.activeHull)

        // 5. Virtual perspective camera
        cameraEntity.name = "MainVirtualCamera"
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = 60.0
        cameraEntity.components.set(camera)
        rootEntity.addChild(cameraEntity)

        // Restore saved star system if commander was in another system
        let savedID = SystemID(rawValue: commander.data.currentSystemRawID)
        if savedID != navManager.currentSystem.id {
            navManager.loadSystem(systemID: savedID)
        }
        if var currentEnv = solEnv {
            SolSceneBuilder.applySystemVisuals(to: &currentEnv, system: navManager.currentSystem)
            solEnv = currentEnv
        }

        applyCameraModeVisibility()
        syncSceneTransforms(dt: 1.0 / 60.0)
    }

    func rebuildPlayerShip(hull: ShipHullCatalogItem) {
        builtShip?.root.removeFromParent()
        let newShip = ShipEntityBuilder.makeShip(hullID: hull.id)
        rootEntity.addChild(newShip.root)
        builtShip = newShip
        flight.spec = hull.flightSpec
        applyCameraModeVisibility()
    }

    func toggleCameraMode() {
        cameraMode = (cameraMode == .cockpit) ? .chase : .cockpit
        freeLookYaw = 0.0
        freeLookPitch = 0.0
        applyCameraModeVisibility()
    }

    func selectOverviewContact(_ item: OverviewContactItem, navManager: NavigationWaypointManager, commander: CommanderProfile) {
        CockpitAudioManager.shared.playTargetLock()
        if let dIdx = item.droneIndex {
            combat.lockedDroneIndex = dIdx
            combat.lockedAsteroidIndex = nil
            commander.postBanner("OVERVIEW TARGET LOCKED: \(item.name)")
        } else if let wpID = item.waypointID, let wp = navManager.localWaypoints.first(where: { $0.id == wpID }) {
            navManager.selectWaypoint(wp)
            commander.postBanner("WAYPOINT LOCKED: \(wp.name.uppercased())")
        } else {
            commander.postBanner("OVERVIEW SELECTED: \(item.name) (\(item.distanceText))")
        }
    }

    func engageOverviewApproach(_ item: OverviewContactItem, inputManager: ControllerInputManager, commander: CommanderProfile) {
        autopilotMode = .approach(name: item.name, targetPos: item.worldPosition)
        inputManager.setThrottle(0.54)
        CockpitAudioManager.shared.playTargetLock()
        commander.postBanner("AUTOPILOT: APPROACHING \(item.name) AT BLUE-ZONE SPEED")
    }

    func engageOverviewOrbit(_ item: OverviewContactItem, inputManager: ControllerInputManager, commander: CommanderProfile) {
        autopilotMode = .orbit500m(name: item.name, centerPos: item.worldPosition)
        inputManager.setThrottle(0.52)
        CockpitAudioManager.shared.playTargetLock()
        commander.postBanner("AUTOPILOT: ORBITING \(item.name) AT 500M")
    }

    func initiateFSDJump(to waypoint: NavigationWaypoint, commander: CommanderProfile) {
        autopilotMode = .manual
        if let targetSys = waypoint.targetSystem {
            pendingHyperspaceSystem = targetSys
            pendingFSDWaypoint = waypoint
            fsdCountdown = 3.2
            CockpitAudioManager.shared.playFSDCharge()
            commander.postBanner("FRAME SHIFT DRIVE CHARGING → \(targetSys.name.uppercased())", duration: 3.5)
        } else if waypoint.supportsLocalJump {
            pendingHyperspaceSystem = nil
            pendingFSDWaypoint = waypoint
            fsdCountdown = 2.0
            CockpitAudioManager.shared.playFSDCharge()
            commander.postBanner("SUPERCRUISE CHARGING → \(waypoint.name.uppercased())", duration: 2.5)
        }
    }

    private func completeLocalSupercruiseDrop(to waypoint: NavigationWaypoint, commander: CommanderProfile) {
        let offset = SIMD3<Double>(0.0, 16.0, 210.0)
        playerWorldPos.position = waypoint.worldPosition + offset
        let toDest = waypoint.worldPosition - playerWorldPos.position
        let dist = max(1.0, simd_length(toDest))
        let fwd = SIMD3<Float>(Float(toDest.x / dist), Float(toDest.y / dist), Float(toDest.z / dist))
        flight.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: fwd)
        chaseOrientation = flight.orientation
        flight.angularVelocity = .zero
        flight.velocity = fwd * 75.0
        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)
        syncSceneTransforms(dt: 1.0 / 60.0)
        CockpitAudioManager.shared.playHyperspaceBoom()
        commander.postBanner("DROPPED FROM SUPERCRUISE AT \(waypoint.name.uppercased())", duration: 3.5)
    }

    func dockAtPrimaryStation(commander: CommanderProfile, navManager: NavigationWaypointManager) {
        autopilotMode = .manual
        flight.velocity = .zero
        flight.angularVelocity = .zero
        combat.playerShields = 100.0
        combat.playerHull = 100.0
        commander.dockedStationName = navManager.primaryStationName
        commander.isDocked = true
        CockpitAudioManager.shared.playTractorScoop()
        commander.postBanner("DOCKING COMPLETE • WELCOME TO \(navManager.primaryStationName.uppercased())")
    }

    func launchFromStation(commander: CommanderProfile) {
        autopilotMode = .manual
        commander.isDocked = false
        playerWorldPos.position = SIMD3<Double>(0.0, 10.0, -420.0)
        flight.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        chaseOrientation = flight.orientation
        flight.velocity = flight.forwardVector * 75.0
        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)
        syncSceneTransforms(dt: 1.0 / 60.0)
        CockpitAudioManager.shared.playBoostSurge()
        commander.postBanner("LAUNCH CLEARANCE GRANTED • CLEAR STATION PERIMETER", duration: 4.0)
    }

    private func applyCameraModeVisibility() {
        guard let ship = builtShip else { return }
        switch cameraMode {
        case .cockpit:
            ship.exteriorRoot.isEnabled = false
            ship.cockpitInteriorRoot.isEnabled = true
        case .chase:
            ship.exteriorRoot.isEnabled = true
            ship.cockpitInteriorRoot.isEnabled = false
        }
    }

    func stepFrame(
        deltaTime: TimeInterval,
        input: InputStateComponent,
        navManager: NavigationWaypointManager,
        commander: CommanderProfile,
        onToggleNavMap: () -> Void
    ) -> FlightHUDTelemetry {
        let clampedDT = min(max(deltaTime, 0.001), 0.1)
        let fdt = Float(clampedDT)

        navManager.jumpRangeLY = commander.jumpRangeLY

        if commander.statusBannerTimer > 0.0 {
            commander.statusBannerTimer = max(0.0, commander.statusBannerTimer - fdt)
            if commander.statusBannerTimer <= 0.0 {
                commander.statusBannerMessage = "SYSTEMS NOMINAL • BLUE THROTTLE ZONE = +35% AGILITY"
            }
        }

        commander.stepCommsTicker(
            dt: fdt,
            systemName: navManager.currentSystem.name,
            stationName: navManager.primaryStationName,
            securityText: navManager.primarySecurityText
        )

        // Handle active FSD charging & Witch-Space Hyperspace Tunnel
        if fsdCountdown > 0.0 {
            fsdCountdown = max(0.0, fsdCountdown - fdt)
            if fsdCountdown <= 0.0 {
                if pendingHyperspaceSystem != nil {
                    hyperspaceTimer = 2.8
                    CockpitAudioManager.shared.playHyperspaceBoom()
                } else if let wp = pendingFSDWaypoint {
                    pendingFSDWaypoint = nil
                    completeLocalSupercruiseDrop(to: wp, commander: commander)
                }
            }
        } else if hyperspaceTimer > 0.0 {
            hyperspaceTimer = max(0.0, hyperspaceTimer - fdt)
            if hyperspaceTimer <= 0.0, let destSys = pendingHyperspaceSystem {
                pendingHyperspaceSystem = nil
                pendingFSDWaypoint = nil
                navManager.loadSystem(systemID: destSys.id)
                if var currentEnv = solEnv {
                    SolSceneBuilder.applySystemVisuals(to: &currentEnv, system: navManager.currentSystem)
                    solEnv = currentEnv
                }
                commander.data.currentSystemRawID = destSys.id.rawValue
                commander.data.systemsVisited += 1
                commander.saveToDisk()
                playerWorldPos.position = .zero
                flight.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                chaseOrientation = flight.orientation
                flight.velocity = flight.forwardVector * 70.0
                originFrame.updateIfNeeded(playerWorldPosition: .zero)
                CockpitAudioManager.shared.playHyperspaceBoom()
                commander.postBanner("ARRIVED IN \(destSys.name.uppercased()) SYSTEM (\(navManager.primarySecurityText))", duration: 5.0)
                commander.postRadioComms(
                    sender: "\(navManager.primaryStationName.uppercased()) CONTROL",
                    message: "Welcome to \(destSys.name), Commander. Docking bays are open."
                )
            }
        }

        if commander.isDocked {
            return buildHUDTelemetry(input: input, navManager: navManager, commander: commander)
        }

        if input.cameraToggleTriggered {
            toggleCameraMode()
        }
        if input.galaxyMapTriggered {
            onToggleNavMap()
        }
        if input.boostTriggered && flight.canBoost {
            CockpitAudioManager.shared.playBoostSurge()
        }

        // Manual stick movement disengages EVE Autopilot
        if abs(input.pitch) > 0.18 || abs(input.yaw) > 0.18 {
            autopilotMode = .manual
        }

        // Free-look via Hold LB + Right Stick
        if input.isModifierHeld {
            freeLookYaw = min(max(freeLookYaw - input.lookYaw * fdt * 1.8, -1.2), 1.2)
            freeLookPitch = min(max(freeLookPitch + input.lookPitch * fdt * 1.5, -0.9), 0.9)
        } else if !isDragging {
            freeLookYaw *= max(0.0, 1.0 - fdt * 6.0)
            freeLookPitch *= max(0.0, 1.0 - fdt * 6.0)
        }

        // Compute target assist or EVE Autopilot steering direction in ship-local space
        let engSpeedMult = combat.distributor.engineSpeedMultiplier * commander.thrusterBonusMultiplier
        let boostChargeMult = combat.distributor.boostRechargeMultiplier
        var targetAssistDir = combat.lockedTargetShipLocalDirection(
            playerWorldPos: playerWorldPos.position,
            playerOrientation: flight.orientation
        )

        switch autopilotMode {
        case .manual:
            break
        case .approach(_, let targetPos):
            let delta = targetPos - playerWorldPos.position
            let dist = simd_length(delta)
            if dist < 85.0 {
                autopilotMode = .manual
            } else {
                let unitW = SIMD3<Float>(Float(delta.x / dist), Float(delta.y / dist), Float(delta.z / dist))
                targetAssistDir = flight.orientation.inverse.act(unitW)
            }
        case .orbit500m(_, let centerPos):
            orbitPhaseAngle += fdt * 0.25
            let orbitPt = centerPos + SIMD3<Double>(
                Double(cos(orbitPhaseAngle)) * 220.0,
                15.0,
                Double(sin(orbitPhaseAngle)) * 220.0
            )
            let delta = orbitPt - playerWorldPos.position
            let dist = max(1.0, simd_length(delta))
            let unitW = SIMD3<Float>(Float(delta.x / dist), Float(delta.y / dist), Float(delta.z / dist))
            targetAssistDir = flight.orientation.inverse.act(unitW)
        }

        fixedAccumulator += clampedDT
        var tickInput = input
        if case .manual = autopilotMode {
            // keep user's autoTrackEnabled
        } else {
            tickInput.autoTrackEnabled = true
        }
        var steps = 0
        while fixedAccumulator >= FlightPhysics.fixedTimeStep && steps < 6 {
            FlightPhysics.stepFixedTick(
                flight: &flight,
                input: tickInput,
                worldPosition: &playerWorldPos,
                dt: Float(FlightPhysics.fixedTimeStep),
                engineSpeedMultiplier: engSpeedMult,
                boostRechargeMultiplier: boostChargeMult,
                targetAssistLocalDir: targetAssistDir
            )
            tickInput.boostTriggered = false
            fixedAccumulator -= FlightPhysics.fixedTimeStep
            steps += 1
        }

        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)

        // Check mail-slot automatic docking when player flies into the glowing cyan docking slot (< 45m from slot at (0, 0, -852))
        let mailSlotWorldPos = SIMD3<Double>(0.0, 0.0, -852.0)
        if simd_length(playerWorldPos.position - mailSlotWorldPos) < 42.0 && flight.speed < 140.0 {
            dockAtPrimaryStation(commander: commander, navManager: navManager)
        }

        // Step combat drones, asteroid belt mining, canisters, friendly traffic & power distributor pips
        combat.stepCombat(
            dt: fdt,
            input: input,
            playerWorldPos: playerWorldPos.position,
            playerVelocity: flight.velocity,
            playerOrientation: flight.orientation,
            originFrame: originFrame,
            weaponDamageMultiplier: commander.weaponBonusMultiplier,
            shieldBonusMultiplier: commander.shieldBonusMultiplier,
            tractorRangeMetres: commander.tractorRangeMetres
        )

        stationRotationAngle += fdt * 0.16
        if stationRotationAngle > .pi * 2.0 {
            stationRotationAngle -= .pi * 2.0
        }
        solEnv?.rotatingWheelEntity.orientation = simd_quatf(angle: stationRotationAngle, axis: SIMD3<Float>(0, 0, 1))

        syncSceneTransforms(dt: fdt)

        return buildHUDTelemetry(input: input, navManager: navManager, commander: commander)
    }

    private func syncSceneTransforms(dt: Float) {
        let playerLocal = originFrame.localPosition(for: playerWorldPos.position)

        skyboxEntity?.position = playerLocal

        if let ship = builtShip {
            ship.root.position = playerLocal
            ship.root.orientation = flight.orientation
            ship.root.components.set(flight)
            ship.root.components.set(playerWorldPos)

            let thrustLevel: Float = flight.isBoosting ? 1.65 : max(0.18, min(1.0, flight.speed / max(1.0, flight.spec.maxSpeed)))
            let plumeScale = SIMD3<Float>(
                0.75 + 0.35 * thrustLevel,
                0.55 + 0.35 * thrustLevel,
                0.90 + 2.40 * thrustLevel
            )
            ship.leftPlume.scale = plumeScale
            ship.rightPlume.scale = plumeScale
        }

        for child in rootEntity.children where child !== builtShip?.root {
            if let wp = child.components[WorldPositionComponent.self] {
                child.position = originFrame.localPosition(for: wp.position)
            }
        }

        if let env = solEnv {
            for planet in env.planetaryEntities {
                guard let body = planet.components[PlanetaryBodyComponent.self] else { continue }
                let delta = body.worldPosition - playerWorldPos.position
                let dist = max(body.trueRadiusMetres * 1.05, simd_length(delta))
                let dirDouble = delta / dist
                let dirFloat = SIMD3<Float>(Float(dirDouble.x), Float(dirDouble.y), Float(dirDouble.z))

                planet.position = playerLocal + dirFloat * body.proxyDistanceMetres
                let angularRadius = Float(body.trueRadiusMetres / dist) * body.proxyDistanceMetres
                planet.scale = SIMD3<Float>(repeating: max(0.5, angularRadius))
            }

            let boxSpan: Float = 140.0
            let halfSpan: Float = boxSpan * 0.5
            let pW = playerWorldPos.position
            for (idx, mote) in env.dustParticles.enumerated() {
                let seedOffset = env.dustOffsets[idx]
                let rx = Self.wrapCoord(Float(pW.x.truncatingRemainder(dividingBy: Double(boxSpan))) - seedOffset.x, halfSpan: halfSpan)
                let ry = Self.wrapCoord(Float(pW.y.truncatingRemainder(dividingBy: Double(boxSpan))) - seedOffset.y, halfSpan: halfSpan)
                let rz = Self.wrapCoord(Float(pW.z.truncatingRemainder(dividingBy: Double(boxSpan))) - seedOffset.z, halfSpan: halfSpan)
                mote.position = playerLocal - SIMD3<Float>(rx, ry, rz)
            }
        }

        let targetFOV: Float = (flight.isBoosting || hyperspaceTimer > 0.0) ? 72.0 : 60.0
        currentFOV += (targetFOV - currentFOV) * min(1.0, dt * 6.0)
        var camComp = PerspectiveCameraComponent()
        camComp.fieldOfViewInDegrees = currentFOV
        cameraEntity.components.set(camComp)

        let lookQuat = simd_mul(
            simd_quatf(angle: freeLookYaw, axis: SIMD3<Float>(0, 1, 0)),
            simd_quatf(angle: freeLookPitch, axis: SIMD3<Float>(1, 0, 0))
        )

        switch cameraMode {
        case .cockpit:
            let gOffset = SIMD3<Float>(
                min(max(-flight.localGForce.x * 0.012, -0.06), 0.06),
                min(max(-flight.localGForce.y * 0.012, -0.05), 0.05),
                min(max(flight.localGForce.z * 0.015, -0.06), 0.08)
            )
            let seatLocal = SIMD3<Float>(0.0, 0.08, -0.25) + gOffset
            cameraEntity.position = playerLocal + flight.orientation.act(seatLocal)
            cameraEntity.orientation = simd_normalize(simd_mul(flight.orientation, lookQuat))

        case .chase:
            let slerpFactor = min(1.0, dt * 8.5)
            chaseOrientation = simd_slerp(chaseOrientation, flight.orientation, slerpFactor)
            let camOrient = simd_normalize(simd_mul(chaseOrientation, lookQuat))
            let chaseOffset = SIMD3<Float>(0.0, 2.8, 12.5)
            cameraEntity.position = playerLocal + camOrient.act(chaseOffset)
            cameraEntity.orientation = camOrient
        }
    }

    private static func wrapCoord(_ value: Float, halfSpan: Float) -> Float {
        let span = halfSpan * 2.0
        var v = (value + halfSpan).truncatingRemainder(dividingBy: span)
        if v < 0 { v += span }
        return v - halfSpan
    }

    private func projectDirectionToScreen(worldDeltaFromPlayer: SIMD3<Double>) -> (x: CGFloat, y: CGFloat, isOnScreen: Bool, bearingAngle: Double) {
        let playerLocal = originFrame.localPosition(for: playerWorldPos.position)
        let camOffsetFromPlayer = cameraEntity.position - playerLocal
        let dist = simd_length(worldDeltaFromPlayer)

        let camSpaceVec: SIMD3<Float>
        if dist > 5_000.0 {
            let unitD = worldDeltaFromPlayer / max(1.0, dist)
            let unitF = SIMD3<Float>(Float(unitD.x), Float(unitD.y), Float(unitD.z))
            camSpaceVec = cameraEntity.orientation.inverse.act(unitF)
        } else {
            let relFloat = SIMD3<Float>(Float(worldDeltaFromPlayer.x), Float(worldDeltaFromPlayer.y), Float(worldDeltaFromPlayer.z)) - camOffsetFromPlayer
            camSpaceVec = cameraEntity.orientation.inverse.act(relFloat)
        }

        let halfW = Float(max(400.0, viewportSize.width)) * 0.5
        let halfH = Float(max(300.0, viewportSize.height)) * 0.5
        let tanHalfFOV = tan((currentFOV * 0.5) * .pi / 180.0)
        let focalLengthPts = halfH / max(0.01, tanHalfFOV)

        let bearing = Double(atan2(-camSpaceVec.y, camSpaceVec.x))

        guard camSpaceVec.z < -0.1 else {
            return (0, 0, false, bearing)
        }

        let screenX = (camSpaceVec.x / -camSpaceVec.z) * focalLengthPts
        let screenY = (-camSpaceVec.y / -camSpaceVec.z) * focalLengthPts
        let marginX = halfW - 55.0
        let marginY = halfH - 55.0
        let onScreen = abs(screenX) <= marginX && abs(screenY) <= marginY

        return (CGFloat(screenX), CGFloat(screenY), onScreen, bearing)
    }

    private func buildHUDTelemetry(
        input: InputStateComponent,
        navManager: NavigationWaypointManager,
        commander: CommanderProfile
    ) -> FlightHUDTelemetry {
        let invShipRot = flight.orientation.inverse
        let spd = flight.speed

        var progradeX: CGFloat = 0.0
        var progradeY: CGFloat = 0.0
        var hasPrograde = false
        if spd > 2.0 {
            let vDir = flight.velocity / spd
            let proj = projectDirectionToScreen(worldDeltaFromPlayer: SIMD3<Double>(Double(vDir.x) * 10_000.0, Double(vDir.y) * 10_000.0, Double(vDir.z) * 10_000.0))
            if proj.isOnScreen {
                hasPrograde = true
                progradeX = proj.x
                progradeY = proj.y
            }
        }

        let stationDist: Double
        let earthAltKm: Double
        let moonDistKm: Double
        if let env = solEnv {
            stationDist = simd_length(env.stationWorldPosition - playerWorldPos.position)
            let earthCentreDist = simd_length(env.earthWorldPosition - playerWorldPos.position)
            earthAltKm = max(0.0, (earthCentreDist - env.earthRadiusMetres) / 1_000.0)
            moonDistKm = simd_length(env.moonWorldPosition - playerWorldPos.position) / 1_000.0
        } else {
            stationDist = 900.0
            earthAltKm = 9_100.0
            moonDistKm = 384_400.0
        }
        let isMassLocked = stationDist < 350.0
        let canDock = stationDist < 1_500.0

        let wp = navManager.activeWaypoint
        let wpDelta = wp.worldPosition - playerWorldPos.position
        let wpDist = max(1.0, simd_length(wpDelta))
        let wpDirDouble = wpDelta / wpDist
        let wpDirWorld = SIMD3<Float>(Float(wpDirDouble.x), Float(wpDirDouble.y), Float(wpDirDouble.z))
        let wpLocalDir = invShipRot.act(wpDirWorld)

        let wpInFront = wpLocalDir.z < -0.05
        let compassX = CGFloat(min(max(wpLocalDir.x, -1.0), 1.0))
        let compassY = CGFloat(min(max(-wpLocalDir.y, -1.0), 1.0))

        let wpProj = projectDirectionToScreen(worldDeltaFromPlayer: wpDelta)

        let effectiveClosingSpeed = max(25.0, Double(spd))
        let etaSec = min(3599.0, wpDist / effectiveClosingSpeed)
        let etaMin = Int(etaSec) / 60
        let etaRemSec = Int(etaSec) % 60
        let etaString = wpDist > 1.0e9 ? "HYPERSPACE" : String(format: "%d:%02d", etaMin, etaRemSec)

        var contacts: [SensorDiscContact] = []
        let radarRange: Float = 1_200.0

        for localWP in navManager.localWaypoints {
            let d = localWP.worldPosition - playerWorldPos.position
            let localVec = invShipRot.act(SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
            let normVec = localVec / radarRange
            let clampedXZ = Self.clampToUnitCircle(x: normVec.x, z: normVec.z)
            contacts.append(
                SensorDiscContact(
                    id: localWP.id,
                    label: localWP.name,
                    discX: clampedXZ.x,
                    discZ: clampedXZ.z,
                    elevationY: min(max(normVec.y, -1.0), 1.0),
                    isHostile: false,
                    isLockedTarget: false,
                    isStation: localWP.kind == .station,
                    isWaypoint: localWP.id == wp.id
                )
            )
        }

        for (idx, drone) in combat.drones.enumerated() where drone.isAlive {
            let d = drone.worldPosition - playerWorldPos.position
            let localVec = invShipRot.act(SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
            let normVec = localVec / radarRange
            let clampedXZ = Self.clampToUnitCircle(x: normVec.x, z: normVec.z)
            contacts.append(
                SensorDiscContact(
                    id: drone.id,
                    label: drone.callsign,
                    discX: clampedXZ.x,
                    discZ: clampedXZ.z,
                    elevationY: min(max(normVec.y, -1.0), 1.0),
                    isHostile: true,
                    isLockedTarget: combat.lockedDroneIndex == idx,
                    isStation: false,
                    isWaypoint: false
                )
            )
        }

        let overviewContacts = combat.buildOverviewContacts(
            playerWorldPos: playerWorldPos.position,
            localWaypoints: navManager.localWaypoints
        )

        var hasTarget = false
        var tName = "NO TARGET"
        var tState = ""
        var tDistText = "--"
        var tShields: Float = 0.0
        var tHull: Float = 0.0
        var tScreenX: CGFloat = 0.0
        var tScreenY: CGFloat = 0.0
        var tOnScreen = false
        var tBearing: Double = 0.0
        var leadX: CGFloat = 0.0
        var leadY: CGFloat = 0.0

        if let lockedIdx = combat.lockedDroneIndex, lockedIdx < combat.drones.count {
            let drone = combat.drones[lockedIdx]
            if drone.isAlive {
                hasTarget = true
                tName = drone.callsign
                tState = drone.state.rawValue
                tShields = drone.shields
                tHull = drone.hull

                let deltaD = drone.worldPosition - playerWorldPos.position
                let dist = max(1.0, simd_length(deltaD))
                tDistText = NavigationWaypointManager.formatDistance(dist)

                let targetProj = projectDirectionToScreen(worldDeltaFromPlayer: deltaD)
                tScreenX = targetProj.x
                tScreenY = targetProj.y
                tOnScreen = targetProj.isOnScreen
                tBearing = targetProj.bearingAngle

                if tOnScreen {
                    let interceptTime = Double(dist / 680.0)
                    let relVel = drone.velocity - flight.velocity
                    let leadDelta = deltaD + SIMD3<Double>(Double(relVel.x) * interceptTime, Double(relVel.y) * interceptTime, Double(relVel.z) * interceptTime)
                    let leadProj = projectDirectionToScreen(worldDeltaFromPlayer: leadDelta)
                    leadX = leadProj.isOnScreen ? leadProj.x : tScreenX
                    leadY = leadProj.isOnScreen ? leadProj.y : tScreenY
                }
            }
        }

        let subsystemName = CombatDroneInstance.subsystems[combat.selectedSubsystemIndex % CombatDroneInstance.subsystems.count]
        let inBlueZone = input.throttle >= 0.38 && input.throttle <= 0.66
        let fsdCountStr = fsdCountdown > 0.0 ? String(format: "FSD CHARGING... %.1f s", fsdCountdown) : ""

        return FlightHUDTelemetry(
            shipName: flight.spec.name,
            currentSystemName: navManager.currentSystem.name,
            currentSystemSecurity: navManager.primarySecurityText,
            credits: commander.data.credits,
            unclaimedBountiesCR: commander.data.unclaimedBountiesCR,
            cargoSummaryText: "\(commander.cargoUsedTons)/\(commander.data.cargoCapacity) T",
            statusBannerText: commander.statusBannerMessage,
            radioSender: commander.radioSender,
            radioMessage: commander.radioMessage,
            autopilotStatusText: autopilotMode.statusText,
            isAudioMuted: CockpitAudioManager.shared.isMuted,
            speedMetresPerSec: spd,
            maxSpeed: flight.spec.maxSpeed * combat.distributor.engineSpeedMultiplier * commander.thrusterBonusMultiplier,
            boostSpeed: flight.spec.boostSpeed * commander.thrusterBonusMultiplier,
            throttle: input.throttle,
            isInBlueZone: inBlueZone,
            isBoosting: flight.isBoosting,
            boostChargeFraction: flight.boostChargeFraction,
            flightAssistEnabled: input.flightAssistEnabled,
            autoTrackEnabled: input.autoTrackEnabled,
            hardpointsDeployed: input.hardpointsDeployed,
            landingGearDeployed: input.landingGearDeployed,
            cameraMode: cameraMode,
            isFSDCharging: fsdCountdown > 0.0,
            fsdCountdownText: fsdCountStr,
            isHyperspaceJumping: hyperspaceTimer > 0.0,
            hyperspaceDestinationName: pendingHyperspaceSystem?.name ?? wp.name,
            canDockAtStation: canDock,
            progradeOffsetX: progradeX,
            progradeOffsetY: progradeY,
            hasValidPrograde: hasPrograde,
            waypointName: wp.name,
            waypointKind: wp.kind,
            waypointDistanceText: NavigationWaypointManager.formatDistance(wpDist),
            waypointETAText: etaString,
            waypointSupportsLocalJump: wp.supportsLocalJump,
            waypointIsInterstellar: wp.targetSystem != nil,
            waypointScreenX: wpProj.x,
            waypointScreenY: wpProj.y,
            waypointIsOnScreen: wpProj.isOnScreen,
            waypointBearingAngle: wpProj.bearingAngle,
            waypointIsInFront: wpInFront,
            compassDotX: compassX,
            compassDotY: compassY,
            isMassLocked: isMassLocked,
            sensorContacts: contacts,
            overviewContacts: overviewContacts,
            hasLockedTarget: hasTarget,
            targetName: tName,
            targetStateText: tState,
            targetSubsystem: subsystemName,
            targetDistanceText: tDistText,
            targetShields: tShields,
            targetHull: tHull,
            targetScreenX: tScreenX,
            targetScreenY: tScreenY,
            targetIsOnScreen: tOnScreen,
            targetBearingAngle: tBearing,
            leadScreenX: leadX,
            leadScreenY: leadY,
            showHitMarker: combat.hitMarkerTimer > 0.0,
            showShieldHitFlash: combat.playerShieldHitTimer > 0.0,
            totalKills: commander.data.totalKills,
            playerShields: combat.playerShields,
            playerHull: combat.playerHull,
            weaponCapacitor: combat.weaponCapacitor,
            sysPips: combat.distributor.sysPips,
            engPips: combat.distributor.engPips,
            wepPips: combat.distributor.wepPips,
            stationDistanceMetres: stationDist,
            earthAltitudeKm: earthAltKm,
            moonDistanceKm: moonDistKm,
            originRecenterCount: originFrame.recenterCount
        )
    }

    private static func clampToUnitCircle(x: Float, z: Float) -> (x: Float, z: Float) {
        let len = sqrt(x * x + z * z)
        if len > 1.0 {
            return (x / len, z / len)
        }
        return (x, z)
    }
}

struct SpaceSceneView: View {
    @StateObject private var metrics = DebugMetrics()
    @StateObject private var inputManager = ControllerInputManager()
    @StateObject private var sceneController = SceneController()
    @StateObject private var navManager = NavigationWaypointManager()
    @StateObject private var commander = CommanderProfile()

    @State private var showHoloNavMap = false
    @State private var showTuningDrawer = false
    @State private var minimalHUDMode = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RealityView { content in
                    content.camera = .virtual
                    sceneController.setupSceneIfNeeded(commander: commander, navManager: navManager)
                    content.add(sceneController.rootEntity)

                    let metricsRef = metrics
                    let inputRef = inputManager
                    let controllerRef = sceneController
                    let navRef = navManager
                    let cmdrRef = commander

                    controllerRef.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                        MainActor.assumeIsolated {
                            let currentInput = inputRef.pollTick(deltaTime: event.deltaTime)
                            var toggledMap = false
                            let latestHUD = controllerRef.stepFrame(
                                deltaTime: event.deltaTime,
                                input: currentInput,
                                navManager: navRef,
                                commander: cmdrRef,
                                onToggleNavMap: { toggledMap = true }
                            )
                            if toggledMap {
                                showHoloNavMap.toggle()
                            }
                            metricsRef.recordFrame(
                                deltaTime: event.deltaTime,
                                rootEntity: controllerRef.rootEntity,
                                latestHUD: latestHUD
                            )
                        }
                    }
                }
                .ignoresSafeArea()
                .gesture(freeLookDragGesture)

                FlightHUDView(
                    hud: metrics.hud,
                    minimalHUDMode: minimalHUDMode,
                    onToggleCamera: { sceneController.toggleCameraMode() },
                    onToggleFlightAssist: { inputManager.toggleFlightAssist() },
                    onToggleAutoTrack: { inputManager.toggleAutoTrack() },
                    onToggleAudioMute: { CockpitAudioManager.shared.toggleMute() },
                    onTriggerBoost: { inputManager.requestBoost() },
                    onSetThrottle: { inputManager.setThrottle($0) },
                    onOpenNavMap: { showHoloNavMap = true },
                    onCycleWaypoint: { navManager.cycleNextLocalWaypoint() },
                    onEngageFSD: { sceneController.initiateFSDJump(to: navManager.activeWaypoint, commander: commander) },
                    onDockAtStation: { sceneController.dockAtPrimaryStation(commander: commander, navManager: navManager) },
                    onCycleTarget: { sceneController.combat.cycleNextTarget() },
                    onCycleSubsystem: {
                        sceneController.combat.selectedSubsystemIndex =
                            (sceneController.combat.selectedSubsystemIndex + 1) % CombatDroneInstance.subsystems.count
                    },
                    onPipSYS: { sceneController.combat.distributor.allocateSYS() },
                    onPipENG: { sceneController.combat.distributor.allocateENG() },
                    onPipWEP: { sceneController.combat.distributor.allocateWEP() },
                    onPipReset: { sceneController.combat.distributor.reset() },
                    onOpenTuningDrawer: { showTuningDrawer.toggle() },
                    onSelectOverviewItem: { item in
                        sceneController.selectOverviewContact(item, navManager: navManager, commander: commander)
                    },
                    onOverviewApproach: { item in
                        sceneController.engageOverviewApproach(item, inputManager: inputManager, commander: commander)
                    },
                    onOverviewOrbit: { item in
                        sceneController.engageOverviewOrbit(item, inputManager: inputManager, commander: commander)
                    },
                    onOverviewTractor: {
                        let scooped = sceneController.combat.tractorNearestCanister(
                            playerWorldPos: sceneController.playerWorldPos.position,
                            maxRange: commander.tractorRangeMetres + 180.0
                        )
                        if !scooped {
                            commander.postBanner("NO CANISTER WITHIN TRACTOR RANGE (\(Int(commander.tractorRangeMetres + 180.0)) M)")
                        }
                    },
                    onOverviewWarpOrDock: { item in
                        if item.isStation && metrics.hud.canDockAtStation {
                            sceneController.dockAtPrimaryStation(commander: commander, navManager: navManager)
                        } else if let wpID = item.waypointID, let wp = navManager.localWaypoints.first(where: { $0.id == wpID }) {
                            navManager.selectWaypoint(wp)
                            sceneController.initiateFSDJump(to: wp, commander: commander)
                        } else {
                            sceneController.engageOverviewApproach(item, inputManager: inputManager, commander: commander)
                        }
                    },
                    onSetTouchPrimaryFire: { firing in
                        inputManager.touchPrimaryFireHeld = firing
                    },
                    onSetTouchSecondaryFire: { firing in
                        inputManager.touchSecondaryFireHeld = firing
                    }
                )

                DebugOverlayView(
                    metrics: metrics,
                    inputManager: inputManager,
                    showSolSheet: $showHoloNavMap
                )
                .padding(.top, 12)
                .padding(.leading, 16)

                if showTuningDrawer {
                    HStack {
                        Spacer()
                        FlightTuningDrawerView(
                            spec: $sceneController.flight.spec,
                            deadZone: $inputManager.deadZone,
                            responseExponent: $inputManager.responseExponent,
                            modernSteerMode: $inputManager.modernSteerMode,
                            minimalHUDMode: $minimalHUDMode,
                            onResetDefaults: {
                                sceneController.flight.spec = commander.activeHull.flightSpec
                                inputManager.deadZone = 0.12
                                inputManager.responseExponent = 2.10
                                inputManager.modernSteerMode = true
                                minimalHUDMode = false
                            },
                            onClose: { showTuningDrawer = false }
                        )
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }
                }

                if showHoloNavMap {
                    HoloNavigationMapView(
                        navManager: navManager,
                        playerWorldPosition: sceneController.playerWorldPos.position,
                        isMassLocked: metrics.hud.isMassLocked,
                        onEngageLocalJump: { wp in
                            sceneController.initiateFSDJump(to: wp, commander: commander)
                        },
                        onClose: { showHoloNavMap = false }
                    )
                    .transition(.opacity)
                }

                if commander.isDocked {
                    StarportServicesView(
                        commander: commander,
                        navManager: navManager,
                        onShipChanged: { newHull in
                            sceneController.rebuildPlayerShip(hull: newHull)
                        },
                        onRepairAndRefuel: {
                            sceneController.combat.playerShields = 100.0
                            sceneController.combat.playerHull = 100.0
                            commander.data.fuelTons = commander.data.maxFuelTons
                            CockpitAudioManager.shared.playTractorScoop()
                            commander.postBanner("HULL REPAIRED & FUEL TANKS TOPPED UP (100%)")
                        },
                        onLaunchShip: {
                            sceneController.launchFromStation(commander: commander)
                        }
                    )
                    .transition(.opacity)
                }
            }
            .onAppear {
                sceneController.viewportSize = geo.size
            }
            .onChange(of: geo.size) { _, newSize in
                sceneController.viewportSize = newSize
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
    }

    private var freeLookDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !sceneController.isDragging {
                    sceneController.isDragging = true
                    sceneController.dragStartYaw = sceneController.freeLookYaw
                    sceneController.dragStartPitch = sceneController.freeLookPitch
                }
                let sensitivity: Float = 0.004
                sceneController.freeLookYaw = min(max(sceneController.dragStartYaw - Float(value.translation.width) * sensitivity, -1.4), 1.4)
                sceneController.freeLookPitch = min(max(sceneController.dragStartPitch - Float(value.translation.height) * sensitivity, -1.0), 1.0)
            }
            .onEnded { _ in
                sceneController.isDragging = false
            }
    }
}
