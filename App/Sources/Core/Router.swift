import SwiftUI
import Observation
import AniliteKit

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case discover, find, atlas, library, you

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .find: return "Find"
        case .atlas: return "Atlas"
        case .library: return "Library"
        case .you: return "You"
        }
    }

    var symbol: String {
        switch self {
        case .discover: return "sparkles"
        case .find: return "wand.and.stars"
        case .atlas: return "point.3.connected.trianglepath.dotted"
        case .library: return "books.vertical.fill"
        case .you: return "person.crop.circle.fill"
        }
    }
}

/// Push destinations shared by every tab's navigation stack.
enum Route: Hashable {
    case media(Int)
    case character(Int)
    case staff(Int)
    case studio(Int)
    case pathfinder(Int)
    case genre(String, MediaType)
    case tag(String, MediaType)
    case shelf(UUID)
    case planner
    case calendar
    case journal
    case history
    case recap(Int)
    case achievements
    case tasteDNA
    case social
    case compareUser(String)
    case club(String)
    case glossary
    case settings
    case status(MediaListStatus, MediaType)
}

/// Modal destinations.
enum SheetRoute: Identifiable {
    case concierge
    case editor(Media)
    case journalCompose(Media)
    case sharedList(SharedList)
    case joinClub(Club)
    case fingerprint(TasteFingerprint)
    case newClub(Media?)
    case newShelf
    case shareList

    var id: String {
        switch self {
        case .concierge: return "concierge"
        case .editor(let m): return "editor-\(m.id)"
        case .journalCompose(let m): return "journal-\(m.id)"
        case .sharedList(let l): return "list-\(l.id)"
        case .joinClub(let c): return "club-\(c.id)"
        case .fingerprint(let f): return "dna-\(f.name)"
        case .newClub(let m): return "newclub-\(m?.id ?? 0)"
        case .newShelf: return "newshelf"
        case .shareList: return "sharelist"
        }
    }
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .discover
    var paths: [AppTab: NavigationPath] = [:]
    var sheet: SheetRoute?
    /// A natural-language query handed to the Find tab (from mood chips, the Concierge, etc.).
    var pendingSearch: String?

    func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    func push(_ route: Route, on tab: AppTab? = nil) {
        let target = tab ?? self.tab
        var path = paths[target] ?? NavigationPath()
        path.append(route)
        paths[target] = path
        if self.tab != target { self.tab = target }
    }

    func search(_ text: String) {
        pendingSearch = text
        if tab != .find { tab = .find }
        popToRoot(.find)
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = NavigationPath()
    }

    /// Selecting the current tab again pops it to the top, like system tab bars.
    func select(_ tab: AppTab) {
        if self.tab == tab {
            popToRoot(tab)
        } else {
            self.tab = tab
        }
    }
}
