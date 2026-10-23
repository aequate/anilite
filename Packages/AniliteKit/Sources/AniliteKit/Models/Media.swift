import Foundation

public struct FuzzyDate: Codable, Hashable, Sendable, Comparable {
    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year, month: c.month, day: c.day)
    }

    public var isEmpty: Bool { year == nil }

    /// Sortable integer (yyyymmdd); unknown parts sort to the end of their range.
    public var sortKey: Int {
        guard let year else { return Int.max }
        return year * 10_000 + (month ?? 12) * 100 + (day ?? 28)
    }

    public func date(calendar: Calendar = .current) -> Date? {
        guard let year else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month ?? 1, day: day ?? 1))
    }

    public static func < (lhs: FuzzyDate, rhs: FuzzyDate) -> Bool { lhs.sortKey < rhs.sortKey }
}

public struct MediaTitle: Codable, Hashable, Sendable {
    public var romaji: String?
    public var english: String?
    public var native: String?
    public var userPreferred: String?

    public init(romaji: String? = nil, english: String? = nil, native: String? = nil, userPreferred: String? = nil) {
        self.romaji = romaji
        self.english = english
        self.native = native
        self.userPreferred = userPreferred
    }
}

public enum TitleLanguage: String, Codable, CaseIterable, Sendable {
    case english, romaji, native

    public var label: String {
        switch self {
        case .english: return "English"
        case .romaji: return "Romaji"
        case .native: return "Native"
        }
    }
}

public extension MediaTitle {
    func preferred(_ language: TitleLanguage = .english) -> String {
        let fallback = english ?? userPreferred ?? romaji ?? native ?? "Untitled"
        switch language {
        case .english: return fallback
        case .romaji: return romaji ?? fallback
        case .native: return native ?? romaji ?? fallback
        }
    }
}

public struct CoverImage: Codable, Hashable, Sendable {
    public var extraLarge: String?
    public var large: String?
    public var medium: String?
    public var color: String?

    public init(extraLarge: String? = nil, large: String? = nil, medium: String? = nil, color: String? = nil) {
        self.extraLarge = extraLarge
        self.large = large
        self.medium = medium
        self.color = color
    }

    public var best: String? { extraLarge ?? large ?? medium }
    public var thumbnail: String? { large ?? medium ?? extraLarge }
}

public struct NextAiringEpisode: Codable, Hashable, Sendable {
    public var airingAt: Int
    public var episode: Int
    public var timeUntilAiring: Int?

    public init(airingAt: Int, episode: Int, timeUntilAiring: Int? = nil) {
        self.airingAt = airingAt
        self.episode = episode
        self.timeUntilAiring = timeUntilAiring
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(airingAt)) }
}

public struct Studio: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public struct StudioConnection: Codable, Hashable, Sendable {
    public var nodes: [Studio]?
}

public struct MediaTag: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var rank: Int?
    public var category: String?
    public var isGeneralSpoiler: Bool?
    public var isMediaSpoiler: Bool?

    public init(id: Int, name: String, rank: Int? = nil, category: String? = nil, isGeneralSpoiler: Bool? = false, isMediaSpoiler: Bool? = false) {
        self.id = id
        self.name = name
        self.rank = rank
        self.category = category
        self.isGeneralSpoiler = isGeneralSpoiler
        self.isMediaSpoiler = isMediaSpoiler
    }

    public var isSpoiler: Bool { (isGeneralSpoiler ?? false) || (isMediaSpoiler ?? false) }
}

public struct Trailer: Codable, Hashable, Sendable {
    public var id: String?
    public var site: String?
    public var thumbnail: String?

    public var url: URL? {
        guard let id, let site else { return nil }
        switch site.lowercased() {
        case "youtube": return URL(string: "https://www.youtube.com/watch?v=\(id)")
        case "dailymotion": return URL(string: "https://www.dailymotion.com/video/\(id)")
        default: return nil
        }
    }
}

public struct MediaRelationEdge: Codable, Hashable, Sendable {
    public var relationType: MediaRelationType?
    public var node: Media?

    public init(relationType: MediaRelationType?, node: Media?) {
        self.relationType = relationType
        self.node = node
    }
}

public struct RelationConnection: Codable, Hashable, Sendable {
    public var edges: [MediaRelationEdge]?
    public init(edges: [MediaRelationEdge]?) { self.edges = edges }
}

public struct PersonName: Codable, Hashable, Sendable {
    public var full: String?
    public var native: String?
    public init(full: String? = nil, native: String? = nil) { self.full = full; self.native = native }
}

public struct PersonImage: Codable, Hashable, Sendable {
    public var large: String?
    public var medium: String?
    public var best: String? { large ?? medium }
}

