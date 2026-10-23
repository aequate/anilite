import SwiftUI
import AniliteKit

/// Resolves a `Route` into its screen. Shared by every tab's stack.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .media(let id): MediaDetailView(mediaId: id)
        case .character(let id): CharacterView(characterId: id)
        case .staff(let id): StaffView(staffId: id)
        case .studio(let id): StudioView(studioId: id)
        case .pathfinder(let id): PathfinderView(mediaId: id)
        case .genre(let name, let type): BrowseView(kind: .genre(name), type: type)
        case .tag(let name, let type): BrowseView(kind: .tag(name), type: type)
        case .shelf(let id): ShelfView(shelfId: id)
        case .planner: PlannerView()
        case .calendar: AiringCalendarView()
        case .journal: JournalView()
        case .history: HistoryView()
        case .recap(let year): RecapView(year: year)
        case .achievements: AchievementsView()
        case .tasteDNA: TasteDNAView()
        case .social: SocialView()
        case .compareUser(let name): CompareUserView(userName: name)
        case .club(let id): ClubView(clubId: id)
        case .glossary: GlossaryView()
        case .settings: SettingsView()
        case .status(let status, let type): StatusListView(status: status, type: type)
        }
    }
}

/// Loads a value with the shared client and shows skeleton → content → retryable error.
struct AsyncContent<Value: Sendable, Content: View>: View {
    let id: String
    let load: @MainActor () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var value: Value?
    @State private var error: String?

    init(id: String, load: @escaping @MainActor () async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.id = id
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                VStack {
                    Spacer(minLength: 80)
                    ErrorBanner(message: error) { Task { await run() } }
                        .padding(Theme.gutter)
                    Spacer()
                }
            } else {
                LoadingPlaceholder()
            }
        }
        .task(id: id) { await run() }
    }

    private func run() async {
        error = nil
        do {
            let loaded = try await load()
            withAnimation(.easeOut(duration: 0.25)) { value = loaded }
        } catch is CancellationError {
            return
        } catch {
            if value == nil { self.error = AppModel.message(for: error) }
        }
    }
}

struct LoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Skeleton(cornerRadius: Theme.corner).frame(height: 220)
            Skeleton().frame(width: 220, height: 24)
            Skeleton().frame(height: 14)
            Skeleton().frame(height: 14)
            Skeleton().frame(width: 180, height: 14)
        }
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("Loading")
    }
}

/// Sumi ground with the marbled-ink backdrop, behind every screen without artwork of its own.
struct ScreenBackground: View {
    var atmosphere: Atmosphere = .brand
    var intensity: Double = 0.55

    var body: some View {
        ZStack {
            Theme.ink0
            AtmosphereView(atmosphere: atmosphere, intensity: intensity)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.7), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard screen chrome: dark atmosphere background and inline title.
    func screenChrome(_ title: String, atmosphere: Atmosphere = .brand, large: Bool = false) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { ScreenBackground(atmosphere: atmosphere) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
