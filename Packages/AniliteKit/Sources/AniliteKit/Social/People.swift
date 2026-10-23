import Foundation

// MARK: - Profiles

public struct UserStatistics: Codable, Hashable, Sendable {
    public struct Anime: Codable, Hashable, Sendable {
        public var count: Int?
        public var episodesWatched: Int?
        public var minutesWatched: Int?
        public var meanScore: Double?
    }

    public struct Manga: Codable, Hashable, Sendable {
        public var count: Int?
        public var chaptersRead: Int?
        public var volumesRead: Int?
        public var meanScore: Double?
    }

    public var anime: Anime?
    public var manga: Manga?
}

public struct CharacterNodeConnection: Codable, Hashable, Sendable {
    public var nodes: [Character]?
}

public struct UserFavourites: Codable, Hashable, Sendable {
    public var anime: MediaNodeConnection?
    public var manga: MediaNodeConnection?
    public var characters: CharacterNodeConnection?
}

/// A public AniList profile, as seen by the viewer.
public struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var about: String?
    public var avatar: UserAvatar?
    public var bannerImage: String?
    /// nil unless the viewer is signed in.
    public var isFollowing: Bool?
    public var isFollower: Bool?
    public var createdAt: Int?
    public var statistics: UserStatistics?
    public var favourites: UserFavourites?

    public var user: AniListUser { AniListUser(id: id, name: name, avatar: avatar) }

    public var isMutual: Bool { isFollowing == true && isFollower == true }

    public var favouriteTitles: [Media] {
        ((favourites?.anime?.nodes ?? []) + (favourites?.manga?.nodes ?? [])).filter { !($0.isAdult ?? false) }
    }

    public var daysWatched: Double {
        Double(statistics?.anime?.minutesWatched ?? 0) / 1440
    }

    /// The bio as plain text: no markup, no images, no marked spoilers.
    public var aboutText: String {
        guard let about, !about.isEmpty else { return "" }
        return Self.plainText(about)
    }

    static func plainText(_ raw: String) -> String {
        var s = raw
        let patterns: [(String, String)] = [
            ("~!.*?!~", ""),                          // spoilers
            ("img\\d*%?\\(.*?\\)", ""),               // AniList image embeds
            ("(?:webm|youtube)\\(.*?\\)", ""),         // video embeds
            ("<[^>]+>", ""),                          // HTML tags
            ("\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),     // markdown links keep their text
            ("(\\*\\*|__|~~~|~~)", ""),               // emphasis
            ("^#+\\s*", ""),                          // headings
            ("[ \\t]+", " "),
            ("\\n{3,}", "\n\n")
        ]
        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .anchorsMatchLines]) else { continue }
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct UserProfileResponse: Codable, Sendable {
    public var User: UserProfile
}

public struct FollowPage: Codable, Sendable {
    public var pageInfo: PageInfo?
    public var following: [AniListUser]?
    public var followers: [AniListUser]?
    public var people: [AniListUser] { following ?? followers ?? [] }
}

public struct FollowListResponse: Codable, Sendable {
    public var Page: FollowPage
}

public struct FollowState: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isFollowing: Bool?
}

public struct ToggleFollowResponse: Codable, Sendable {
    public var ToggleFollow: FollowState
}

// MARK: - Discovery signals

public struct ReviewSignal: Codable, Hashable, Sendable {
    public var id: Int
    public var score: Int?
    public var mediaId: Int
    public var user: AniListUser?
}

public struct ActivitySignal: Codable, Hashable, Sendable {
    public struct MediaRef: Codable, Hashable, Sendable { public var id: Int }
    public var id: Int?
    public var status: String?
    public var createdAt: Int?
    public var media: MediaRef?
    public var user: AniListUser?
}

/// One aliased page of the discovery query: reviews or recent list activity on one title.
public struct PeopleSignalPage: Codable, Hashable, Sendable {
    public var reviews: [ReviewSignal]?
    public var activities: [ActivitySignal]?
}

/// Someone whose lists overlap with yours, and why.
public struct PersonSuggestion: Hashable, Sendable, Identifiable {
    public enum Signal: Hashable, Sendable {
        case reviewed(score: Int)
        case completed
        case watching
        case planning
    }

    public struct Reason: Hashable, Sendable {
        public var mediaId: Int
        public var title: String
        public var signal: Signal
    }

    public var user: AniListUser
    public var reasons: [Reason]
    public var score: Double
    public var id: Int { user.id }

