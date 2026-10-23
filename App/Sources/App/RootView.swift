import SwiftUI
import AniliteKit

/// Chooses onboarding or the main shell.
struct AppRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.ink0.ignoresSafeArea()
            if model.needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.needsOnboarding)
    }
}

/// Five tab stacks under a floating liquid-glass dock.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases) { tab in
                TabStack(tab: tab)
                    .tag(tab)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .overlay(alignment: .bottom) { Dock() }
        .overlay(alignment: .top) { StatusBanners() }
        .sheet(item: $router.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(model)
                .environment(model.effects)
                .environment(model.router)
        }
    }
}

/// One tab's navigation stack with the shared destinations and hero namespace.
private struct TabStack: View {
    let tab: AppTab
    @Environment(Router.self) private var router
    @Namespace private var hero

    var body: some View {
        NavigationStack(path: router.path(for: tab)) {
            root
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
        .environment(\.heroNamespace, hero)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Dock.height)
        }
    }

    @ViewBuilder private var root: some View {
        switch tab {
        case .discover: DiscoverView()
        case .find: FindView()
        case .atlas: AtlasView()
        case .library: LibraryView()
        case .you: YouView()
        }
    }
}

/// Floating dock. Icons only with VoiceOver labels; the selected tab gets a liquid pill.
struct Dock: View {
    static let height: CGFloat = 78

    @Environment(Router.self) private var router
    @Environment(EffectsBudget.self) private var budget
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    item(tab)
                }
            }
            .padding(5)
            .glassCapsule(interactive: true)

            Button {
                Haptics.tap(.medium)
                router.sheet = .concierge
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.brand, Theme.brandCool], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                    .glassCapsule(tint: Theme.brand, interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Ask the Concierge")
            .accessibilityHint("Questions like where to start, what's filler, or what to watch next")
        }
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        return Button {
            if router.tab != tab { Haptics.tick() }
            withAnimation(budget.allowsPhysics ? .spring(response: 0.38, dampingFraction: 0.72) : .easeInOut(duration: 0.2)) {
                router.select(tab)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(tab.title)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .frame(width: 56, height: 50)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Offline, sync and session messages.
private struct StatusBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if model.sessionExpired {
                banner(symbol: "person.crop.circle.badge.exclamationmark", text: "Your AniList session ended. Your library is safe on this device.",
                       action: "Sign in") {
                    Task { await model.signIn() }
                }
            } else if model.isOffline {
                banner(symbol: "wifi.slash", text: offlineText, action: nil, perform: nil)
            }
            if let message = model.banner {
                banner(symbol: "info.circle.fill", text: message, action: nil, perform: nil)
                    .onTapGesture { model.banner = nil }
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.banner)
        .animation(.easeInOut, value: model.isOffline)
    }

    private var offlineText: String {
        let pending = model.queue.count
        return pending > 0 ? "Offline · \(pending) change\(pending == 1 ? "" : "s") will sync when you reconnect" : "Offline · showing saved data"
    }

    private func banner(symbol: String, text: String, action: String?, perform: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.caution)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action, let perform {
                Button(action, action: perform)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

/// Resolves a sheet route.
private struct SheetHost: View {
    let sheet: SheetRoute

    var body: some View {
        switch sheet {
        case .concierge: ConciergeView()
        case .editor(let media): EntryEditorSheet(media: media)
        case .journalCompose(let media): JournalComposeSheet(media: media)
        case .sharedList(let list): SharedListSheet(list: list)
        case .joinClub(let club): JoinClubSheet(club: club)
        case .fingerprint(let fingerprint): FingerprintSheet(fingerprint: fingerprint)
        case .newClub(let media): NewClubSheet(media: media)
        case .newShelf: NewShelfSheet()
        case .shareList: ShareListSheet()
        }
    }
}
