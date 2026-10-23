import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AniliteKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json") else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(FixtureEnvelope<T>.self, from: data(name)).data
    }
}

struct FixtureEnvelope<T: Decodable>: Decodable { let data: T }

/// A clock tests can move by hand. `sleep` advances time instantly.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private(set) var slept: [TimeInterval] = []

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }

    var now: Date { lock.lock(); defer { lock.unlock() }; return current }

    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }

    var clock: AppClock {
        AppClock(now: { self.now }, sleep: { s in self.recordSleep(s) })
    }

    private func recordSleep(_ s: TimeInterval) {
        lock.lock()
        slept.append(s)
        current += s
        lock.unlock()
    }
}

/// Scripted HTTP responses; records every request.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
        var error: Error?
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    var fallback: Reply?

    init(_ replies: [Reply] = [], fallback: Reply? = nil) {
        self.replies = replies
        self.fallback = fallback
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let reply = nextReply(for: request) else { throw URLError(.notConnectedToInternet) }
        if let error = reply.error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }

    private func nextReply(for request: URLRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return replies.isEmpty ? fallback : replies.removeFirst()
    }

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    static func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
        Reply(status: status, body: Data(string.utf8), headers: headers)
    }
}

func makeMedia(
    _ id: Int, _ title: String, type: MediaType = .anime, format: MediaFormat = .tv, status: MediaStatus = .finished,
    episodes: Int? = 12, chapters: Int? = nil, duration: Int? = 24, year: Int = 2020, score: Int? = 75, popularity: Int? = 50_000,
    genres: [String] = [], tags: [(String, Int)] = [], color: String? = nil, relations: [(MediaRelationType, Media)] = []
) -> Media {
    var m = Media(
        id: id, type: type, format: format, status: status, episodes: type == .anime ? episodes : nil, chapters: chapters,
        duration: type == .anime ? duration : nil, seasonYear: year, averageScore: score, popularity: popularity, genres: genres,
        title: MediaTitle(romaji: title, english: title),
        coverImage: CoverImage(large: "https://example.com/\(id).jpg", color: color),
        startDate: FuzzyDate(year: year, month: 4, day: 1),
        tags: tags.enumerated().map { MediaTag(id: 1000 + $0.offset, name: $0.element.0, rank: $0.element.1) }
    )
    if !relations.isEmpty {
        m.relations = RelationConnection(edges: relations.map { MediaRelationEdge(relationType: $0.0, node: $0.1) })
    }
    return m
}

func makeEntry(_ media: Media, _ status: MediaListStatus, progress: Int = 0, score: Double = 0, updated: Date = Date(timeIntervalSince1970: 1_700_000_000),
               completedAt: FuzzyDate? = nil, startedAt: FuzzyDate? = nil) -> LibraryEntry {
    var p = progress
    if status == .completed, p == 0 { p = media.totalUnits ?? 0 }
    return LibraryEntry(media: media, status: status, progress: p, score: score, startedAt: startedAt, completedAt: completedAt, updatedAt: updated)
}

func makeLibrary(_ entries: [LibraryEntry], readOnly: Bool = false) -> Library {
    Library(entries: Dictionary(uniqueKeysWithValues: entries.map { ($0.mediaId, $0) }), isReadOnly: readOnly)
}

var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

func utcDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    utcCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
