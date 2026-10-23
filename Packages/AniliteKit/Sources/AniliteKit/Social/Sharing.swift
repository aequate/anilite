import Foundation

/// Encodes small Codable payloads into copy-pasteable codes and `anilite://` links.
/// Nothing is uploaded anywhere: the code *is* the data.
public enum ShareCodec {
    public static let scheme = "anilite"

    public static func encode<T: Encodable>(_ value: T, prefix: String) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return prefix + "-" + base64URL(data)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from code: String, prefix: String) -> T? {
        var trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept a full link too.
        if let url = URL(string: trimmed), url.scheme == scheme,
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let d = comps.queryItems?.first(where: { $0.name == "d" })?.value {
            trimmed = d
        }
        guard trimmed.hasPrefix(prefix + "-") else { return nil }
        let body = String(trimmed.dropFirst(prefix.count + 1))
        guard let data = fromBase64URL(body) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func link(kind: String, code: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = kind
        comps.queryItems = [URLQueryItem(name: "d", value: code)]
        return comps.url
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64URL(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

/// What an incoming `anilite://` link points at.
public enum DeepLink: Equatable, Sendable {
    case auth(token: String?, expiresIn: Int?, error: String?)
    case media(id: Int)
    case sharedList(SharedList)
    case club(Club)
    case fingerprint(TasteFingerprint)
    case user(name: String)

    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == ShareCodec.scheme else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch url.host {
        case "auth-callback":
            // Implicit grant returns the token in the fragment: #access_token=...&token_type=Bearer&expires_in=...
            var params: [String: String] = [:]
            for pair in (url.fragment ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
            let error = params["error"] ?? query["error"]
            return .auth(token: params["access_token"], expiresIn: params["expires_in"].flatMap(Int.init), error: error)
        case "media":
            let id = url.pathComponents.dropFirst().first.flatMap(Int.init) ?? query["id"].flatMap(Int.init)
            return id.map { .media(id: $0) }
        case "list":
            return query["d"].flatMap { ShareCodec.decode(SharedList.self, from: $0, prefix: SharedList.prefix) }.map { .sharedList($0) }
        case "club":
            return query["d"].flatMap { ShareCodec.decode(Club.self, from: $0, prefix: Club.prefix) }.map { .club($0) }
        case "dna":
            return query["d"].flatMap { TasteFingerprint.decode($0) }.map { .fingerprint($0) }
        case "user":
            return url.pathComponents.dropFirst().first.map { .user(name: $0) }
        default:
            return nil
        }
    }
}

/// A curated list shared as a code. Notes pass through the spoiler filter before sharing.
public struct SharedList: Codable, Hashable, Sendable, Identifiable {
    public static let prefix = "LIST"

    public struct Item: Codable, Hashable, Sendable {
        public var id: Int
        public var title: String
        public var note: String?
        public init(id: Int, title: String, note: String? = nil) { self.id = id; self.title = title; self.note = note }
    }

    public var title: String
    public var curator: String
    public var items: [Item]
    public var created: Date
    public var id: String { title + curator + String(created.timeIntervalSince1970) }

    public init(title: String, curator: String, items: [Item], created: Date = Date()) {
        self.title = title
        self.curator = curator
        self.items = items
        self.created = Date(timeIntervalSince1970: created.timeIntervalSince1970.rounded())
    }

    public var code: String { ShareCodec.encode(self, prefix: Self.prefix) ?? "" }
    public var link: URL? { ShareCodec.link(kind: "list", code: code) }

    /// Builds a list from a shelf, stripping spoilers from personal notes.
    public static func from(title: String, curator: String, entries: [LibraryEntry], notes: [Int: String] = [:]) -> SharedList {
        SharedList(title: title, curator: curator, items: entries.prefix(60).map { entry in
            let raw = notes[entry.mediaId].map { spoilerFree($0) }
            let note = raw.flatMap { $0.isEmpty ? nil : String($0.prefix(140)) }
            return Item(id: entry.mediaId, title: entry.media.titleText, note: note)
        })
    }

    /// Drops `~!spoiler!~` segments so shared notes never leak marked spoilers.
    public static func spoilerFree(_ text: String) -> String {
        RichText.segments(from: text).filter { !$0.isSpoiler }.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A watch/read club: a shared pacing plan everyone follows on their own AniList account.
public struct Club: Codable, Hashable, Sendable, Identifiable {
    public static let prefix = "CLUB"

    public var id: String
    public var name: String
    public var mediaId: Int
    public var mediaTitle: String
    public var mediaType: MediaType
    public var totalUnits: Int
    public var unitsPerSession: Int
    /// Days of the week (1 = Sunday … 7 = Saturday) the club meets.
    public var weekdays: [Int]
    public var startDate: Date
    public var host: String
    public var members: [String]

    public init(id: String = UUID().uuidString, name: String, mediaId: Int, mediaTitle: String, mediaType: MediaType, totalUnits: Int,
                unitsPerSession: Int, weekdays: [Int], startDate: Date, host: String, members: [String] = []) {
        self.id = id
        self.name = name
        self.mediaId = mediaId
        self.mediaTitle = mediaTitle
        self.mediaType = mediaType
        self.totalUnits = max(1, totalUnits)
        self.unitsPerSession = max(1, unitsPerSession)
        self.weekdays = weekdays.isEmpty ? [7] : Array(Set(weekdays)).sorted()
        self.startDate = Date(timeIntervalSince1970: startDate.timeIntervalSince1970.rounded())
        self.host = host
        self.members = members
    }

    public var code: String { ShareCodec.encode(self, prefix: Self.prefix) ?? "" }
    public var link: URL? { ShareCodec.link(kind: "club", code: code) }

    public struct Session: Hashable, Sendable, Identifiable {
        public var index: Int
        public var date: Date
        public var units: ClosedRange<Int>
        public var id: Int { index }
    }

    /// Every meeting from the start date until the title is finished.
    public func schedule(calendar: Calendar = .current) -> [Session] {
        var sessions: [Session] = []
        var day = calendar.startOfDay(for: startDate)
        var next = 1
        var guardCount = 0
        while next <= totalUnits && guardCount < 3650 {
            guardCount += 1
            if weekdays.contains(calendar.component(.weekday, from: day)) {
                let end = min(totalUnits, next + unitsPerSession - 1)
                sessions.append(Session(index: sessions.count, date: day, units: next...end))
                next = end + 1
            }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = tomorrow
        }
        return sessions
    }

    /// The units the club should have reached by `date` — the club's spoiler line.
    public func expectedProgress(on date: Date, calendar: Calendar = .current) -> Int {
        schedule(calendar: calendar).filter { $0.date <= date }.last?.units.upperBound ?? 0
    }

    public func nextSession(after date: Date, calendar: Calendar = .current) -> Session? {
        let today = calendar.startOfDay(for: date)
        return schedule(calendar: calendar).first { $0.date >= today }
    }

    public enum Standing: Equatable, Sendable { case ahead(Int), onTrack, behind(Int) }

    public func standing(progress: Int, on date: Date, calendar: Calendar = .current) -> Standing {
        let expected = expectedProgress(on: date, calendar: calendar)
        if progress > expected { return .ahead(progress - expected) }
        if progress < expected { return .behind(expected - progress) }
        return .onTrack
    }
}
