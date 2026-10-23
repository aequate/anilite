import SwiftUI
import AniliteKit

/// Library home: what's in progress, every status at a glance, shelves, and the planning
/// tools (binge planner, airing calendar, journal, history).
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var type: MediaType = .anime
    @State private var filter = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                if model.library.isEmpty {
                    emptyState
                } else if !filter.isEmpty {
                    filtered
                } else {
                    inProgress
                    statusGrid
                    backlog
                    shelves
                }
                tools
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.syncLibrary(force: true) }
        .background { ScreenBackground(atmosphere: .night, intensity: 0.45) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(Typo.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SyncBadge()
            }
            Text(model.account.summary)
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
            if !model.library.isEmpty {
                Picker("Type", selection: $type.animation(Motion.standard)) {
                    Text("Anime").tag(MediaType.anime)
                    Text("Manga").tag(MediaType.manga)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.textTertiary)
                    TextField("Filter your library", text: $filter)
                        .submitLabel(.done)
                    if !filter.isEmpty {
                        Button { filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                        }
                        .accessibilityLabel("Clear filter")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .surface(cornerRadius: 16, interactive: true)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            EmptyStateView(symbol: "books.vertical", title: "Your shelves are empty",
                           message: model.canEdit
                               ? "Add anything you're watching, reading or planning. Your progress, forecasts and recaps build from here."
                               : "This profile has no public list entries yet.",
                           actionTitle: "Find something", action: { router.select(.find) })
            if model.syncState.isLoading {
                ProgressView("Syncing…")
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
    }

    // MARK: Sections

    private var entries: [LibraryEntry] { model.library.entries(type: type) }

    @ViewBuilder private var inProgress: some View {
        let active = entries.filter { $0.status.isActive }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: type == .anime ? "Watching" : "Reading", subtitle: "\(active.count) in progress")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(active.prefix(20)) { entry in
                            ContinueCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var statusGrid: some View {
        let all = entries
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Everything")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(MediaListStatus.allCases, id: \.self) { status in
                    let items = all.filter { $0.status == status }
                    NavigationLink(value: Route.status(status, type)) {
                        StatusTile(status: status, type: type, count: items.count, covers: items.prefix(3).map(\.media))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder private var backlog: some View {
        let forecast = Forecast.backlog(model.library, pace: model.pace)
        if forecast.minutes > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Backlog forecast")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Formatting.duration(minutes: forecast.minutes))
                        .font(Typo.bigMetric)
                        .foregroundStyle(Theme.textPrimary)
                    Text("to clear what you've started")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let days = forecast.days {
                    Text("About \(days) days at your recent pace of \(Formatting.duration(minutes: Int(model.pace.minutesPerDay))) a day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                NavigationLink(value: Route.planner) {
                    Label("Plan it out", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: Theme.corner)
            .padding(.horizontal, Theme.gutter)
        }
    }

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Shelves", subtitle: "Smart shelves fill themselves") {
                if model.canEdit || model.account == .local {
                    Button {
                        router.sheet = .newShelf
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .capsuleSurface(interactive: true)
                    }
                    .accessibilityLabel("New shelf")
                }
            }
            .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.allShelves) { shelf in
                        NavigationLink(value: Route.shelf(shelf.id)) {
                            ShelfTile(shelf: shelf, entries: shelf.entries(in: model.library))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Tools")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ToolTile(route: .planner, title: "Binge Planner", symbol: "calendar.badge.clock", tint: Theme.accent)
                ToolTile(route: .calendar, title: "Airing Calendar", symbol: "dot.radiowaves.left.and.right", tint: Theme.accentCool)
                ToolTile(route: .journal, title: "Journal", symbol: "book.closed.fill", tint: Theme.caution)
                ToolTile(route: .history, title: "History", symbol: "clock.arrow.circlepath", tint: Theme.positive)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder private var filtered: some View {
        let needle = filter.lowercased()
        let matches = model.library.all.filter { entry in
            let media = entry.media
            let titles = [media.title?.english, media.title?.romaji, media.title?.native, media.title?.userPreferred].compactMap { $0?.lowercased() }
            return titles.contains { $0.contains(needle) } || (media.synonyms ?? []).contains { $0.lowercased().contains(needle) }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "\(matches.count) matching")
            ForEach(matches) { entry in
                MediaRow(media: entry.media, detail: LibraryText.progress(entry))
                Divider().overlay(Theme.hairline)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

enum LibraryText {
    static func progress(_ entry: LibraryEntry) -> String {
        let media = entry.media
        var parts: [String] = [entry.status.label(for: entry.type)]
        if entry.status != .planning {
            parts.append(media.totalUnits.map { "\(media.unitShort) \(entry.progress)/\($0)" } ?? "\(media.unitShort) \(entry.progress)")
        }
        if entry.isScored { parts.append("★ \(ScoreFormat.point10Decimal.display(entry.score))") }
        return parts.joined(separator: " · ")
    }
}

/// Sync state: offline, pending changes, syncing, or a quiet check.
struct SyncBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isOffline {
                StatPill(symbol: "wifi.slash", text: model.queue.isEmpty ? "Offline" : "\(model.queue.count) waiting", tint: Theme.caution)
            } else if model.isFlushing || model.syncState.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Syncing").font(Typo.caption).foregroundStyle(Theme.textSecondary)
                }
            } else if !model.queue.isEmpty {
                StatPill(symbol: "arrow.triangle.2.circlepath", text: "\(model.queue.count) pending", tint: Theme.caution)
            } else if let synced = model.library.lastSynced, model.account.isConnected || model.account.displayName != nil {
                StatPill(symbol: "checkmark.icloud", text: synced.formatted(.relative(presentation: .named)), tint: Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusTile: View {
    let status: MediaListStatus
    let type: MediaType
    let count: Int
    let covers: [Media]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: StatusDot.symbol(status))
                    .foregroundStyle(StatusDot.color(status))
                Spacer()
                HStack(spacing: -12) {
                    ForEach(covers) { media in
                        PosterImage(media: media, width: 24, cornerRadius: 4)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                }
            }
            Text("\(count)")
                .font(Typo.metric)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(status.label(for: type))
                .font(Typo.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.label(for: type)), \(count)")
    }
}

private struct ShelfTile: View {
    let shelf: Shelf
    let entries: [LibraryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.ink2)
                    .frame(width: 150, height: 92)
                HStack(spacing: -22) {
                    ForEach(entries.prefix(4)) { entry in
                        PosterImage(media: entry.media, width: 44, cornerRadius: 6)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 2)
                    }
                }
                .padding(10)
                if entries.isEmpty {
                    Image(systemName: shelf.symbol)
                        .font(.title)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 150, height: 92)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: shelf.symbol).font(.caption).foregroundStyle(Theme.accentCool)
                Text(shelf.name)
                    .font(Typo.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Text(shelf.isSmart ? "Smart · \(entries.count)" : "\(entries.count) titles")
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ToolTile: View {
    let route: Route
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .surface(cornerRadius: 16, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Status list

struct StatusListView: View {
    let status: MediaListStatus
    let type: MediaType

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recent", title = "Title", score = "Score", remaining = "Time left", added = "Year"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var sort: Sort = .recent

    var body: some View {
        let items = sorted(model.library.entries(type: type, status: status))
        List {
            if items.isEmpty {
                EmptyStateView(symbol: StatusDot.symbol(status), title: "Nothing here", message: "Titles you mark as \(status.label(for: type).lowercased()) will appear here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { entry in
                MediaRow(media: entry.media, detail: detail(entry))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.hairline)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if model.canEdit, entry.status.isActive, (entry.media.totalUnits ?? Int.max) > entry.progress {
                            Button { model.increment(entry) } label: { Label("+1", systemImage: "plus") }
                                .tint(Theme.positive)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if model.canEdit {
                            Button(role: .destructive) { model.remove(mediaId: entry.mediaId) } label: { Label("Remove", systemImage: "trash") }
                            Button { router.sheet = .editor(entry.media) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                                .tint(Theme.accentCool)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .screenChrome(status.label(for: type))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
        }
    }

    private func sorted(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        switch sort {
        case .recent: return entries.sorted { $0.updatedAt > $1.updatedAt }
        case .title: return entries.sorted { model.title($0.media).localizedCompare(model.title($1.media)) == .orderedAscending }
        case .score: return entries.sorted { $0.score > $1.score }
        case .remaining: return entries.sorted { ($0.remainingMinutes ?? Int.max) < ($1.remainingMinutes ?? Int.max) }
        case .added: return entries.sorted { ($0.media.year ?? 0) > ($1.media.year ?? 0) }
        }
    }

    private func detail(_ entry: LibraryEntry) -> String {
        var parts = [LibraryText.progress(entry)]
        if entry.status.isActive, let minutes = entry.remainingMinutes, minutes > 0 {
            parts.append("\(Formatting.duration(minutes: minutes)) left")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shelf

struct ShelfView: View {
    let shelfId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let shelf = model.shelf(shelfId) {
            let items = shelf.entries(in: model.library)
            List {
                if let rule = shelf.rule {
                    Text(Self.describe(rule))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .listRowBackground(Color.clear)
                }
                if items.isEmpty {
                    EmptyStateView(symbol: shelf.symbol, title: "Empty shelf",
                                   message: shelf.isSmart ? "Nothing in your library matches this shelf yet." : "Add titles from any title's editor.")
                        .listRowBackground(Color.clear)
                }
                ForEach(items) { entry in
                    MediaRow(media: entry.media, detail: LibraryText.progress(entry))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.hairline)
                        .swipeActions(edge: .trailing) {
                            if !shelf.isSmart {
                                Button(role: .destructive) { model.toggle(entry.mediaId, onShelf: shelf.id) } label: { Label("Take off shelf", systemImage: "minus.circle") }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .screenChrome(shelf.name)
            .toolbar {
                if model.shelves.contains(where: { $0.id == shelf.id }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete shelf")
                    }
                }
            }
            .confirmationDialog("Delete “\(shelf.name)”? Titles stay in your library.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete shelf", role: .destructive) {
                    model.deleteShelf(shelf.id)
                    dismiss()
                }
            }
        } else {
            EmptyStateView(symbol: "questionmark.folder", title: "Shelf not found", message: "It may have been deleted.")
                .screenChrome("Shelf")
        }
    }

    static func describe(_ rule: SmartRule) -> String {
        var parts: [String] = []
        if let type = rule.type { parts.append(type == .anime ? "Anime" : "Manga") }
        if !rule.statuses.isEmpty { parts.append(rule.statuses.map { $0.label(for: rule.type ?? .anime) }.joined(separator: " or ")) }
        if !rule.genres.isEmpty { parts.append(rule.genres.joined(separator: ", ")) }
        if let score = rule.minScore { parts.append("scored \(Int(score))+") }
        if let minutes = rule.maxRemainingMinutes { parts.append("under \(Formatting.duration(minutes: minutes)) left") }
        if let days = rule.untouchedDays { parts.append("untouched for \(days)+ days") }
        if let list = rule.customList { parts.append("in “\(list)”") }
        return "Smart shelf: " + parts.joined(separator: " · ")
    }
}
