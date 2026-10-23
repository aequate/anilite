import SwiftUI

/// Namespace shared by a tab's navigation stack so a poster can zoom into its detail page.
private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

/// Marks the view a detail page zooms out of (iOS 18 shared-element navigation).
private struct HeroSource: ViewModifier {
    let id: Int
    @Environment(\.heroNamespace) private var namespace
    @Environment(EffectsBudget.self) private var budget

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, budget.level != .still {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            }
        } else {
            content
        }
    }
}

/// The destination half of the zoom transition.
private struct HeroDestination: ViewModifier {
    let id: Int
    @Environment(\.heroNamespace) private var namespace
    @Environment(EffectsBudget.self) private var budget

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, budget.level != .still {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func heroSource(_ id: Int) -> some View { modifier(HeroSource(id: id)) }
    func heroDestination(_ id: Int) -> some View { modifier(HeroDestination(id: id)) }
}
