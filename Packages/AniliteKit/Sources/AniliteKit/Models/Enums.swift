import Foundation

/// Enums decoded from AniList that must not break when AniList adds a new case.
/// Unknown raw values decode to `fallback` instead of failing the whole response.
public protocol ResilientEnum: RawRepresentable, CaseIterable, Codable, Hashable, Sendable where RawValue == String {
    static var fallback: Self { get }
}

public extension ResilientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum MediaType: String, ResilientEnum {
    case anime = "ANIME"
    case manga = "MANGA"
    public static var fallback: MediaType { .anime }
}

public enum MediaFormat: String, ResilientEnum {
    case tv = "TV"
    case tvShort = "TV_SHORT"
    case movie = "MOVIE"
    case special = "SPECIAL"
    case ova = "OVA"
    case ona = "ONA"
    case music = "MUSIC"
    case manga = "MANGA"
    case novel = "NOVEL"
    case oneShot = "ONE_SHOT"
    case unknown = "UNKNOWN"
    public static var fallback: MediaFormat { .unknown }

    public var label: String {
        switch self {
        case .tv: return "TV"
        case .tvShort: return "TV Short"
        case .movie: return "Movie"
        case .special: return "Special"
        case .ova: return "OVA"
        case .ona: return "ONA"
        case .music: return "Music"
        case .manga: return "Manga"
        case .novel: return "Light Novel"
        case .oneShot: return "One-shot"
        case .unknown: return "Other"
        }
    }

    public var isAnime: Bool {
        switch self {
        case .tv, .tvShort, .movie, .special, .ova, .ona, .music: return true
        default: return false
        }
    }

    /// Formats that form the backbone of a franchise's story.
    public var isMainline: Bool {
        switch self {
        case .tv, .tvShort, .movie, .ona: return true
        default: return false
        }
    }
}

public enum MediaStatus: String, ResilientEnum {
    case finished = "FINISHED"
    case releasing = "RELEASING"
    case notYetReleased = "NOT_YET_RELEASED"
    case cancelled = "CANCELLED"
    case hiatus = "HIATUS"
    case unknown = "UNKNOWN"
    public static var fallback: MediaStatus { .unknown }

    public var label: String {
        switch self {
        case .finished: return "Finished"
        case .releasing: return "Releasing"
        case .notYetReleased: return "Upcoming"
        case .cancelled: return "Cancelled"
        case .hiatus: return "On Hiatus"
        case .unknown: return "Unknown"
        }
    }
}

public enum MediaSeason: String, ResilientEnum {
    case winter = "WINTER"
    case spring = "SPRING"
    case summer = "SUMMER"
    case fall = "FALL"
    public static var fallback: MediaSeason { .winter }

    public var label: String { rawValue.capitalized }

    /// The anime season a date falls in, using AniList's month boundaries.
    public static func of(_ date: Date, calendar: Calendar = .current) -> (season: MediaSeason, year: Int) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let month = comps.month ?? 1
        let year = comps.year ?? 2000
        switch month {
        case 1...3: return (.winter, year)
        case 4...6: return (.spring, year)
        case 7...9: return (.summer, year)
        default: return (.fall, year)
        }
    }

    public func next(year: Int) -> (season: MediaSeason, year: Int) {
        switch self {
        case .winter: return (.spring, year)
        case .spring: return (.summer, year)
        case .summer: return (.fall, year)
        case .fall: return (.winter, year + 1)
        }
    }
}

public enum MediaListStatus: String, ResilientEnum {
    case current = "CURRENT"
    case planning = "PLANNING"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case paused = "PAUSED"
    case repeating = "REPEATING"
    public static var fallback: MediaListStatus { .planning }

    public func label(for type: MediaType) -> String {
        switch self {
        case .current: return type == .anime ? "Watching" : "Reading"
        case .planning: return "Planning"
        case .completed: return "Completed"
        case .dropped: return "Dropped"
        case .paused: return "Paused"
        case .repeating: return type == .anime ? "Rewatching" : "Rereading"
        }
    }

    public var isActive: Bool { self == .current || self == .repeating }
}

public enum MediaRelationType: String, ResilientEnum {
    case adaptation = "ADAPTATION"
    case prequel = "PREQUEL"
    case sequel = "SEQUEL"
    case parent = "PARENT"
    case sideStory = "SIDE_STORY"
    case character = "CHARACTER"
    case summary = "SUMMARY"
    case alternative = "ALTERNATIVE"
    case spinOff = "SPIN_OFF"
    case other = "OTHER"
    case source = "SOURCE"
    case compilation = "COMPILATION"
    case contains = "CONTAINS"
    public static var fallback: MediaRelationType { .other }

    public var label: String {
        switch self {
        case .adaptation: return "Adaptation"
        case .prequel: return "Prequel"
        case .sequel: return "Sequel"
        case .parent: return "Parent Story"
        case .sideStory: return "Side Story"
        case .character: return "Shared Characters"
        case .summary: return "Recap"
        case .alternative: return "Alternative Version"
        case .spinOff: return "Spin-off"
        case .other: return "Related"
        case .source: return "Source"
        case .compilation: return "Compilation"
        case .contains: return "Contains"
        }
    }
}

public enum CharacterRole: String, ResilientEnum {
    case main = "MAIN"
    case supporting = "SUPPORTING"
    case background = "BACKGROUND"
    public static var fallback: CharacterRole { .background }
}

public enum ExternalLinkType: String, ResilientEnum {
    case info = "INFO"
    case streaming = "STREAMING"
    case social = "SOCIAL"
    public static var fallback: ExternalLinkType { .info }
}

public enum ScoreFormat: String, ResilientEnum {
    case point100 = "POINT_100"
    case point10Decimal = "POINT_10_DECIMAL"
    case point10 = "POINT_10"
    case point5 = "POINT_5"
    case point3 = "POINT_3"
    public static var fallback: ScoreFormat { .point10 }
}
