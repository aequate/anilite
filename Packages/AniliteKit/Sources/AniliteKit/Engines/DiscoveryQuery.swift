import Foundation

public enum DiscoverySort: String, Codable, CaseIterable, Sendable {
    case popularity = "POPULARITY_DESC"
    case score = "SCORE_DESC"
    case trending = "TRENDING_DESC"
    case newest = "START_DATE_DESC"
    case relevance = "SEARCH_MATCH"

    public var label: String {
        switch self {
        case .popularity: return "Popular"
        case .score: return "Top rated"
        case .trending: return "Trending"
        case .newest: return "Newest"
        case .relevance: return "Best match"
        }
    }
}

/// Everything discovery can filter on. Server-side fields map onto AniList's Page.media
/// arguments; `maxTotalMinutes`, `moods` and `likeTitle` are applied on device.
public struct DiscoveryQuery: Codable, Hashable, Sendable {
    public var text: String?
    public var type: MediaType = .anime
    public var genresInclude: [String] = []
    public var genresExclude: [String] = []
    public var tagsInclude: [String] = []
    public var tagsExclude: [String] = []
    public var formats: [MediaFormat] = []
    public var maxEpisodes: Int?
    public var minEpisodes: Int?
    public var maxEpisodeMinutes: Int?
    public var maxTotalMinutes: Int?
    public var yearFrom: Int?
    public var yearTo: Int?
    public var minScore: Int?
    public var maxPopularity: Int?
    public var minPopularity: Int?
    public var status: MediaStatus?
    public var country: String?
    public var sort: DiscoverySort?
    public var moods: [Mood] = []
    public var likeTitle: String?

    public init(text: String? = nil, type: MediaType = .anime) {
        self.text = text
        self.type = type
    }

    public var effectiveSort: DiscoverySort {
        if let text, !text.isEmpty { return sort ?? .relevance }
        return sort ?? (moods.isEmpty ? .popularity : .score)
    }

    public var hasServerFilters: Bool {
        !(text ?? "").isEmpty || !genresInclude.isEmpty || !genresExclude.isEmpty || !tagsInclude.isEmpty || !tagsExclude.isEmpty
            || !formats.isEmpty || maxEpisodes != nil || minEpisodes != nil || yearFrom != nil || yearTo != nil || minScore != nil
            || maxPopularity != nil || status != nil || country != nil || maxEpisodeMinutes != nil
    }

    /// AniList's genre_in / tag_in require *all* values, so moods contribute one anchor
    /// filter on the server and are otherwise used to re-rank results on device.
    public func preparedForServer() -> DiscoveryQuery {
        var q = self
        if let mood = moods.first, q.genresInclude.isEmpty, q.tagsInclude.isEmpty, (q.text ?? "").isEmpty {
            if let anchor = mood.anchorGenre { q.genresInclude = [anchor] }
            if q.minPopularity == nil && q.maxPopularity == nil { q.minPopularity = 4_000 }
        }
        if let total = maxTotalMinutes, q.maxEpisodes == nil, q.formats.isEmpty {
            // Rough server-side narrowing; exact runtime is checked after fetching.
            q.maxEpisodes = max(1, total / 20)
        }
        return q
    }

    /// On-device filtering and mood re-ranking of server results.
    public func refine(_ results: [Media]) -> [Media] {
        var list = results
        if let total = maxTotalMinutes {
            list = list.filter { ($0.totalMinutes ?? Int.max) <= total }
        }
        guard !moods.isEmpty else { return list }
        let scored = list.map { media -> (Media, Double) in
            let vibe = VibeProfile.of(media)
            let moodFit = moods.map { vibe.moodScore($0) }.reduce(0, +) / Double(moods.count)
            let quality = Double(media.averageScore ?? 60) / 100
            return (media, 0.75 * moodFit + 0.25 * quality)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

public extension Mood {
    var anchorGenre: String? {
        switch self {
        case .uplifting: return nil
        case .cozy, .chill: return "Slice of Life"
        case .intense: return "Action"
        case .dark: return "Psychological"
        case .funny: return "Comedy"
        case .heartbreaking: return "Drama"
        case .mindBending: return "Mystery"
        case .romantic: return "Romance"
        case .epic: return "Adventure"
        }
    }
}

/// A human-readable piece of what the parser understood, shown as a chip.
public struct InterpretationChip: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case genre, tag, exclude, length, time, era, quality, format, mood, similar, status, type }
    public var kind: Kind
    public var label: String
    public var id: String { kind.rawValue + ":" + label }

    public var symbol: String {
        switch kind {
        case .genre: return "theatermasks.fill"
        case .tag: return "number"
        case .exclude: return "minus.circle.fill"
        case .length: return "film.stack"
        case .time: return "clock.fill"
        case .era: return "calendar"
        case .quality: return "star.fill"
        case .format: return "rectangle.on.rectangle"
        case .mood: return "sparkles"
        case .similar: return "point.3.connected.trianglepath.dotted"
        case .status: return "dot.radiowaves.left.and.right"
        case .type: return "book.fill"
        }
    }
}

public struct ParsedQuery: Hashable, Sendable {
    public var query: DiscoveryQuery
    public var chips: [InterpretationChip]
    /// Short queries might be a title ("Monster", "Space Dandy"): search titles too.
    public var alsoSearchTitle: String?
}
