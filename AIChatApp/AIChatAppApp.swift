import SwiftUI

@main
struct AIChatAppApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var assistants = AssistantStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(assistants)
        }
    }
}
