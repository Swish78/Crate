import SwiftUI

@main
struct CrateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar) // Modern macOS appearance
    }
}
