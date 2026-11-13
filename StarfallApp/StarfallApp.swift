import SwiftUI

@main
struct StarfallApp: App {
    var body: some Scene {
        WindowGroup {
            SolOverviewView()
                .preferredColorScheme(.dark)
        }
    }
}
