import SwiftUI
import AniliteKit

@main
struct AniliteApp: App {
    @State private var effects = EffectsBudget()

    var body: some Scene {
        WindowGroup {
            BootView()
                .environment(effects)
                .preferredColorScheme(.dark)
        }
    }
}

/// Temporary first screen while the rest of the app lands.
struct BootView: View {
    var body: some View {
        ZStack {
            AtmosphereView(atmosphere: .brand)
            VStack(spacing: 12) {
                Text("ANILITE").font(Typo.display(40)).foregroundStyle(Theme.textPrimary)
                Text("Anime and manga, one universe.").foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
