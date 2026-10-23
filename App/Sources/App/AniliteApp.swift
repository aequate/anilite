import SwiftUI
import AniliteKit

@main
struct AniliteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel(effects: EffectsBudget()))
    }

    var body: some Scene {
        let model = self.model
        WindowGroup {
            AppRoot()
                .environment(model)
                .environment(model.effects)
                .environment(model.router)
                .preferredColorScheme(.dark)
                .tint(Theme.brand)
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
