import SwiftUI
import AniliteKit

@main
struct AniliteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel(effects: EffectsBudget()))
        Self.styleNavigationBars()
    }

    /// Serif titles in the navigation bar, to match the in-page headings. The bar stays
    /// transparent so each screen's backdrop runs to the top edge.
    private static func styleNavigationBars() {
        func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let weighted = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            guard let descriptor = weighted.fontDescriptor.withDesign(.serif) else { return weighted }
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
        let ink = UIColor(red: 0.937, green: 0.918, blue: 0.878, alpha: 1)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.font: serif(.headline, weight: .semibold), .foregroundColor: ink]
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .bold), .foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        let model = self.model
        WindowGroup {
            AppRoot()
                .environment(model)
                .environment(model.effects)
                .environment(model.router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { model.handle($0) }
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                AiringReminders.scheduleBackgroundRefresh()
                Task { await model.flush() }
            case .active:
                model.effects.refresh()
                Task { await model.flush() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AiringReminders.refreshTaskId)) {
            await model.backgroundRefresh()
        }
    }
}
