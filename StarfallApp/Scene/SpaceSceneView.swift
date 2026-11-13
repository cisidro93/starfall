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

    // Fixed 60 Hz simulation state
    var flight = FlightComponent()
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

        // 3. Player starfighter (SF-1V Kestrel)
        let ship = ShipEntityBuilder.makeKestrelShip()
        rootEntity.addChild(ship.root)
        builtShip = ship

        // 4. Virtual perspective camera
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
        onToggleSolSheet: () -> Void
    ) -> FlightHUDTelemetry {
        let clampedDT = min(max(deltaTime, 0.001), 0.1)
        let fdt = Float(clampedDT)

        if input.cameraToggleTriggered {
            toggleCameraMode()
        }
        if input.galaxyMapTriggered {
            onToggleSolSheet()
        }

        // Free-look via Hold LB + Right Stick (or return smoothly to center when released)
        if input.isModifierHeld {
            freeLookYaw = min(max(freeLookYaw - input.lookYaw * fdt * 1.8, -1.2), 1.2)
            freeLookPitch = min(max(freeLookPitch + input.lookPitch * fdt * 1.5, -0.9), 0.9)
        } else if !isDragging {
            freeLookYaw *= max(0.0, 1.0 - fdt * 6.0)
            freeLookPitch *= max(0.0, 1.0 - fdt * 6.0)
        }

        // Fixed 60 Hz simulation loop
        fixedAccumulator += clampedDT
        var tickInput = input
        var steps = 0
        while fixedAccumulator >= FlightPhysics.fixedTimeStep && steps < 6 {
            FlightPhysics.stepFixedTick(
                flight: &flight,
                input: tickInput,
                worldPosition: &playerWorldPos,
                dt: Float(FlightPhysics.fixedTimeStep)
            )
            // Consume single-tick triggers after the first fixed step
            tickInput.boostTriggered = false
            fixedAccumulator -= FlightPhysics.fixedTimeStep
            steps += 1
        }

        // Floating origin recentring check (every time player exceeds 2,000 m from local origin)
        originFrame.updateIfNeeded(playerWorldPosition: playerWorldPos.position)

        // Rotate Gagarin Gateway habitat wheel
        stationRotationAngle += fdt * 0.16
        if stationRotationAngle > .pi * 2.0 {
            stationRotationAngle -= .pi * 2.0
        }
        solEnv?.rotatingWheelEntity.orientation = simd_quatf(angle: stationRotationAngle, axis: SIMD3<Float>(0, 0, 1))

        // Update all camera-relative & local-origin entity transforms
        syncSceneTransforms(dt: fdt)

        return buildHUDTelemetry(input: input)
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

        // 3. Update local world-positioned objects (station & approach buoys)
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
            // Subtle pilot head G-force offset inside cockpit
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

    private func buildHUDTelemetry(input: InputStateComponent) -> FlightHUDTelemetry {
        var progradeX: CGFloat = 0.0
        var progradeY: CGFloat = 0.0
        var hasPrograde = false

        let spd = flight.speed
        if spd > 2.0 {
            let localVel = flight.orientation.inverse.act(flight.velocity / spd)
            if localVel.z < -0.05 {
                hasPrograde = true
                let scalePts: Float = 110.0
                progradeX = CGFloat(min(max((localVel.x / -localVel.z) * scalePts, -130.0), 130.0))
                progradeY = CGFloat(min(max((-localVel.y / -localVel.z) * scalePts, -130.0), 130.0))
            }
        }

        let stationDist: Double
        let earthAltKm: Double
        let moonDistKm: Double
        let stationName: String

        if let env = solEnv {
            stationName = env.stationName
            stationDist = simd_length(env.stationWorldPosition - playerWorldPos.position)
            let earthCentreDist = simd_length(env.earthWorldPosition - playerWorldPos.position)
            earthAltKm = max(0.0, (earthCentreDist - env.earthRadiusMetres) / 1_000.0)
            moonDistKm = simd_length(env.moonWorldPosition - playerWorldPos.position) / 1_000.0
        } else {
            stationName = "Gagarin Gateway"
            stationDist = 900.0
            earthAltKm = 9_100.0
            moonDistKm = 384_400.0
        }

        return FlightHUDTelemetry(
            shipName: flight.spec.name,
            speedMetresPerSec: spd,
            maxSpeed: flight.spec.maxSpeed,
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
            stationName: stationName,
            stationDistanceMetres: stationDist,
            earthAltitudeKm: earthAltKm,
            moonDistanceKm: moonDistKm,
            originRecenterCount: originFrame.recenterCount
        )
    }
}

struct SpaceSceneView: View {
    @StateObject private var metrics = DebugMetrics()
    @StateObject private var inputManager = ControllerInputManager()
    @StateObject private var sceneController = SceneController()
    @State private var showSolSheet = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.camera = .virtual
                sceneController.setupSceneIfNeeded()
                content.add(sceneController.rootEntity)

                let metricsRef = metrics
                let inputRef = inputManager
                let controllerRef = sceneController

                controllerRef.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        let currentInput = inputRef.pollTick(deltaTime: event.deltaTime)
                        var toggledMap = false
                        let latestHUD = controllerRef.stepFrame(
                            deltaTime: event.deltaTime,
                            input: currentInput,
                            onToggleSolSheet: { toggledMap = true }
                        )
                        if toggledMap {
                            showSolSheet.toggle()
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
                onToggleCamera: { sceneController.toggleCameraMode() },
                onToggleFlightAssist: { inputManager.toggleFlightAssist() },
                onTriggerBoost: { inputManager.requestBoost() },
                onSetThrottle: { inputManager.setThrottle($0) }
            )

            DebugOverlayView(
                metrics: metrics,
                inputManager: inputManager,
                showSolSheet: $showSolSheet
            )
            .padding(.top, 18)
            .padding(.leading, 20)
        }
        .background(Color.black)
        .sheet(isPresented: $showSolSheet) {
            NavigationStack {
                SolOverviewView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                showSolSheet = false
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
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
