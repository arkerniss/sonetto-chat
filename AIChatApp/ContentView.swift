import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ChatView()
            .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
