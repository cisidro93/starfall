import SwiftUI
import RealityKit
import simd
import StarfallGalaxy

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

    // Camera state
    var cameraMode: ShipCameraMode = .cockpit
    var chaseOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var currentFOV: Float = 60.0
    var freeLookYaw: Float = 0.0
    var freeLookPitch: Float = 0.0
    var dragStartYaw: Float = 0.0
    var dragStartPitch: Float = 0.0
    var isDragging: Bool = false

    func setupSceneIfNeeded() {
        guard rootEntity.children.isEmpty else { return }
        WorldPositionComponent.registerComponent()
        PlanetaryBodyComponent.registerComponent()
        FlightComponent.registerComponent()
        InputStateComponent.registerComponent()

        rootEntity.name = "StarfallSpaceRoot"

        // 1. Starfield skybox (follows camera translation, never rotates with ship)
        let skybox = StarfieldGenerator.makeSkyboxEntity()
        rootEntity.addChild(skybox)
        skyboxEntity = skybox

        // 2. Sol system environment (Sun, Earth, Moon, Gagarin Gateway, buoys, space dust)
        let env = SolSceneBuilder.buildSolEnvironment(into: rootEntity)
        solEnv = env

        // 3. Combat drones, Forsaken Relay Hulk, Nav Beacon & weapon tracer beams
        combat.setupCombatEntities(into: rootEntity)

        // 4. Player starfighter (SF-1V Kestrel)
        let ship = ShipEntityBuilder.makeKestrelShip()
        rootEntity.addChild(ship.root)
        builtShip = ship

        // 5. Virtual perspective camera
        cameraEntity.name = "MainVirtualCamera"
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = 60.0
        cameraEntity.components.set(camera)
        rootEntity.addChild(cameraEntity)

        applyCameraModeVisibility()
        syncSceneTransforms(dt: 1.0 / 60.0)
    }

    func toggleCameraMode() {
        cameraMode = (cameraMode == .cockpit) ? .chase : .cockpit
        freeLookYaw = 0.0
        freeLookPitch = 0.0
        applyCameraModeVisibility()
    }

    func engageLocalMicroJump(to waypoint: NavigationWaypoint) {
        guard waypoint.supportsLocalJump else { return }
        // Place player 280 m back from the destination along their approach vector
        let offset = SIMD3<Double>(0.0, 25.0, 280.0)
        playerWorldPos.position = waypoint.worldPosition + offset
        flight.velocity = flight.forwardVector * 120.0
        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)
        syncSceneTransforms(dt: 1.0 / 60.0)
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
        onToggleNavMap: () -> Void
    ) -> FlightHUDTelemetry {
        let clampedDT = min(max(deltaTime, 0.001), 0.1)
        let fdt = Float(clampedDT)

        if input.cameraToggleTriggered {
            toggleCameraMode()
        }
        if input.galaxyMapTriggered {
            onToggleNavMap()
        }

        // Free-look via Hold LB + Right Stick (or return smoothly to center when released)
        if input.isModifierHeld {
            freeLookYaw = min(max(freeLookYaw - input.lookYaw * fdt * 1.8, -1.2), 1.2)
            freeLookPitch = min(max(freeLookPitch + input.lookPitch * fdt * 1.5, -0.9), 0.9)
        } else if !isDragging {
            freeLookYaw *= max(0.0, 1.0 - fdt * 6.0)
            freeLookPitch *= max(0.0, 1.0 - fdt * 6.0)
        }

        // Fixed 60 Hz simulation loop (scaled by Step 8 ENG distributor pips)
        let engSpeedMult = combat.distributor.engineSpeedMultiplier
        let boostChargeMult = combat.distributor.boostRechargeMultiplier

        fixedAccumulator += clampedDT
        var tickInput = input
        var steps = 0
        while fixedAccumulator >= FlightPhysics.fixedTimeStep && steps < 6 {
            FlightPhysics.stepFixedTick(
                flight: &flight,
                input: tickInput,
                worldPosition: &playerWorldPos,
                dt: Float(FlightPhysics.fixedTimeStep),
                engineSpeedMultiplier: engSpeedMult,
                boostRechargeMultiplier: boostChargeMult
            )
            tickInput.boostTriggered = false
            fixedAccumulator -= FlightPhysics.fixedTimeStep
            steps += 1
        }

        // Floating origin recentring check (every time player exceeds 2,000 m from local origin)
        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)

        // Step combat drones, weapons & power distributor pips
        combat.stepCombat(
            dt: fdt,
            input: input,
            playerWorldPos: playerWorldPos.position,
            playerVelocity: flight.velocity,
            playerOrientation: flight.orientation,
            originFrame: originFrame
        )

        // Rotate Gagarin Gateway habitat wheel
        stationRotationAngle += fdt * 0.16
        if stationRotationAngle > .pi * 2.0 {
            stationRotationAngle -= .pi * 2.0
        }
        solEnv?.rotatingWheelEntity.orientation = simd_quatf(angle: stationRotationAngle, axis: SIMD3<Float>(0, 0, 1))

        // Update all camera-relative & local-origin entity transforms
        syncSceneTransforms(dt: fdt)

        return buildHUDTelemetry(input: input, navManager: navManager)
    }

    private func syncSceneTransforms(dt: Float) {
        let playerLocal = originFrame.localPosition(for: playerWorldPos.position)

        // 1. Keep skybox centered on player
        skyboxEntity?.position = playerLocal

        // 2. Update player ship transform & engine plume scale
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

        // 3. Update local world-positioned objects (station, buoys, hulk, beacon, drones)
        for child in rootEntity.children where child !== builtShip?.root {
            if let wp = child.components[WorldPositionComponent.self] {
                child.position = originFrame.localPosition(for: wp.position)
            }
        }

        // 4. Update planetary body proxies (Sun, Earth, Moon) at true angular scale & direction
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

            // 5. Wrap space-dust motes in a 140m cube around the player for speed perception
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

        // 6. Update virtual camera position, rotation & dynamic FOV
        let targetFOV: Float = flight.isBoosting ? 70.0 : 60.0
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

    private func buildHUDTelemetry(
        input: InputStateComponent,
        navManager: NavigationWaypointManager
    ) -> FlightHUDTelemetry {
        let invShipRot = flight.orientation.inverse
        let spd = flight.speed

        // 1. Prograde velocity vector projection
        var progradeX: CGFloat = 0.0
        var progradeY: CGFloat = 0.0
        var hasPrograde = false
        if spd > 2.0 {
            let localVel = invShipRot.act(flight.velocity / spd)
            if localVel.z < -0.05 {
                hasPrograde = true
                let scalePts: Float = 110.0
                progradeX = CGFloat(min(max((localVel.x / -localVel.z) * scalePts, -140.0), 140.0))
                progradeY = CGFloat(min(max((-localVel.y / -localVel.z) * scalePts, -140.0), 140.0))
            }
        }

        // 2. Orbital distances & Mass-Lock status
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
        let isMassLocked = stationDist < 450.0

        // 3. Active Waypoint Projection & 3D Compass Nav-Ball
        let wp = navManager.activeWaypoint
        let wpDelta = wp.worldPosition - playerWorldPos.position
        let wpDist = max(1.0, simd_length(wpDelta))
        let wpDirDouble = wpDelta / wpDist
        let wpDirWorld = SIMD3<Float>(Float(wpDirDouble.x), Float(wpDirDouble.y), Float(wpDirDouble.z))
        let wpLocalDir = invShipRot.act(wpDirWorld)

        let wpInFront = wpLocalDir.z < -0.08
        let compassX = CGFloat(min(max(wpLocalDir.x, -1.0), 1.0))
        let compassY = CGFloat(min(max(-wpLocalDir.y, -1.0), 1.0))

        var wpScreenX: CGFloat = 0.0
        var wpScreenY: CGFloat = 0.0
        if wpInFront {
            let projScale: Float = 240.0
            wpScreenX = CGFloat(min(max((wpLocalDir.x / -wpLocalDir.z) * projScale, -260.0), 260.0))
            wpScreenY = CGFloat(min(max((-wpLocalDir.y / -wpLocalDir.z) * projScale, -155.0), 155.0))
        }

        let effectiveClosingSpeed = max(25.0, Double(spd))
        let etaSec = min(3599.0, wpDist / effectiveClosingSpeed)
        let etaMin = Int(etaSec) / 60
        let etaRemSec = Int(etaSec) % 60
        let etaString = wpDist > 1.0e9 ? "JUMP" : String(format: "%d:%02d", etaMin, etaRemSec)

        // 4. Build 3D Holographic Sensor Disc Contacts
        var contacts: [SensorDiscContact] = []
        let radarRange: Float = 1_400.0

        // Add local waypoints (Station, Hulk, Beacon)
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

        // Add alive combat drones to 3D sensor disc
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

        // 5. Locked Combat Target & Vendetta Predictive Lead Reticle Projection
        var hasTarget = false
        var tName = "NO TARGET"
        var tState = ""
        var tDistText = "--"
        var tShields: Float = 0.0
        var tHull: Float = 0.0
        var tScreenX: CGFloat = 0.0
        var tScreenY: CGFloat = 0.0
        var tInFront = false
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

                let relFloat = SIMD3<Float>(Float(deltaD.x), Float(deltaD.y), Float(deltaD.z))
                let localTarget = invShipRot.act(relFloat)
                if localTarget.z < -1.0 {
                    tInFront = true
                    let projScale: Float = 240.0
                    tScreenX = CGFloat(min(max((localTarget.x / -localTarget.z) * projScale, -260.0), 260.0))
                    tScreenY = CGFloat(min(max((-localTarget.y / -localTarget.z) * projScale, -155.0), 155.0))

                    // Predictive lead point for 680 m/s cannon projectiles
                    let interceptTime = Float(dist) / 680.0
                    let leadWorldRel = relFloat + (drone.velocity - flight.velocity) * interceptTime
                    let localLead = invShipRot.act(leadWorldRel)
                    if localLead.z < -1.0 {
                        leadX = CGFloat(min(max((localLead.x / -localLead.z) * projScale, -270.0), 270.0))
                        leadY = CGFloat(min(max((-localLead.y / -localLead.z) * projScale, -165.0), 165.0))
                    } else {
                        leadX = tScreenX
                        leadY = tScreenY
                    }
                }
            }
        }

        let subsystemName = CombatDroneInstance.subsystems[combat.selectedSubsystemIndex % CombatDroneInstance.subsystems.count]

        return FlightHUDTelemetry(
            shipName: flight.spec.name,
            speedMetresPerSec: spd,
            maxSpeed: flight.spec.maxSpeed * combat.distributor.engineSpeedMultiplier,
            boostSpeed: flight.spec.boostSpeed,
            throttle: input.throttle,
            isBoosting: flight.isBoosting,
            boostChargeFraction: flight.boostChargeFraction,
            flightAssistEnabled: input.flightAssistEnabled,
            hardpointsDeployed: input.hardpointsDeployed,
            landingGearDeployed: input.landingGearDeployed,
            cameraMode: cameraMode,
            progradeOffsetX: progradeX,
            progradeOffsetY: progradeY,
            hasValidPrograde: hasPrograde,
            waypointName: wp.name,
            waypointKind: wp.kind,
            waypointDistanceText: NavigationWaypointManager.formatDistance(wpDist),
            waypointETAText: etaString,
            waypointSupportsLocalJump: wp.supportsLocalJump,
            waypointScreenX: wpScreenX,
            waypointScreenY: wpScreenY,
            waypointIsInFront: wpInFront,
            compassDotX: compassX,
            compassDotY: compassY,
            isMassLocked: isMassLocked,
            sensorContacts: contacts,
            hasLockedTarget: hasTarget,
            targetName: tName,
            targetStateText: tState,
            targetSubsystem: subsystemName,
            targetDistanceText: tDistText,
            targetShields: tShields,
            targetHull: tHull,
            targetScreenX: tScreenX,
            targetScreenY: tScreenY,
            targetIsInFront: tInFront,
            leadScreenX: leadX,
            leadScreenY: leadY,
            showHitMarker: combat.hitMarkerTimer > 0.0,
            totalKills: combat.totalKills,
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

    @State private var showHoloNavMap = false
    @State private var showTuningDrawer = false
    @State private var minimalHUDMode = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.camera = .virtual
                sceneController.setupSceneIfNeeded()
                content.add(sceneController.rootEntity)

                let metricsRef = metrics
                let inputRef = inputManager
                let controllerRef = sceneController
                let navRef = navManager

                controllerRef.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        let currentInput = inputRef.pollTick(deltaTime: event.deltaTime)
                        var toggledMap = false
                        let latestHUD = controllerRef.stepFrame(
                            deltaTime: event.deltaTime,
                            input: currentInput,
                            navManager: navRef,
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
                onTriggerBoost: { inputManager.requestBoost() },
                onSetThrottle: { inputManager.setThrottle($0) },
                onOpenNavMap: { showHoloNavMap = true },
                onCycleWaypoint: { navManager.cycleNextLocalWaypoint() },
                onMicroJump: { sceneController.engageLocalMicroJump(to: navManager.activeWaypoint) },
                onCycleTarget: { sceneController.combat.cycleNextTarget() },
                onCycleSubsystem: {
                    sceneController.combat.selectedSubsystemIndex =
                        (sceneController.combat.selectedSubsystemIndex + 1) % CombatDroneInstance.subsystems.count
                },
                onPipSYS: { sceneController.combat.distributor.allocateSYS() },
                onPipENG: { sceneController.combat.distributor.allocateENG() },
                onPipWEP: { sceneController.combat.distributor.allocateWEP() },
                onPipReset: { sceneController.combat.distributor.reset() },
                onOpenTuningDrawer: { showTuningDrawer.toggle() }
            )

            DebugOverlayView(
                metrics: metrics,
                inputManager: inputManager,
                showSolSheet: $showHoloNavMap
            )
            .padding(.top, 16)
            .padding(.leading, 18)

            if showTuningDrawer {
                HStack {
                    Spacer()
                    FlightTuningDrawerView(
                        spec: $sceneController.flight.spec,
                        deadZone: $inputManager.deadZone,
                        responseExponent: $inputManager.responseExponent,
                        minimalHUDMode: $minimalHUDMode,
                        onResetDefaults: {
                            sceneController.flight.spec = ShipSpec.loadStarterSpec()
                            inputManager.deadZone = 0.10
                            inputManager.responseExponent = 1.80
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
                        sceneController.engageLocalMicroJump(to: wp)
                    },
                    onClose: { showHoloNavMap = false }
                )
                .transition(.opacity)
            }
        }
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
