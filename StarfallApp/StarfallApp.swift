import SwiftUI

@main
struct StarfallApp: App {
    var body: some Scene {
        WindowGroup {
            SpaceSceneView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