public struct Character: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: PersonName?
    public var image: PersonImage?
    public var description: String?
    public var gender: String?
    public var age: String?
    public var favourites: Int?
    public var media: CharacterMediaConnection?

    public init(id: Int, name: PersonName? = nil) { self.id = id; self.name = name }
}

public struct VoiceActor: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: PersonName?
    public var image: PersonImage?
}

public struct CharacterEdge: Codable, Hashable, Sendable {
    public var role: CharacterRole?
    public var node: Character?
    public var voiceActors: [VoiceActor]?

    public init(role: CharacterRole?, node: Character?, voiceActors: [VoiceActor]? = nil) {
        self.role = role
        self.node = node
        self.voiceActors = voiceActors
    }
}

public struct CharacterConnection: Codable, Hashable, Sendable {
    public var edges: [CharacterEdge]?
    public init(edges: [CharacterEdge]?) { self.edges = edges }
}

public struct CharacterMediaEdge: Codable, Hashable, Sendable {
    public var characterRole: CharacterRole?
    public var node: Media?
}

public struct CharacterMediaConnection: Codable, Hashable, Sendable {
    public var edges: [CharacterMediaEdge]?
}

public struct Staff: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: PersonName?
    public var image: PersonImage?
    public var primaryOccupations: [String]?
    public var description: String?
    public var staffMedia: MediaNodeConnection?

    public init(id: Int, name: PersonName? = nil) { self.id = id; self.name = name }
}

public struct StaffEdge: Codable, Hashable, Sendable {
    public var role: String?
    public var node: Staff?
}

public struct StaffConnection: Codable, Hashable, Sendable {
    public var edges: [StaffEdge]?
}

public struct MediaNodeConnection: Codable, Hashable, Sendable {
    public var nodes: [Media]?
}

public struct Recommendation: Codable, Hashable, Sendable {
    public var rating: Int?
    public var mediaRecommendation: Media?
}

public struct RecommendationConnection: Codable, Hashable, Sendable {
    public var nodes: [Recommendation]?
}

public struct ExternalLink: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var url: String?
    public var site: String
    public var type: ExternalLinkType?
    public var language: String?
    public var color: String?
    public var icon: String?
    public var notes: String?
    public var isDisabled: Bool?

    public init(id: Int, url: String?, site: String, type: ExternalLinkType?, language: String? = nil, color: String? = nil, icon: String? = nil, notes: String? = nil, isDisabled: Bool? = false) {
        self.id = id
        self.url = url
        self.site = site
        self.type = type
        self.language = language
        self.color = color
        self.icon = icon
        self.notes = notes
        self.isDisabled = isDisabled
    }
}

public struct StreamingEpisode: Codable, Hashable, Sendable {
    public var title: String?
    public var thumbnail: String?
    public var url: String?
    public var site: String?

    /// AniList titles look like "Episode 3 - Title"; pull the number out when present.
    public var episodeNumber: Int? {
        guard let title else { return nil }
        let pattern = #"(?i)episode\s+(\d+)"#
        guard let range = title.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = title[range].filter(\.isNumber)
        return Int(digits)
    }
}

public struct Ranking: Codable, Hashable, Sendable {
    public var rank: Int
    public var type: String?
    public var context: String?
    public var allTime: Bool?
    public var year: Int?
    public var season: MediaSeason?
}

public struct ScoreDistribution: Codable, Hashable, Sendable {
    public var score: Int
    public var amount: Int
}

public struct StatusDistribution: Codable, Hashable, Sendable {
    public var status: MediaListStatus?
    public var amount: Int
}

public struct MediaStats: Codable, Hashable, Sendable {
    public var scoreDistribution: [ScoreDistribution]?
    public var statusDistribution: [StatusDistribution]?
}

public struct AiringNode: Codable, Hashable, Sendable {
    public var airingAt: Int
    public var episode: Int
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(airingAt)) }
}

public struct AiringConnection: Codable, Hashable, Sendable {
    public var nodes: [AiringNode]?
}

/// A single anime or manga. Card queries fill the top half; the detail query fills the rest.
public struct Media: Codable, Identifiable, Sendable {
    public var id: Int
    public var idMal: Int?
    public var type: MediaType?
    public var format: MediaFormat?
    public var status: MediaStatus?
    public var episodes: Int?
    public var chapters: Int?
    public var volumes: Int?
    public var duration: Int?
    public var season: MediaSeason?
    public var seasonYear: Int?
    public var averageScore: Int?
    public var meanScore: Int?
    public var popularity: Int?
    public var trending: Int?
    public var favourites: Int?
    public var genres: [String]?
    public var isAdult: Bool?
    public var countryOfOrigin: String?
    public var source: String?
    public var title: MediaTitle?
    public var coverImage: CoverImage?
    public var bannerImage: String?
    public var startDate: FuzzyDate?
    public var endDate: FuzzyDate?
    public var nextAiringEpisode: NextAiringEpisode?
    public var studios: StudioConnection?
    public var tags: [MediaTag]?

