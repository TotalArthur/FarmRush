import SwiftUI

@main
struct HexboundApp: App {
    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .preferredColorScheme(.light)
        }
    }
}
