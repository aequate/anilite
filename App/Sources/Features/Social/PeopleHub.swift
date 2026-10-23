import SwiftUI
import AniliteKit

// MARK: - Building blocks

/// Round avatar with the person's initial underneath while the image loads.
struct PersonAvatar: View {
    var url: String?
    var name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Theme.ink3)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textSecondary)
            if url != nil {
                RemoteImage(url, points: size, placeholder: .clear)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Follow / Following toggle. It hides itself when following isn't possible.
struct FollowButton: View {
    let user: AniListUser
    var compact = false
    @Environment(AppModel.self) private var model
    @State private var busy = false

    var body: some View {
        let following = model.isFollowing(user.name)
        Button {
            guard !busy else { return }
            busy = true
            Haptics.tap()
            Task {
                await model.toggleFollow(user)
                busy = false
            }
        } label: {
            Text(following ? "Following" : "Follow")
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .foregroundStyle(following ? Theme.textSecondary : Theme.ink0)
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 6 : 10)
                .frame(minWidth: compact ? 84 : nil)
                .background {
                    Capsule().fill(following ? Theme.ink2 : Theme.accent)
                }
                .overlay {
                    if following { Capsule().strokeBorder(Theme.ink3, lineWidth: 1) }
                }
                .opacity(busy ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.quick, value: following)
        .accessibilityLabel(following ? "Unfollow \(user.name)" : "Follow \(user.name)")
    }
}

/// A person in a list: avatar, name, an optional line underneath, and whatever goes on the right.
struct PersonRow<Trailing: View>: View {
    let user: AniListUser
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.person(user.name)) {
                HStack(spacing: 12) {
                    PersonAvatar(url: user.avatar?.medium ?? user.avatar?.large, name: user.name, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let detail {
                            Text(detail)
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(.vertical, 4)
    }
}

extension PersonRow where Trailing == EmptyView {
    init(user: AniListUser, detail: String? = nil) {
        self.user = user
        self.detail = detail
        self.trailing = { EmptyView() }
    }
}

/// One list update: "Ann watched episode 4 of Frieren", with the cover on the right.
struct FeedRow: View {
    let activity: ListActivity
    var showsUser = true
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsUser, let user = activity.user {
                NavigationLink(value: Route.person(user.name)) {
                    PersonAvatar(url: user.avatar?.medium, name: user.name, size: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(user.name)
            }
            if let media = activity.media {
                NavigationLink(value: Route.media(media.id)) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            sentence(media: media)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(activity.date, format: .relative(presentation: .named))
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                        PosterImage(media: media, width: 36, cornerRadius: Theme.cornerCover)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func sentence(media: Media) -> Text {
        let status = activity.status ?? "updated"
        let title = Text(model.title(media)).foregroundColor(Theme.textPrimary).fontWeight(.semibold)
        var lead = Text("")
        if showsUser, let name = activity.user?.name {
            lead = Text(name).foregroundColor(Theme.textPrimary).fontWeight(.semibold) + Text(" ")
        }
        let action = showsUser ? status : status.prefix(1).uppercased() + status.dropFirst()
        if let progress = activity.progress, !progress.isEmpty {
            return lead + Text("\(action) \(progress) of ") + title
        }
        return lead + Text("\(action) ") + title
    }
}

// MARK: - Profile

struct PersonProfileView: View {
    let name: String
    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncContent(id: "person-\(name)") { [name] () async throws -> UserProfile in
            try await model.client.fetch(Queries.userProfile(name: name), policy: .networkFirst).User
        } content: { profile in
            PersonProfileContent(profile: profile)
        }
        .screenChrome(name)
    }
}

private struct PersonProfileContent: View {
    let profile: UserProfile
    @Environment(AppModel.self) private var model
    @State private var report: CompatibilityReport?
    @State private var reportFailed = false
    @State private var activity: [ListActivity] = []
    @State private var aboutExpanded = false
    @State private var addingFriend = false

    private var isMe: Bool {
        if let id = model.viewerId { return id == profile.id }
        return model.account.displayName?.caseInsensitiveCompare(profile.name) == .orderedSame
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                stats
                if !isMe { actions }
                if !isMe { compatibility }
                if !profile.aboutText.isEmpty { about }
                favourites
                if !activity.isEmpty { recent }
                connections
            }
            .padding(.bottom, Dock.height + 24)
        }
        .scrollIndicators(.hidden)
        .background {
            // Their banner, or else their top favourite: the page looks like the person.
            let favourite = profile.favouriteTitles.first
            ScreenBackground(artwork: profile.bannerImage ?? favourite?.backdropArtwork ?? profile.avatar?.large,
                             artworkHint: favourite?.coverImage?.color)
        }
        .toolbar {
            if let link = profileLink {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: link, subject: Text(profile.name),
                              message: Text("\(profile.name) on Anilite")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share profile")
                }
            }
        }
        .task(id: profile.id) { await load() }
    }

    private var profileLink: URL? {
        var comps = URLComponents()
        comps.scheme = ShareCodec.scheme
        comps.host = "user"
        comps.path = "/" + profile.name
        return comps.url
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let banner = profile.bannerImage {
                        RemoteImage(banner, points: 420, placeholder: Theme.ink1)
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.55)
                    } else {
                        Theme.ink1
                    }
                }
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipped()
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .center, endPoint: .bottom)
                }
                .accessibilityHidden(true)

                PersonAvatar(url: profile.avatar?.large ?? profile.avatar?.medium, name: profile.name, size: 84)
                    .overlay(Circle().strokeBorder(Theme.ink0, lineWidth: 3))
                    .padding(.leading, Theme.gutter)
                    .offset(y: 34)
            }
            .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(Typo.display(30))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    if isMe {
                        Tag(text: "You")
                    } else if profile.isMutual {
                        Tag(text: "You follow each other", tint: Theme.accentCool)
                    } else if profile.isFollower == true {
                        Tag(text: "Follows you", tint: Theme.accentCool)
                    }
                    if model.isFriend(profile.name) {
                        Tag(text: "In your friends")
                    }
                    if let joined = profile.createdAt, joined > 0 {
                        Text("On AniList since \(Date(timeIntervalSince1970: TimeInterval(joined)).formatted(.dateTime.year()))")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: Stats

    private var stats: some View {
        let anime = profile.statistics?.anime
        let manga = profile.statistics?.manga
        let titles = (anime?.count ?? 0) + (manga?.count ?? 0)
        let mean = [anime?.meanScore, manga?.meanScore].compactMap { $0 }.filter { $0 > 0 }
        return HStack(spacing: 0) {
            ProfileStat(value: "\(titles)", label: "titles")
            Divider().frame(height: 34).overlay(Theme.ink3)
            ProfileStat(value: profile.daysWatched.formatted(.number.precision(.fractionLength(profile.daysWatched < 10 ? 1 : 0))), label: "days watched")
            Divider().frame(height: 34).overlay(Theme.ink3)
            ProfileStat(value: mean.isEmpty ? "–" : (mean.reduce(0, +) / Double(mean.count)).formatted(.number.precision(.fractionLength(0))), label: "mean score")
            Divider().frame(height: 34).overlay(Theme.ink3)
            ProfileStat(value: "\(manga?.chaptersRead ?? 0)", label: "chapters")
        }
        .padding(.vertical, 14)
        .surface()
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if model.canFollow {
                    FollowButton(user: profile.user)
                }
                Button {
                    addingFriend = true
                    Task {
                        await model.addFriend(named: profile.name)
                        addingFriend = false
                    }
                } label: {
                    Label(model.isFriend(profile.name) ? "Update Taste DNA" : "Add as friend", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(addingFriend)
            }
            if !model.canFollow {
                Text("Connect your AniList account in Settings to follow people. Adding a friend works without it.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Compatibility

    @ViewBuilder
    private var compatibility: some View {
        if let report {
            NavigationLink(value: Route.compareUser(profile.name)) {
                HStack(spacing: 14) {
                    CompatibilityBadge(score: report.score)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.verdict)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(compatibilityDetail(report))
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(14)
                .surface()
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Theme.gutter)
            .transition(.opacity)
        } else if !reportFailed {
            Skeleton(cornerRadius: Theme.corner)
                .frame(height: 72)
                .padding(.horizontal, Theme.gutter)
        }
    }

    private func compatibilityDetail(_ report: CompatibilityReport) -> String {
        var parts = ["\(report.sharedCount) titles in common"]
        if let genre = report.sharedGenres.first { parts.append("both into \(genre.lowercased())") }
        return parts.joined(separator: " · ")
    }

    // MARK: About

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "About")
            Text(profile.aboutText)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(aboutExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
            if profile.aboutText.count > 260 {
                Button(aboutExpanded ? "Less" : "More") {
                    withAnimation(Motion.standard) { aboutExpanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Favourites

    @ViewBuilder
    private var favourites: some View {
        let anime = (profile.favourites?.anime?.nodes ?? []).filter { !($0.isAdult ?? false) }
        let manga = (profile.favourites?.manga?.nodes ?? []).filter { !($0.isAdult ?? false) }
        let characters = profile.favourites?.characters?.nodes ?? []
        if !anime.isEmpty {
            MediaRail(title: "Favourite anime", items: anime)
        }
        if !manga.isEmpty {
            MediaRail(title: "Favourite manga", items: manga)
        }
        if !characters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Favourite characters")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(characters) { character in
                            NavigationLink(value: Route.character(character.id)) {
                                VStack(spacing: 6) {
                                    PersonAvatar(url: character.image?.best, name: character.name?.full ?? "?", size: 64)
                                    Text(character.name?.full ?? "")
                                        .font(Typo.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Recent activity

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Lately")
                .padding(.bottom, 4)
            ForEach(activity.prefix(8)) { item in
                FeedRow(activity: item, showsUser: false)
                if item.id != activity.prefix(8).last?.id {
                    Divider().overlay(Theme.ink2)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Following / followers

    private var connections: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.follows(userId: profile.id, name: profile.name, followers: false)) {
                ConnectionRow(title: "Following", symbol: "person.2")
            }
            Divider().overlay(Theme.ink2).padding(.leading, 48)
            NavigationLink(value: Route.follows(userId: profile.id, name: profile.name, followers: true)) {
                ConnectionRow(title: "Followers", symbol: "person.3")
            }
        }
        .buttonStyle(.plain)
        .surface()
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Loading

    private func load() async {
        async let lists = theirLibrary()
        async let latest = recentActivity()
        let theirs = await lists
        let items = await latest
        withAnimation(Motion.standard) {
            if let theirs {
                report = Compatibility.compare(mine: model.library, theirs: theirs, theirName: profile.name)
            } else {
                reportFailed = true
            }
            activity = items
        }
    }

    private func theirLibrary() async -> Library? {
        guard !isMe else { return nil }
        guard let response = try? await model.client.fetch(Queries.lists(userName: profile.name), policy: .cacheFirst) else { return nil }
        return Library.from(anime: response.anime, manga: response.manga,
                            user: response.anime?.user ?? response.manga?.user, isReadOnly: true)
    }

    private func recentActivity() async -> [ListActivity] {
        let since = Date().addingTimeInterval(-60 * 86_400)
        guard let page = try? await model.client.fetch(Queries.activities(userId: profile.id, since: since, page: 1), policy: .cacheFirst).Page else { return [] }
        return page.activities.filter { !($0.media?.isAdult ?? false) }
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Typo.metric)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionRow: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// Small flat label, e.g. "Follows you".
struct Tag: View {
    let text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(Typo.micro)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Following feed

struct FollowingFeedView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [ListActivity] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if !model.canFollow {
                EmptyStateView(symbol: "person.2", title: "Nobody to follow yet",
                               message: "Connect your AniList account in Settings to follow people and see what they're watching.")
            } else if items.isEmpty && loading {
                VStack(spacing: 14) {
                    ForEach(0..<6, id: \.self) { _ in Skeleton().frame(height: 58) }
                }
                .padding(Theme.gutter)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if items.isEmpty, let error {
                ErrorBanner(message: error) { Task { await load(reset: true) } }
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if items.isEmpty {
                EmptyStateView(symbol: "person.2", title: "Quiet for now",
                               message: "When people you follow update their lists, it shows up here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            FeedRow(activity: item)
                                .onAppear {
                                    if item.id == items.last?.id { Task { await load(reset: false) } }
                                }
                            Divider().overlay(Theme.ink2)
                        }
                        if loading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, Dock.height + 24)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load(reset: true) }
            }
        }
        .screenChrome("From people you follow")
        .task { if items.isEmpty { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        guard model.canFollow, !loading, reset || hasMore else { return }
        loading = true
        defer { loading = false }
        let next = reset ? 1 : page + 1
        do {
            let response = try await model.client.fetch(Queries.followingFeed(page: next), policy: reset ? .networkFirst : .cacheFirst)
            let fresh = response.Page.activities.filter { $0.media != nil && !($0.media?.isAdult ?? false) }
            if reset {
                items = fresh
            } else {
                let seen = Set(items.map(\.id))
                items += fresh.filter { !seen.contains($0.id) }
            }
            page = next
            hasMore = response.Page.pageInfo?.hasNextPage == true
            error = nil
        } catch {
            self.error = AppModel.message(for: error)
        }
    }
}

// MARK: - Following / followers list

struct FollowListView: View {
    let userId: Int
    let name: String
    let followers: Bool
    @Environment(AppModel.self) private var model
    @State private var people: [AniListUser] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if people.isEmpty && loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if people.isEmpty, let error {
                ErrorBanner(message: error) { Task { await load() } }
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if people.isEmpty {
                EmptyStateView(symbol: "person.2", title: followers ? "No followers yet" : "Not following anyone",
                               message: followers ? "\(name) doesn't have any followers on AniList yet." : "\(name) isn't following anyone on AniList yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { user in
                            PersonRow(user: user, detail: model.isFriend(user.name) ? "In your friends" : nil) {
                                if model.canFollow && user.id != model.viewerId {
                                    FollowButton(user: user, compact: true)
                                }
                            }
                            .onAppear {
                                if user.id == people.last?.id { Task { await load() } }
                            }
                            Divider().overlay(Theme.ink2).padding(.leading, 56)
                        }
                        if loading { ProgressView().padding() }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, Dock.height + 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .screenChrome(followers ? "\(name)'s followers" : "\(name) follows")
        .task { if people.isEmpty { await load() } }
    }

    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        defer { loading = false }
        let next = page + 1
        do {
            let op = followers ? Queries.followers(userId: userId, page: next) : Queries.following(userId: userId, page: next)
            let response = try await model.client.fetch(op, policy: .cacheFirst)
            let seen = Set(people.map(\.id))
            people += response.Page.people.filter { !seen.contains($0.id) }
            page = next
            hasMore = response.Page.pageInfo?.hasNextPage == true
            error = nil
        } catch {
            self.error = AppModel.message(for: error)
        }
    }
}