    // Detail-only fields
    public var description: String?
    public var synonyms: [String]?
    public var hashtag: String?
    public var siteUrl: String?
    public var trailer: Trailer?
    public var relations: RelationConnection?
    public var characters: CharacterConnection?
    public var staff: StaffConnection?
    public var recommendations: RecommendationConnection?
    public var externalLinks: [ExternalLink]?
    public var streamingEpisodes: [StreamingEpisode]?
    public var rankings: [Ranking]?
    public var stats: MediaStats?
    public var airingSchedule: AiringConnection?

    public init(
        id: Int,
        type: MediaType? = .anime,
        format: MediaFormat? = .tv,
        status: MediaStatus? = .finished,
        episodes: Int? = nil,
        chapters: Int? = nil,
        volumes: Int? = nil,
        duration: Int? = nil,
        seasonYear: Int? = nil,
        averageScore: Int? = nil,
        popularity: Int? = nil,
        genres: [String]? = nil,
        title: MediaTitle? = nil,
        coverImage: CoverImage? = nil,
        startDate: FuzzyDate? = nil,
        tags: [MediaTag]? = nil,
        relations: RelationConnection? = nil,
        isAdult: Bool? = false,
        countryOfOrigin: String? = "JP"
    ) {
        self.id = id
        self.type = type
        self.format = format
        self.status = status
        self.episodes = episodes
        self.chapters = chapters
        self.volumes = volumes
        self.duration = duration
        self.seasonYear = seasonYear
        self.averageScore = averageScore
        self.popularity = popularity
        self.genres = genres
        self.title = title
        self.coverImage = coverImage
        self.startDate = startDate
        self.tags = tags
        self.relations = relations
        self.isAdult = isAdult
        self.countryOfOrigin = countryOfOrigin
    }
}

extension Media: Hashable {
    // Identity is the AniList id; content changes are delivered by replacing the value.
    public static func == (lhs: Media, rhs: Media) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension Media {
    var mediaType: MediaType { type ?? (format?.isAnime == false ? .manga : .anime) }

    func displayTitle(_ language: TitleLanguage = .english) -> String {
        title?.preferred(language) ?? "Untitled"
    }

    var titleText: String { displayTitle() }

    var year: Int? { seasonYear ?? startDate?.year }

    var isManhwa: Bool { countryOfOrigin == "KR" }
    var isManhua: Bool { countryOfOrigin == "CN" || countryOfOrigin == "TW" }

    /// Units the user tracks: episodes for anime, chapters for manga.
    var totalUnits: Int? { mediaType == .anime ? episodes : chapters }

    /// Episodes released so far for an airing show; total otherwise.
    var releasedUnits: Int? {
        if mediaType == .anime, let next = nextAiringEpisode { return max(0, next.episode - 1) }
        return totalUnits
    }

    var unitName: String { mediaType == .anime ? "episode" : "chapter" }
    var unitShort: String { mediaType == .anime ? "Ep" : "Ch" }

    /// Minutes per unit, with sensible defaults when AniList has no duration.
    var minutesPerUnit: Int {
        if mediaType == .manga { return format == .novel ? 25 : 6 }
        if let duration, duration > 0 { return duration }
        switch format {
        case .movie: return 105
        case .tvShort: return 5
        default: return 24
        }
    }

    var totalMinutes: Int? {
        guard let units = totalUnits else { return nil }
        return units * minutesPerUnit
    }

    var mainStudio: Studio? { studios?.nodes?.first }

    var formatLabel: String {
        if mediaType == .manga {
            if isManhwa { return "Manhwa" }
            if isManhua { return "Manhua" }
        }
        return format?.label ?? "Other"
    }

    var relationEdges: [MediaRelationEdge] { relations?.edges ?? [] }

    func related(_ types: Set<MediaRelationType>) -> [Media] {
        relationEdges.compactMap { edge in
            guard let type = edge.relationType, types.contains(type) else { return nil }
            return edge.node
        }
    }

    /// Spoiler-free tags sorted by how strongly they describe the title.
    var safeTags: [MediaTag] {
        (tags ?? []).filter { !$0.isSpoiler }.sorted { ($0.rank ?? 0) > ($1.rank ?? 0) }
    }
}
