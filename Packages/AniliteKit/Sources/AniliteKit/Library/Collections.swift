import Foundation

/// A private, on-device diary entry tied to a moment in a title.
public struct JournalEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var mediaId: Int
    public var mediaTitle: String
    public var coverURL: String?
    public var unit: Int?
    public var text: String
    public var feeling: Feeling?
    public var createdAt: Date

    public enum Feeling: String, Codable, CaseIterable, Sendable {
        case loved, moved, hyped, laughing, shocked, cozy, conflicted, bored

        public var emoji: String {
            switch self {
            case .loved: return "😍"
            case .moved: return "🥲"
            case .hyped: return "🔥"
            case .laughing: return "😂"
            case .shocked: return "😱"
            case .cozy: return "☕️"
            case .conflicted: return "🤔"
            case .bored: return "😴"
            }
        }

        public var label: String { rawValue.capitalized }
    }

    public init(id: UUID = UUID(), mediaId: Int, mediaTitle: String, coverURL: String? = nil, unit: Int? = nil, text: String, feeling: Feeling? = nil, createdAt: Date = Date()) {
        self.id = id
        self.mediaId = mediaId
        self.mediaTitle = mediaTitle
        self.coverURL = coverURL
        self.unit = unit
        self.text = text
        self.feeling = feeling
        self.createdAt = createdAt
    }
}

/// A user shelf. Manual shelves hold ids; smart shelves are rules evaluated live.
public struct Shelf: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var mediaIds: [Int]
    public var rule: SmartRule?

    public init(id: UUID = UUID(), name: String, symbol: String = "books.vertical.fill", mediaIds: [Int] = [], rule: SmartRule? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.mediaIds = mediaIds
        self.rule = rule
    }

    public var isSmart: Bool { rule != nil }

    public func entries(in library: Library) -> [LibraryEntry] {
        if let rule { return rule.apply(to: library) }
        return mediaIds.compactMap { library.entry(for: $0) }
    }
}

public struct SmartRule: Codable, Hashable, Sendable {
    public var type: MediaType?
    public var statuses: [MediaListStatus]
    public var genres: [String]
    public var minScore: Double?
    public var maxRemainingMinutes: Int?
    public var untouchedDays: Int?
    public var customList: String?

    public init(type: MediaType? = nil, statuses: [MediaListStatus] = [], genres: [String] = [], minScore: Double? = nil,
                maxRemainingMinutes: Int? = nil, untouchedDays: Int? = nil, customList: String? = nil) {
        self.type = type
        self.statuses = statuses
        self.genres = genres
        self.minScore = minScore
        self.maxRemainingMinutes = maxRemainingMinutes
        self.untouchedDays = untouchedDays
        self.customList = customList
    }

    public func matches(_ e: LibraryEntry, now: Date = Date()) -> Bool {
        if let type, e.type != type { return false }
        if !statuses.isEmpty && !statuses.contains(e.status) { return false }
        if !genres.isEmpty && Set(genres).isDisjoint(with: e.media.genres ?? []) { return false }
        if let minScore, e.score < minScore { return false }
        if let maxRemainingMinutes, (e.remainingMinutes ?? Int.max) > maxRemainingMinutes { return false }
        if let untouchedDays, now.timeIntervalSince(e.updatedAt) < Double(untouchedDays) * 86_400 { return false }
        if let customList, !e.customLists.contains(customList) { return false }
        return true
    }

    public func apply(to library: Library, now: Date = Date()) -> [LibraryEntry] {
        library.all.filter { matches($0, now: now) }.sorted { $0.updatedAt > $1.updatedAt }
    }
}

public extension Shelf {
    /// Useful shelves every library gets for free.
    static let builtIns: [Shelf] = [
        Shelf(name: "Almost Done", symbol: "flag.checkered", rule: SmartRule(statuses: [.current, .paused], maxRemainingMinutes: 120)),
        Shelf(name: "Gathering Dust", symbol: "hourglass.bottomhalf.filled", rule: SmartRule(statuses: [.current, .paused], untouchedDays: 45)),
        Shelf(name: "Hall of Fame", symbol: "crown.fill", rule: SmartRule(statuses: [.completed, .repeating], minScore: 90)),
        Shelf(name: "Weeknight Picks", symbol: "moon.stars.fill", rule: SmartRule(type: .anime, statuses: [.planning], maxRemainingMinutes: 300))
    ]
}

