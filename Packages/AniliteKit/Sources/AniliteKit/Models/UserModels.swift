import Foundation

public struct UserAvatar: Codable, Hashable, Sendable {
    public var large: String?
    public var medium: String?
    public init(large: String? = nil, medium: String? = nil) { self.large = large; self.medium = medium }
}

public struct MediaListOptions: Codable, Hashable, Sendable {
    public var scoreFormat: ScoreFormat?
}

public struct UserOptions: Codable, Hashable, Sendable {
    public var displayAdultContent: Bool?
    public var titleLanguage: String?
}

public struct AniListUser: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var avatar: UserAvatar?
    public var bannerImage: String?
    public var mediaListOptions: MediaListOptions?
    public var options: UserOptions?

    public init(id: Int, name: String, avatar: UserAvatar? = nil) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }
}

/// Raw list entry as AniList returns it.
public struct MediaListEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var mediaId: Int
    public var status: MediaListStatus?
    public var score: Double?
    public var progress: Int?
    public var progressVolumes: Int?
    public var repeatCount: Int?
    public var notes: String?
    public var isPrivate: Bool?
    public var updatedAt: Int?
    public var startedAt: FuzzyDate?
    public var completedAt: FuzzyDate?
    public var media: Media?

    enum CodingKeys: String, CodingKey {
        case id, mediaId, status, score, progress, progressVolumes, notes, updatedAt, startedAt, completedAt, media
        case repeatCount = "repeat"
        case isPrivate = "private"
    }
}

public struct MediaListGroup: Codable, Hashable, Sendable {
    public var name: String?
    public var isCustomList: Bool?
    public var status: MediaListStatus?
    public var entries: [MediaListEntry]?
}

public struct MediaListCollection: Codable, Hashable, Sendable {
    public var user: AniListUser?
    public var lists: [MediaListGroup]?
}

/// One title in the user's library, merged across AniList's status and custom lists.
public struct LibraryEntry: Codable, Hashable, Sendable, Identifiable {
    public var mediaId: Int
    public var remoteId: Int?
    public var media: Media
    public var status: MediaListStatus
    public var progress: Int
    public var progressVolumes: Int
    /// 0–100 regardless of the user's AniList score format. 0 means unscored.
    public var score: Double
    public var repeatCount: Int
    public var notes: String
    public var startedAt: FuzzyDate?
    public var completedAt: FuzzyDate?
    public var updatedAt: Date
    public var customLists: [String]

    public var id: Int { mediaId }

    public init(
        media: Media,
        status: MediaListStatus,
        progress: Int = 0,
        progressVolumes: Int = 0,
        score: Double = 0,
        repeatCount: Int = 0,
        notes: String = "",
        startedAt: FuzzyDate? = nil,
        completedAt: FuzzyDate? = nil,
        updatedAt: Date = Date(),
        remoteId: Int? = nil,
        customLists: [String] = []
    ) {
        self.mediaId = media.id
        self.media = media
        self.status = status
        self.progress = progress
        self.progressVolumes = progressVolumes
        self.score = score
        self.repeatCount = repeatCount
        self.notes = notes
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.customLists = customLists
    }

    public var type: MediaType { media.mediaType }

    /// Fraction complete, or nil when the total is unknown.
    public var completion: Double? {
        guard let total = media.totalUnits, total > 0 else { return status == .completed ? 1 : nil }
        return min(1, Double(progress) / Double(total))
    }

    public var remainingUnits: Int? {
        guard let total = media.releasedUnits ?? media.totalUnits else { return nil }
        return max(0, total - progress)
    }

    public var remainingMinutes: Int? {
        remainingUnits.map { $0 * media.minutesPerUnit }
    }

    public var isScored: Bool { score > 0 }
}

public struct Library: Codable, Hashable, Sendable {
    public var user: AniListUser?
    public var entries: [Int: LibraryEntry]
    public var lastSynced: Date?
    public var isReadOnly: Bool

    public init(user: AniListUser? = nil, entries: [Int: LibraryEntry] = [:], lastSynced: Date? = nil, isReadOnly: Bool = true) {
        self.user = user
        self.entries = entries
        self.lastSynced = lastSynced
        self.isReadOnly = isReadOnly
    }

    public static let empty = Library()

    public var all: [LibraryEntry] { Array(entries.values) }
    public var isEmpty: Bool { entries.isEmpty }

    public func entry(for mediaId: Int) -> LibraryEntry? { entries[mediaId] }

    public func entries(type: MediaType? = nil, status: MediaListStatus? = nil) -> [LibraryEntry] {
        entries.values
            .filter { (type == nil || $0.type == type) && (status == nil || $0.status == status) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var customListNames: [String] {
        Array(Set(entries.values.flatMap(\.customLists))).sorted()
    }

    /// Converts AniList's list collections into a de-duplicated library.
    public static func from(anime: MediaListCollection?, manga: MediaListCollection?, user: AniListUser?, isReadOnly: Bool, now: Date = Date()) -> Library {
        var entries: [Int: LibraryEntry] = [:]
        for collection in [anime, manga].compactMap({ $0 }) {
            for group in collection.lists ?? [] {
                let isCustom = group.isCustomList ?? false
                for raw in group.entries ?? [] {
                    guard let media = raw.media else { continue }
                    if var existing = entries[raw.mediaId] {
                        if isCustom, let name = group.name, !existing.customLists.contains(name) {
                            existing.customLists.append(name)
                        }
                        entries[raw.mediaId] = existing
                        continue
                    }
                    var entry = LibraryEntry(
                        media: media,
                        status: raw.status ?? .planning,
                        progress: raw.progress ?? 0,
                        progressVolumes: raw.progressVolumes ?? 0,
                        score: raw.score ?? 0,
                        repeatCount: raw.repeatCount ?? 0,
                        notes: raw.notes ?? "",
                        startedAt: raw.startedAt?.isEmpty == false ? raw.startedAt : nil,
                        completedAt: raw.completedAt?.isEmpty == false ? raw.completedAt : nil,
                        updatedAt: raw.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now,
                        remoteId: raw.id
                    )
                    if isCustom, let name = group.name { entry.customLists = [name] }
                    entries[raw.mediaId] = entry
                }
            }
        }
        return Library(user: user ?? anime?.user ?? manga?.user, entries: entries, lastSynced: now, isReadOnly: isReadOnly)
    }
}
