import SwiftUI
import AniliteKit

// MARK: - Received shared list

struct SharedListSheet: View {
    let list: SharedList
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var covers: [Int: Media] = [:]
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.title)
                            .font(Typo.display(24))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Curated by \(list.curator) · \(list.items.count) titles")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(list.items, id: \.id) { item in
                        Button {
                            dismiss()
                            Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                router.push(.media(item.id))
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if let media = covers[item.id] {
                                    PosterImage(media: media, width: 40, cornerRadius: 6)
                                } else {
                                    RoundedRectangle(cornerRadius: 6).fill(Theme.ink3).frame(width: 40, height: 57)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(covers[item.id].map { model.title($0) } ?? item.title)
                                        .foregroundStyle(Theme.textPrimary)
                                    if let note = item.note, !note.isEmpty {
                                        Text(note)
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    if let entry = model.entry(item.id) {
                                        Text("In your library · \(entry.status.label(for: entry.type))")
                                            .font(Typo.caption)
                                            .foregroundStyle(Theme.positive)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Notes in shared lists are stripped of spoiler markup before they're sent.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground(atmosphere: .night, intensity: 0.35))
            .navigationTitle("Shared list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Save list") { model.saveSharedList(list) }
                        if model.canEdit {
                            Button("Add missing titles to Planning") { Task { await addAll() } }
                        }
                    } label: {
                        if adding { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .task { await loadCovers() }
        }
    }

    private func loadCovers() async {
        let ids = Array(list.items.map(\.id).prefix(50))
        guard !ids.isEmpty,
              let media = try? await model.client.fetch(Queries.cards(ids: ids), policy: .cacheFirst).Page.media else { return }
        covers = Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func addAll() async {
        adding = true
        defer { adding = false }
        if covers.isEmpty { await loadCovers() }
        var added = 0
        for item in list.items where model.entry(item.id) == nil {
            if let media = covers[item.id] {
                model.add(media, status: .planning)
                added += 1
            }
        }
        model.saveSharedList(list)
        model.showBanner(added == 0 ? "You already have every title." : "Added \(added) titles to Planning.")
    }
}

// MARK: - Join a club

struct JoinClubSheet: View {
    let club: Club
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Club invite from \(club.host)")
                Text(club.name)
                    .font(Typo.display(28))
                    .foregroundStyle(Theme.textPrimary)
                Label(club.mediaTitle, systemImage: club.mediaType == .anime ? "play.tv" : "book")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(club.unitsPerSession) per session · \(ClubText.weekdays(club.weekdays))")
                    Text("Started \(club.startDate.formatted(date: .abbreviated, time: .omitted))")
                    if let next = club.nextSession(after: Date()) {
                        Text("Next session \(next.date.formatted(.dateTime.weekday(.wide).month().day()))")
                    }
                    Text("The group is at \(club.expectedProgress(on: Date())) of \(club.totalUnits).")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    var joined = club
                    let me = model.account.displayName ?? "Me"
                    if !joined.members.contains(me) && joined.host != me { joined.members.append(me) }
                    model.saveClub(joined)
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        router.push(.club(joined.id), on: .you)
                    }
                } label: {
                    Text(model.clubs.contains { $0.id == club.id } ? "Open club" : "Join club")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ScreenBackground(atmosphere: .brand, intensity: 0.4))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Received Taste DNA

struct FingerprintSheet: View {
    let fingerprint: TasteFingerprint
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let score = model.myFingerprint.compatibility(with: fingerprint)
        let shared = sharedInterests
        NavigationStack {
            VStack(spacing: 20) {
                Text(fingerprint.name)
                    .font(Typo.display(28))
                    .foregroundStyle(Theme.textPrimary)
                Text(fingerprint.archetype)
                    .font(.headline)
                    .foregroundStyle(Theme.accentCool)
                ZStack {
                    ProgressRing(progress: Double(score) / 100, tint: Theme.accent, lineWidth: 10)
                    VStack(spacing: 2) {
                        Text("\(score)%")
                            .font(Typo.bigMetric)
                            .foregroundStyle(Theme.textPrimary)
                        Text("compatible")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 170, height: 170)
                .accessibilityElement(children: .combine)
                if !shared.isEmpty {
                    Text("You both love \(shared.prefix(4).joined(separator: ", ")).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if !model.dna.isMeaningful {
                    Text("Your own Taste DNA is still forming, so this will get more accurate as you add titles.")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    model.addFriend(fingerprint)
                    Haptics.success()
                    dismiss()
                } label: {
                    Text(model.friends.contains { $0.name == fingerprint.name } ? "Update friend" : "Add as friend")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.gutter)
            .frame(maxWidth: .infinity)
            .background(ScreenBackground(atmosphere: .brand, intensity: 0.45))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Strands both people weight positively, strongest first. Keys are "g:Genre" / "t:Tag".
    private var sharedInterests: [String] {
        let mine = model.myFingerprint.weights
        return fingerprint.weights
            .filter { $0.value > 0 && (mine[$0.key] ?? 0) > 0 }
            .sorted { $0.value + (mine[$0.key] ?? 0) > $1.value + (mine[$1.key] ?? 0) }
            .map { pair -> String in
                let key = pair.key
                if let colon = key.firstIndex(of: ":") { return String(key[key.index(after: colon)...]) }
                return key
            }
    }
}

// MARK: - New club

struct NewClubSheet: View {
    let media: Media?
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: Int?
    @State private var name = ""
    @State private var perSession = 2
    @State private var weekdays: Set<Int> = [7]
    @State private var startDate = Date()

    init(media: Media?) {
        self.media = media
        _selectedId = State(initialValue: media?.id)
    }

    private var candidates: [Media] {
        var list = model.library.all
            .filter { $0.status == .current || $0.status == .planning }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.media)
        if let media, !list.contains(where: { $0.id == media.id }) { list.insert(media, at: 0) }
        return list
    }

    private var selected: Media? { candidates.first { $0.id == selectedId } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    if candidates.isEmpty {
                        Text("Add something to Watching or Planning first, or start a club from any title's page.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Picker("Watch or read", selection: $selectedId) {
                            Text("Choose…").tag(Int?.none)
                            ForEach(candidates) { media in
                                Text(model.title(media)).tag(Int?.some(media.id))
                            }
                        }
                    }
                }
                Section("Club") {
                    TextField(selected.map { "\(model.title($0)) club" } ?? "Club name", text: $name)
                    Stepper("\(perSession) \(selected?.unitName ?? "episode")\(perSession == 1 ? "" : "s") per session", value: $perSession, in: 1...50)
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                }
                Section("Meets on") {
                    WeekdayPicker(selection: $weekdays)
                }
                if let selected, let total = selected.totalUnits ?? selected.releasedUnits {
                    Section {
                        let sessions = Int((Double(total) / Double(perSession)).rounded(.up))
                        let weeks = Int((Double(sessions) / Double(max(1, weekdays.count))).rounded(.up))
                        Text("\(sessions) sessions · about \(weeks) week\(weeks == 1 ? "" : "s")")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink1)
            .navigationTitle("New club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(selected == nil || weekdays.isEmpty)
                }
            }
        }
    }

    private func create() {
        guard let selected else { return }
        let total = selected.totalUnits ?? selected.releasedUnits ?? 12
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let club = Club(name: trimmed.isEmpty ? "\(model.title(selected)) club" : trimmed,
                        mediaId: selected.id, mediaTitle: model.title(selected), mediaType: selected.mediaType,
                        totalUnits: total, unitsPerSession: perSession, weekdays: Array(weekdays),
                        startDate: Calendar.current.startOfDay(for: startDate), host: model.account.displayName ?? "Me")
        model.saveClub(club)
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.push(.club(club.id), on: .you)
        }
    }
}

/// Seven toggles, Sunday first, matching `Calendar` weekday numbers (1 = Sunday).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let full = Calendar.current.weekdaySymbols
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    Haptics.tick()
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(on ? Theme.accent : Theme.ink3))
                        .foregroundStyle(on ? Color.white : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(full[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - New shelf

struct NewShelfSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "books.vertical.fill"
    @State private var isSmart = false
    @State private var type: MediaType? = nil
    @State private var statuses: Set<MediaListStatus> = []
    @State private var genres: Set<String> = []
    @State private var useMinScore = false
    @State private var minScore: Double = 70
    @State private var useMaxRemaining = false
    @State private var maxRemainingHours = 5
    @State private var useUntouched = false
    @State private var untouchedDays = 60

    private let symbols = ["books.vertical.fill", "star.fill", "heart.fill", "flame.fill", "moon.stars.fill", "leaf.fill",
                           "bolt.fill", "theatermasks.fill", "sparkles", "cup.and.saucer.fill", "gamecontroller.fill", "music.note"]

    private var allGenres: [String] {
        Array(Set(model.library.all.flatMap { $0.media.genres ?? [] })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Shelf name", text: $name)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(symbols, id: \.self) { item in
                            Button {
                                symbol = item
                                Haptics.tick()
                            } label: {
                                Image(systemName: item)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(symbol == item ? Theme.accent : Theme.ink3))
                                    .foregroundStyle(symbol == item ? Color.white : Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Smart shelf", isOn: $isSmart.animation())
                } footer: {
                    Text(isSmart ? "Smart shelves fill themselves from rules and stay up to date." : "Add titles to this shelf from their edit sheet.")
                }

                if isSmart {
                    Section("Rules") {
                        Picker("Type", selection: $type) {
                            Text("Anime & manga").tag(MediaType?.none)
                            Text("Anime").tag(MediaType?.some(.anime))
                            Text("Manga").tag(MediaType?.some(.manga))
                        }
                        NavigationLink {
                            MultiPick(title: "Statuses", options: MediaListStatus.allCases, label: { $0.label(for: type ?? .anime) }, selection: $statuses)
                        } label: {
                            LabeledContent("Status", value: statuses.isEmpty ? "Any" : statuses.map { $0.label(for: type ?? .anime) }.sorted().joined(separator: ", "))
                        }
                        if !allGenres.isEmpty {
                            NavigationLink {
                                MultiPick(title: "Genres", options: allGenres, label: { $0 }, selection: $genres)
                            } label: {
                                LabeledContent("Genres", value: genres.isEmpty ? "Any" : genres.sorted().joined(separator: ", "))
                            }
                        }
                        Toggle("Minimum score", isOn: $useMinScore)
                        if useMinScore {
                            Slider(value: $minScore, in: 10...100, step: 5) { Text("Minimum score") }
                            Text("At least \(model.scoreFormat.display(minScore))")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Toggle("Short on time left", isOn: $useMaxRemaining)
                        if useMaxRemaining {
                            Stepper("Under \(maxRemainingHours) hour\(maxRemainingHours == 1 ? "" : "s") left", value: $maxRemainingHours, in: 1...100)
                        }
                        Toggle("Untouched for a while", isOn: $useUntouched)
                        if useUntouched {
                            Stepper("No progress for \(untouchedDays) days", value: $untouchedDays, in: 7...720, step: 7)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink1)
            .navigationTitle("New shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        var rule: SmartRule?
        if isSmart {
            rule = SmartRule(type: type, statuses: Array(statuses), genres: Array(genres),
                             minScore: useMinScore ? minScore : nil,
                             maxRemainingMinutes: useMaxRemaining ? maxRemainingHours * 60 : nil,
                             untouchedDays: useUntouched ? untouchedDays : nil)
        }
        model.createShelf(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, rule: rule)
        Haptics.success()
        dismiss()
    }
}

private struct MultiPick<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Set<Option>

    var body: some View {
        List(options, id: \.self) { option in
            Button {
                if selection.contains(option) { selection.remove(option) } else { selection.insert(option) }
            } label: {
                HStack {
                    Text(label(option)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if selection.contains(option) {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Share a list

struct ShareListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = "My favourites"
    @State private var picked: [Int] = []
    @State private var notes: [Int: String] = [:]
    @State private var type: MediaType = .anime

    private var pool: [LibraryEntry] {
        model.library.all
            .filter { $0.type == type && ($0.status == .completed || $0.status == .current || $0.status == .repeating) }
            .sorted { ($0.score, $0.updatedAt) > ($1.score, $1.updatedAt) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List title", text: $title)
                    Picker("Type", selection: $type) {
                        Text("Anime").tag(MediaType.anime)
                        Text("Manga").tag(MediaType.manga)
                    }
                    .pickerStyle(.segmented)
                }
                if !picked.isEmpty {
                    Section("In this list (\(picked.count))") {
                        ForEach(picked, id: \.self) { id in
                            if let entry = model.entry(id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.title(entry.media))
                                    TextField("Why you love it (optional)", text: Binding(
                                        get: { notes[id] ?? "" },
                                        set: { notes[id] = $0 }))
                                        .font(.footnote)
                                }
                            }
                        }
                        .onMove { picked.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { picked.remove(atOffsets: $0) }
                    }
                }
                Section("Add from your library") {
                    if pool.isEmpty {
                        Text("Finish or start something to share it.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(pool.prefix(80)) { entry in
                        Button {
                            if let index = picked.firstIndex(of: entry.mediaId) { picked.remove(at: index) } else if picked.count < 50 { picked.append(entry.mediaId) }
                        } label: {
                            HStack {
                                Image(systemName: picked.contains(entry.mediaId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(entry.mediaId) ? Theme.accent : Theme.textTertiary)
                                Text(model.title(entry.media)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if entry.isScored {
                                    Text(model.scoreFormat.display(entry.score))
                                        .font(Typo.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink1)
            .navigationTitle("Share a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let link = sharedList.link, !picked.isEmpty {
                        ShareLink(item: link, subject: Text(title), message: Text("\(title) — open in Anilite")) {
                            Text("Share")
                        }
                    }
                }
            }
        }
    }

    private var sharedList: SharedList {
        let entries = picked.compactMap { model.entry($0) }
        return SharedList.from(title: title.isEmpty ? "My list" : title, curator: model.account.displayName ?? "A friend",
                               entries: entries, notes: notes)
    }
}