// MARK: - Achievements

public struct Achievement: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var progress: Double
    public var isUnlocked: Bool { progress >= 1 }
}

public enum Achievements {
    public static func evaluate(library: Library, journal: [JournalEntry] = []) -> [Achievement] {
        let completed = library.all.filter { $0.status == .completed || $0.repeatCount > 0 }
        let anime = completed.filter { $0.type == .anime }
        let manga = completed.filter { $0.type == .manga }
        let minutes = library.all.reduce(0) { total, e in
            let units = e.status == .completed ? (e.media.totalUnits ?? e.progress) : e.progress
            return total + units * e.media.minutesPerUnit * (1 + e.repeatCount)
        }
        let decades = Set(completed.compactMap { $0.media.year.map { $0 / 10 } })
        let genres = Set(completed.flatMap { $0.media.genres ?? [] })
        let gems = completed.filter { Recommender.isHiddenGem($0.media) }
        let longest = completed.map { $0.media.totalUnits ?? 0 }.max() ?? 0
        let films = completed.filter { $0.media.format == .movie }
        let countries = Set(completed.compactMap { $0.media.countryOfOrigin })
        let revived = library.all.filter { e in
            guard e.status == .completed, let s = e.startedAt, let c = e.completedAt, s.year != nil, c.year != nil else { return false }
            return c.sortKey - s.sortKey > 10_000
        }

        func ratio(_ value: Int, _ goal: Int) -> Double { min(1, Double(value) / Double(goal)) }

        return [
            Achievement(id: "first", title: "First Steps", detail: "Complete your first title", symbol: "figure.walk", progress: ratio(completed.count, 1)),
            Achievement(id: "anime25", title: "Season Regular", detail: "Complete 25 anime", symbol: "tv.fill", progress: ratio(anime.count, 25)),
            Achievement(id: "anime100", title: "Centurion", detail: "Complete 100 anime", symbol: "rosette", progress: ratio(anime.count, 100)),
            Achievement(id: "manga25", title: "Bookworm", detail: "Complete 25 manga or novels", symbol: "book.fill", progress: ratio(manga.count, 25)),
            Achievement(id: "days", title: "Time Traveller", detail: "Spend 30 days inside stories", symbol: "clock.arrow.circlepath", progress: ratio(minutes, 30 * 24 * 60)),
            Achievement(id: "decades", title: "Archivist", detail: "Finish titles from 4 different decades", symbol: "archivebox.fill", progress: ratio(decades.count, 4)),
            Achievement(id: "genres", title: "Polymath", detail: "Finish titles across 12 genres", symbol: "square.grid.3x3.fill", progress: ratio(genres.count, 12)),
            Achievement(id: "gems", title: "Gem Hunter", detail: "Finish 5 hidden gems", symbol: "diamond.fill", progress: ratio(gems.count, 5)),
            Achievement(id: "marathon", title: "Marathoner", detail: "Finish a 100+ episode series", symbol: "figure.run", progress: ratio(longest, 100)),
            Achievement(id: "cinema", title: "Cinephile", detail: "Watch 10 films", symbol: "film.fill", progress: ratio(films.count, 10)),
            Achievement(id: "world", title: "Globetrotter", detail: "Finish works from Japan, Korea and China", symbol: "globe.asia.australia.fill", progress: ratio(countries.intersection(["JP", "KR", "CN"]).count, 3)),
            Achievement(id: "journal", title: "Diarist", detail: "Write 10 journal entries", symbol: "pencil.and.scribble", progress: ratio(journal.count, 10)),
            Achievement(id: "revive", title: "Second Wind", detail: "Finish something you started over a year ago", symbol: "wind", progress: ratio(revived.count, 1))
        ]
    }
}

// MARK: - Year recap