    /// "Reviewed Mushishi (92), finished Frieren" style summary.
    public var summary: String {
        reasons.prefix(2).map { reason in
            switch reason.signal {
            case .reviewed(let score): return "reviewed \(reason.title) (\(score))"
            case .completed: return "finished \(reason.title)"
            case .watching: return "is on \(reason.title)"
            case .planning: return "plans to start \(reason.title)"
            }
        }.joined(separator: ", ")
    }
}

/// Finds people with similar taste by looking at who reviewed, finished or is currently
/// on the titles you rated highest. Everything comes from public AniList data.
public enum PeopleFinder {
    /// The titles that say the most about you: highest scored first, niche before popular.
    public static func seeds(from library: Library, limit: Int = 4) -> [Media] {
        let candidates = library.all.filter { [.completed, .current, .repeating].contains($0.status) && !($0.media.isAdult ?? false) }
        let scored = candidates.filter { $0.score >= 70 }
        let pool = scored.isEmpty ? candidates.filter { $0.status != .planning } : scored
        return pool.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let pa = a.media.popularity ?? 0, pb = b.media.popularity ?? 0
            if pa != pb { return pa < pb }
            return a.updatedAt > b.updatedAt
        }
        .prefix(limit)
        .map(\.media)
    }

    /// How much a title tells us. Sharing a niche favourite means more than sharing a hit.
    static func distinctiveness(_ media: Media) -> Double {
        let popularity = Double(max(1, media.popularity ?? 50_000))
        return 1 + max(0, 5.5 - log10(popularity)) * 0.18
    }

    static func weight(for signal: PersonSuggestion.Signal) -> Double {
        switch signal {
        case .reviewed(let score):
            if score >= 85 { return 1.6 }
            if score >= 70 { return 1.2 }
            if score >= 50 { return 0.3 }
            return 0
        case .completed: return 0.9
        case .watching: return 0.7
        case .planning: return 0.25
        }
    }

    static func signal(forStatus status: String?) -> PersonSuggestion.Signal? {
        guard let status = status?.lowercased() else { return nil }
        if status.hasPrefix("completed") { return .completed }
        if status.hasPrefix("watched") || status.hasPrefix("read") || status.hasPrefix("rewatched") || status.hasPrefix("reread") { return .watching }
        if status.hasPrefix("plans") { return .planning }
        return nil
    }

    /// Ranks everyone in the signal pages. `excluding` holds lower-cased names to skip
    /// (you, people you follow, friends you already added).
    public static func rank(signals: [String: PeopleSignalPage], seeds: [Media], excluding: Set<String>, limit: Int = 12) -> [PersonSuggestion] {
        let seedById = Dictionary(seeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var users: [Int: AniListUser] = [:]
        // Best signal per person per title.
        var best: [Int: [Int: PersonSuggestion.Signal]] = [:]

        func record(_ user: AniListUser?, mediaId: Int, signal: PersonSuggestion.Signal) {
            guard let user, seedById[mediaId] != nil, !excluding.contains(user.name.lowercased()) else { return }
            users[user.id] = user
            let current = best[user.id]?[mediaId]
            if current == nil || weight(for: signal) > weight(for: current!) {
                best[user.id, default: [:]][mediaId] = signal
            }
        }

        for key in signals.keys.sorted() {
            guard let page = signals[key] else { continue }
            for review in page.reviews ?? [] {
                record(review.user, mediaId: review.mediaId, signal: .reviewed(score: review.score ?? 0))
            }
            for activity in page.activities ?? [] {
                guard let mediaId = activity.media?.id, let signal = signal(forStatus: activity.status) else { continue }
                record(activity.user, mediaId: mediaId, signal: signal)
            }
        }

        var suggestions: [PersonSuggestion] = []
        for (userId, perMedia) in best {
            guard let user = users[userId] else { continue }
            var total = 0.0
            var reasons: [(PersonSuggestion.Reason, Double)] = []
            for (mediaId, signal) in perMedia {
                guard let media = seedById[mediaId] else { continue }
                let w = weight(for: signal) * distinctiveness(media)
                guard w > 0 else { continue }
                total += w
                reasons.append((PersonSuggestion.Reason(mediaId: mediaId, title: media.titleText, signal: signal), w))
            }
            guard !reasons.isEmpty else { continue }
            // Overlap across several of your titles matters more than one strong signal.
            total *= 1 + 0.6 * Double(reasons.count - 1)
            let ordered = reasons.sorted { $0.1 == $1.1 ? $0.0.mediaId < $1.0.mediaId : $0.1 > $1.1 }.map(\.0)
            suggestions.append(PersonSuggestion(user: user, reasons: ordered, score: (total * 100).rounded() / 100))
        }
        return suggestions
            .sorted { $0.score == $1.score ? $0.user.name.lowercased() < $1.user.name.lowercased() : $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Queries

extension Queries {
    static let userFields = "id name avatar { large medium }"

    public static func userProfile(name: String) -> GraphQLOperation<UserProfileResponse> {
        var v = Variables()
        v.set("name", name)
        let query = """
        query Profile($name: String) {
          User(name: $name) {
            id name about avatar { large medium } bannerImage isFollowing isFollower createdAt
            statistics {
              anime { count episodesWatched minutesWatched meanScore }
              manga { count chaptersRead volumesRead meanScore }
            }
            favourites {
              anime(perPage: 12) { nodes { ...lite } }
              manga(perPage: 12) { nodes { ...lite } }
              characters(perPage: 12) { nodes { id name { full } image { large medium } } }
            }
          }
        }
        """ + Fragments.lite
        var op = GraphQLOperation<UserProfileResponse>(name: "profile", query: query, variables: v, ttl: 60 * 10)
        op.attachesToken = true
        return op
    }

    public static func following(userId: Int, page: Int = 1) -> GraphQLOperation<FollowListResponse> {
        follows("following", userId: userId, page: page)
    }

    public static func followers(userId: Int, page: Int = 1) -> GraphQLOperation<FollowListResponse> {
        follows("followers", userId: userId, page: page)
    }

    private static func follows(_ field: String, userId: Int, page: Int) -> GraphQLOperation<FollowListResponse> {
        var v = Variables()
        v.set("uid", userId)
        v.set("page", page)
        let query = """
        query Follows($uid: Int!, $page: Int) {
          Page(page: $page, perPage: 50) {
            pageInfo { hasNextPage }
            \(field)(userId: $uid, sort: USERNAME) { \(userFields) }
          }
        }
        """
        return GraphQLOperation(name: field, query: query, variables: v, ttl: 60 * 5)
    }

    public static func toggleFollow(userId: Int) -> GraphQLOperation<ToggleFollowResponse> {
        var v = Variables()
        v.set("uid", userId)
        let query = "mutation Follow($uid: Int) { ToggleFollow(userId: $uid) { id name isFollowing } }"
        return GraphQLOperation(name: "follow", query: query, variables: v, ttl: 0, isMutation: true, requiresAuth: true)
    }

    /// Recent list updates from everyone the viewer follows.
    public static func followingFeed(page: Int = 1) -> GraphQLOperation<ActivityResponse> {
        var v = Variables()
        v.set("page", page)
        let query = """
        query Feed($page: Int) {
          Page(page: $page, perPage: 30) {
            pageInfo { hasNextPage }
            activities(isFollowing: true, type: MEDIA_LIST, sort: ID_DESC) {
              ... on ListActivity { id status progress createdAt user { \(userFields) } media { ...lite } }
            }
          }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "feed", query: query, variables: v, ttl: 60 * 3, requiresAuth: true)
    }

    /// Reviews and recent list activity on a few titles, in one request.
    public static func peopleSignals(mediaIds: [Int]) -> GraphQLOperation<[String: PeopleSignalPage]> {
        var v = Variables()
        let ids = Array(mediaIds.prefix(4))
        var declarations: [String] = []
        var fields: [String] = []
        for (index, id) in ids.enumerated() {
            v.set("m\(index)", id)
            declarations.append("$m\(index): Int")
            fields.append("""
              r\(index): Page(perPage: 10) { reviews(mediaId: $m\(index), sort: [RATING_DESC]) { id score mediaId user { \(userFields) } } }
              a\(index): Page(perPage: 15) { activities(mediaId: $m\(index), type: MEDIA_LIST, sort: ID_DESC) { ... on ListActivity { id status createdAt media { id } user { \(userFields) } } } }
            """)
        }
        let query = "query People(\(declarations.joined(separator: ", "))) {\n" + fields.joined(separator: "\n") + "\n}"
        return GraphQLOperation(name: "people", query: query, variables: v, ttl: 60 * 60 * 6)
    }
}
