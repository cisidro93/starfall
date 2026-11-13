import SwiftUI
import RealityKit
import simd

@MainActor
final class SceneController: ObservableObject {
    let rootEntity = Entity()
    let cameraEntity = Entity()
    var updateSubscription: EventSubscription?

    var yawRadians: Float = 0.0
    var pitchRadians: Float = 0.0
    var dragStartYaw: Float = 0.0
    var dragStartPitch: Float = 0.0
    var isDragging: Bool = false

    func setupSceneIfNeeded() {
        guard rootEntity.children.isEmpty else { return }
        rootEntity.name = "StarfallSpaceRoot"

        let skybox = StarfieldGenerator.makeSkyboxEntity()
        rootEntity.addChild(skybox)

        cameraEntity.name = "MainVirtualCamera"
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = 60.0
        cameraEntity.components.set(camera)
        rootEntity.addChild(cameraEntity)
        applyCameraRotation()
    }

    func stepFrame(deltaTime: TimeInterval, autoPan: Bool) {
        if autoPan && !isDragging {
            let dt = Float(min(max(deltaTime, 0.0), 0.1))
            yawRadians += dt * 0.12
            if yawRadians > .pi * 2.0 {
                yawRadians -= .pi * 2.0
            }
            pitchRadians = sin(yawRadians * 0.6) * 0.22
            applyCameraRotation()
        }
    }

    func applyCameraRotation() {
        let yawQuat = simd_quatf(angle: yawRadians, axis: SIMD3<Float>(0, 1, 0))
        let pitchQuat = simd_quatf(angle: pitchRadians, axis: SIMD3<Float>(1, 0, 0))
        cameraEntity.transform.rotation = simd_mul(yawQuat, pitchQuat)
    }
}

struct SpaceSceneView: View {
    @StateObject private var metrics = DebugMetrics()
    @StateObject private var sceneController = SceneController()
    @State private var showSolSheet = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.camera = .virtual
                sceneController.setupSceneIfNeeded()
                content.add(sceneController.rootEntity)

                let metricsRef = metrics
                let controllerRef = sceneController
                controllerRef.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        controllerRef.stepFrame(
                            deltaTime: event.deltaTime,
                            autoPan: metricsRef.autoPanEnabled
                        )
                        metricsRef.recordFrame(
                            deltaTime: event.deltaTime,
                            rootEntity: controllerRef.rootEntity
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .gesture(lookDragGesture)

            CenterReticleView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            DebugOverlayView(metrics: metrics, showSolSheet: $showSolSheet)
                .padding(.top, 20)
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

    private var lookDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !sceneController.isDragging {
                    sceneController.isDragging = true
                    sceneController.dragStartYaw = sceneController.yawRadians
                    sceneController.dragStartPitch = sceneController.pitchRadians
                }
                let sensitivity: Float = 0.004
                sceneController.yawRadians = sceneController.dragStartYaw - Float(value.translation.width) * sensitivity
                let rawPitch = sceneController.dragStartPitch - Float(value.translation.height) * sensitivity
                sceneController.pitchRadians = min(max(rawPitch, -1.4), 1.4)
                sceneController.applyCameraRotation()
            }
            .onEnded { _ in
                sceneController.isDragging = false
            }
    }
}

private struct CenterReticleView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.orange.opacity(0.8))
                .frame(width: 4, height: 4)
        }
    }
}