public struct YearRecap: Hashable, Sendable {
    public var year: Int
    public var completedAnime: [LibraryEntry]
    public var completedManga: [LibraryEntry]
    public var minutes: Int
    public var episodes: Int
    public var chapters: Int
    public var topGenres: [(String, Int)]
    public var topRated: [LibraryEntry]
    public var busiestMonth: Int?
    public var monthlyMinutes: [Int]
    public var firstFinish: LibraryEntry?
    public var journalCount: Int
    public var favoriteStudio: String?
    public var archetype: String

    public static func == (a: YearRecap, b: YearRecap) -> Bool {
        a.year == b.year && a.minutes == b.minutes && a.completedAnime == b.completedAnime && a.completedManga == b.completedManga
    }
    public func hash(into h: inout Hasher) { h.combine(year); h.combine(minutes) }

    public var isEmpty: Bool { completedAnime.isEmpty && completedManga.isEmpty && minutes == 0 }

    /// - Parameter activities: AniList list activities for the year (preferred source for time spent).
    public static func build(year: Int, library: Library, activities: [ListActivity] = [], journal: [JournalEntry] = [], calendar: Calendar = .current) -> YearRecap {
        let finished = library.all.filter { $0.completedAt?.year == year && ($0.status == .completed || $0.status == .repeating) }
        let anime = finished.filter { $0.type == .anime }.sorted { ($0.completedAt ?? FuzzyDate()) < ($1.completedAt ?? FuzzyDate()) }
        let manga = finished.filter { $0.type == .manga }.sorted { ($0.completedAt ?? FuzzyDate()) < ($1.completedAt ?? FuzzyDate()) }

        var monthly = Array(repeating: 0, count: 12)
        var episodes = 0, chapters = 0
        let yearActivities = activities.filter { calendar.component(.year, from: $0.date) == year }
        if !yearActivities.isEmpty {
            for a in yearActivities {
                let units = a.unitsCovered
                let media = a.media
                let per = media?.minutesPerUnit ?? 24
                monthly[calendar.component(.month, from: a.date) - 1] += units * per
                if media?.mediaType == .manga { chapters += units } else { episodes += units }
            }
        } else {
            // Without activity history, attribute each finished title to its completion month.
            for e in finished {
                let units = e.media.totalUnits ?? e.progress
                let month = (e.completedAt?.month ?? 1) - 1
                monthly[max(0, min(11, month))] += units * e.media.minutesPerUnit
                if e.type == .manga { chapters += units } else { episodes += units }
            }
        }
        let minutes = monthly.reduce(0, +)

        var genreCounts: [String: Int] = [:]
        for e in finished { for g in e.media.genres ?? [] { genreCounts[g, default: 0] += 1 } }
        var studioCounts: [String: Int] = [:]
        for e in anime { if let s = e.media.mainStudio?.name { studioCounts[s, default: 0] += 1 } }

        let busiest = monthly.max().flatMap { m in m > 0 ? monthly.firstIndex(of: m).map { $0 + 1 } : nil }
        let dna = TasteDNA.build(from: finished)

        return YearRecap(
            year: year,
            completedAnime: anime,
            completedManga: manga,
            minutes: minutes,
            episodes: episodes,
            chapters: chapters,
            topGenres: genreCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) },
            topRated: finished.filter(\.isScored).sorted { $0.score > $1.score }.prefix(5).map { $0 },
            busiestMonth: busiest,
            monthlyMinutes: monthly,
            firstFinish: (anime + manga).min { ($0.completedAt ?? FuzzyDate()) < ($1.completedAt ?? FuzzyDate()) },
            journalCount: journal.filter { calendar.component(.year, from: $0.createdAt) == year }.count,
            favoriteStudio: studioCounts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key,
            archetype: dna.archetype.name
        )
    }
}

// MARK: - Persistence

/// Small Codable documents stored atomically as JSON in Application Support.
public struct PersistentStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func appSupport(_ name: String = "Anilite") -> PersistentStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return PersistentStore(directory: base.appendingPathComponent(name, isDirectory: true))
    }

    func url(_ key: String) -> URL { directory.appendingPathComponent(key + ".json") }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    public func save<T: Encodable>(_ value: T, key: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(value)
        try data.write(to: url(key), options: [.atomic])
    }

    public func remove(key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
