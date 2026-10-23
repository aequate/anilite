import SwiftUI
import AniliteKit

// MARK: - Social hub

/// Friends, clubs and shared lists. Sharing works through links that carry everything
/// inside them, so there's no Anilite server and nothing to sign up for.
struct SocialView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var code = ""
    @State private var userQuery = ""
    @State private var users: [AniListUser] = []
    @State private var searching = false

    var body: some View {
        List {
            Section {
                myCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    TextField("AniList username", text: $userQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await searchUsers() } }
                    if searching { ProgressView() }
                }
                ForEach(users) { user in
                    NavigationLink(value: Route.compareUser(user.name)) {
                        HStack(spacing: 12) {
                            RemoteImage(user.avatar?.medium, points: 36)
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                            Text(user.name)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            } header: {
                Text("Compare with an AniList user")
            } footer: {
                Text("Works with any public AniList profile. Spoiler protection still follows your own progress.")
            }

            Section {
                HStack {
                    TextField("Paste a Taste DNA code or link", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") { addFromCode() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.friends.isEmpty {
                    Text("Friends you add appear here with your compatibility.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(model.friends, id: \.name) { friend in
                    Button {
                        router.sheet = .fingerprint(friend)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.name)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(friend.archetype)
                                    .font(Typo.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            CompatibilityBadge(score: model.myFingerprint.compatibility(with: friend))
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.removeFriend(named: friend.name) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            } header: {
                Text("Friends")
            }

            Section {
                ForEach(model.clubs) { club in
                    NavigationLink(value: Route.club(club.id)) {
                        ClubRow(club: club)
                    }
                }
                Button {
                    router.sheet = .newClub(nil)
                } label: {
                    Label("Start a watch club", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Watch & read clubs")
            } footer: {
                Text("A club shares a schedule. Everyone sees the same spoiler line, so nobody gets ahead of the group by accident.")
            }

            Section {
                ForEach(model.savedLists) { list in
                    Button {
                        router.sheet = .sharedList(list)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.title).foregroundStyle(Theme.textPrimary)
                            Text("\(list.items.count) titles · by \(list.curator)")
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.removeSharedList(list.id) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                Button {
                    router.sheet = .shareList
                } label: {
                    Label("Share a list", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Shared lists")
            }
        }
        .scrollContentBackground(.hidden)
        .screenChrome("Friends & Clubs")
    }

    private var myCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArchetypeCard(dna: model.dna, name: model.account.displayName ?? "You")
            if let link = ShareCodec.link(kind: "dna", code: model.myFingerprint.code) {
                ShareLink(item: link, subject: Text("My Taste DNA"),
                          message: Text("Open in Anilite to see how compatible our anime tastes are.")) {
                    Label("Invite a friend to compare", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }

    private func addFromCode() {
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw), url.scheme == ShareCodec.scheme {
            model.handle(url)
            code = ""
            return
        }
        if let fingerprint = TasteFingerprint.decode(raw) {
            model.addFriend(fingerprint)
            code = ""
            Haptics.success()
        } else {
            model.showBanner("That code isn't a Taste DNA code.")
            Haptics.warning()
        }
    }

    private func searchUsers() async {
        let text = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 1 else { return }
        searching = true
        defer { searching = false }
        do {
            users = try await model.client.fetch(Queries.searchUsers(text), policy: .networkFirst).Page.users
            if users.isEmpty { model.showBanner("No AniList users matched “\(text)”.") }
        } catch {
            model.showBanner(AppModel.message(for: error))
        }
    }
}

struct CompatibilityBadge: View {
    let score: Int

    var body: some View {
        ZStack {
            ProgressRing(progress: Double(score) / 100, tint: tint, lineWidth: 3)
            Text("\(score)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 40, height: 40)
        .accessibilityElement()
        .accessibilityLabel("\(score) percent compatible")
    }

    private var tint: Color {
        switch score {
        case 75...: return Theme.positive
        case 50..<75: return Theme.accentCool
        case 30..<50: return Theme.caution
        default: return Theme.negative
        }
    }
}

private struct ClubRow: View {
    let club: Club
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.entry(club.mediaId)?.progress ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Text(club.name)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Text(club.mediaTitle)
                Text("·")
                Text(ClubText.standing(club.standing(progress: progress, on: Date()), unit: club.mediaType == .anime ? "ep" : "ch"))
            }
            .font(Typo.caption)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
        }
    }
}

enum ClubText {
    static func standing(_ standing: Club.Standing, unit: String) -> String {
        switch standing {
        case .onTrack: return "On track"
        case .ahead(let n): return "\(n) \(unit) ahead"
        case .behind(let n): return "\(n) \(unit) behind"
        }
    }

    static func weekdays(_ days: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
    }
}

// MARK: - Compare with a user

struct CompareUserView: View {
    let userName: String
    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncContent(id: "compare-\(userName)") { [userName] () async throws -> Library in
            let response = try await model.client.fetch(Queries.lists(userName: userName), policy: .cacheFirst)
            return Library.from(anime: response.anime, manga: response.manga, user: response.anime?.user ?? response.manga?.user, isReadOnly: true)
        } content: { theirs in
            CompareContent(theirs: theirs, name: theirs.user?.name ?? userName)
        }
        .screenChrome("Compatibility")
    }
}

private struct CompareContent: View {
    let theirs: Library
    let name: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let report = Compatibility.compare(mine: model.library, theirs: theirs, theirName: name)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    ZStack {
                        ProgressRing(progress: Double(report.score) / 100, tint: Theme.accent, lineWidth: 8)
                        Text("\(report.score)%")
                            .font(Typo.metric)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 100, height: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You & \(name)")
                            .font(Typo.display(22))
                            .foregroundStyle(Theme.textPrimary)
                        Text(report.verdict)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(report.sharedCount) titles in common")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)

                if !report.sharedGenres.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "What you share")
                        FlowLayout(spacing: 8) {
                            ForEach(report.sharedGenres, id: \.self) { Chip(label: $0, symbol: nil, isSelected: true) }
                        }
                        if !report.theirStrengths.isEmpty {
                            Text("\(name) leans into \(report.theirStrengths.prefix(3).joined(separator: ", ")).")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if !report.myStrengths.isEmpty {
                            Text("You lean into \(report.myStrengths.prefix(3).joined(separator: ", ")).")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                if !report.sharedFavorites.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Favourites in common")
                        ForEach(report.sharedFavorites.prefix(6)) { fav in
                            NavigationLink(value: Route.media(fav.media.id)) {
                                HStack(spacing: 12) {
                                    PosterImage(media: fav.media, width: 38, cornerRadius: 6)
                                    Text(model.title(fav.media))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(2)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("You \(model.scoreFormat.display(fav.myScore))")
                                        Text("\(name) \(model.scoreFormat.display(fav.theirScore))")
                                    }
                                    .font(Typo.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !report.watchTogether.isEmpty {
                    MediaRail(title: "Watch together", subtitle: "Neither of you has seen these, and both of you should like them",
                              items: report.watchTogether)
                        .padding(.horizontal, -Theme.gutter)
                }
                if !report.picksForMe.isEmpty {
                    MediaRail(title: "From \(name)'s favourites", subtitle: "Loved by them, likely loved by you",
                              items: report.picksForMe.map(\.media)
                                  .filter { SpoilerShield.isSafeRecommendation($0, library: model.library, policy: model.spoilerPolicy) })
                        .padding(.horizontal, -Theme.gutter)
                }
                if !report.picksForThem.isEmpty {
                    MediaRail(title: "Recommend to \(name)", subtitle: "Your favourites they haven't seen", items: report.picksForThem.map(\.media))
                        .padding(.horizontal, -Theme.gutter)
                }

                Button {
                    var fingerprint = TasteFingerprint(name: name, dna: TasteDNA.build(from: theirs.all))
                    fingerprint.name = name
                    model.addFriend(fingerprint)
                    Haptics.success()
                    model.showBanner("\(name) added to your friends.")
                } label: {
                    Label(model.friends.contains { $0.name == name } ? "Update friend" : "Add \(name) as a friend", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Club

struct ClubView: View {
    let clubId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let club = model.clubs.first(where: { $0.id == clubId }) {
                ClubContent(club: club)
            } else {
                EmptyStateView(symbol: "person.3", title: "Club not found", message: "You may have left this club.")
            }
        }
        .screenChrome("Club")
    }
}

private struct ClubContent: View {
    let club: Club
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLeave = false

    var body: some View {
        let entry = model.entry(club.mediaId)
        let progress = entry?.progress ?? 0
        let now = Date()
        let expected = club.expectedProgress(on: now)
        let sessions = club.schedule()
        let next = club.nextSession(after: now)
        let unit = club.mediaType == .anime ? "Episode" : "Chapter"
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Hosted by \(club.host)")
                    Text(club.name)
                        .font(Typo.display(28))
                        .foregroundStyle(Theme.textPrimary)
                    NavigationLink(value: Route.media(club.mediaId)) {
                        Label(club.mediaTitle, systemImage: club.mediaType == .anime ? "play.tv" : "book")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("\(club.unitsPerSession) \(unit.lowercased())\(club.unitsPerSession == 1 ? "" : "s") every \(ClubText.weekdays(club.weekdays))")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Spoiler line")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(expected == 0 ? "Not started" : "\(unit) \(expected)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.caution)
                    }
                    ProgressBar(progress: Double(expected) / Double(max(1, club.totalUnits)), tint: Theme.caution, height: 6)
                    HStack {
                        Text("You: \(progress) of \(club.totalUnits)")
                        Spacer()
                        Text(ClubText.standing(club.standing(progress: progress, on: now), unit: club.mediaType == .anime ? "ep" : "ch"))
                    }
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textSecondary)
                    if let next {
                        Text("Next: \(next.date.formatted(.dateTime.weekday(.wide).month().day())) · \(unit)\(next.units.count > 1 ? "s" : "") \(next.units.lowerBound)–\(next.units.upperBound)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentCool)
                    } else if !sessions.isEmpty {
                        Text("The club has finished. Nice work!")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.positive)
                    }
                    if entry == nil {
                        Button("Add to my library") {
                            Task {
                                if let media = try? await model.client.fetch(Queries.detail(id: club.mediaId), policy: .cacheFirst).Media {
                                    model.add(media, status: .current)
                                }
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(16)
                .surface(cornerRadius: 20)

                if !club.members.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Members")
                        Text(([club.host] + club.members.filter { $0 != club.host }).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Schedule")
                    ForEach(sessions.prefix(60)) { session in
                        let done = session.units.upperBound <= progress
                        HStack {
                            Image(systemName: done ? "checkmark.circle.fill" : (session.date < now ? "exclamationmark.circle" : "circle"))
                                .foregroundStyle(done ? Theme.positive : (session.date < now ? Theme.caution : Theme.textTertiary))
                            Text(session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(session.units.count == 1 ? "\(session.units.lowerBound)" : "\(session.units.lowerBound)–\(session.units.upperBound)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                HStack {
                    if let link = club.link {
                        ShareLink(item: link, subject: Text(club.name),
                                  message: Text("Join my \(club.mediaTitle) club on Anilite. We'll keep spoilers in sync.")) {
                            Label("Invite", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Leave", role: .destructive) { confirmLeave = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Leave \(club.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave club", role: .destructive) {
                model.leaveClub(club.id)
                dismiss()
            }
        }
    }
}
