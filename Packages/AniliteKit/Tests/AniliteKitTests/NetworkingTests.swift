import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AniliteKit

final class FixtureDecodingTests: XCTestCase {
    func testHomeFeedDecodes() throws {
        let feed = try Fixture.decode(HomeFeed.self, "home")
        XCTAssertEqual(feed.trending.media.count, 4)
        XCTAssertEqual(feed.manga.media.first?.mediaType, .manga)
        XCTAssertTrue(feed.upcoming.media.allSatisfy { $0.status == .notYetReleased || $0.status == .releasing || $0.status == .finished })
    }

    func testDetailDecodesEverything() throws {
        let media = try Fixture.decode(MediaResponse.self, "detail").Media
        XCTAssertEqual(media.id, 154587)
        XCTAssertEqual(media.episodes, 28)
        XCTAssertEqual(media.titleText, "Frieren: Beyond Journey’s End")
        XCTAssertFalse(media.characters?.edges?.isEmpty ?? true)
        XCTAssertFalse(media.relationEdges.isEmpty)
        XCTAssertTrue(media.relationEdges.contains { $0.relationType == .source && $0.node?.id == 118586 })
        XCTAssertTrue(media.externalLinks?.contains { $0.type == .streaming && $0.site == "Crunchyroll" } ?? false)
        XCTAssertEqual(media.streamingEpisodes?.first?.episodeNumber, 1)
        XCTAssertEqual(media.mainStudio?.name, "MADHOUSE")
        XCTAssertEqual(media.totalMinutes, 28 * 24)
    }

    func testAiringSearchListsTagsActivity() throws {
        let airing = try Fixture.decode(AiringResponse.self, "airing")
        XCTAssertEqual(airing.Page.airingSchedules.count, 10)

        let search = try Fixture.decode(PageResponse.self, "search")
        XCTAssertEqual(search.Page.media.count, 6)

        let lists = try Fixture.decode(ListsResponse.self, "lists")
        let library = Library.from(anime: lists.anime, manga: lists.manga, user: nil, isReadOnly: true)
        XCTAssertEqual(library.user?.name, "Anime")
        XCTAssertFalse(library.isEmpty)
        // Entries are unique per media even though AniList repeats them across custom lists.
        XCTAssertEqual(Set(library.all.map(\.mediaId)).count, library.all.count)
        XCTAssertTrue(library.all.allSatisfy { $0.score >= 0 && $0.score <= 100 })

        let taxonomy = try Fixture.decode(TaxonomyResponse.self, "tags")
        XCTAssertEqual(taxonomy.GenreCollection.count, 19)
        XCTAssertGreaterThan(taxonomy.MediaTagCollection.count, 300)

        let activity = try Fixture.decode(ActivityResponse.self, "activity")
        XCTAssertEqual(activity.Page.activities.count, 20)
        XCTAssertTrue(activity.Page.activities.allSatisfy { $0.unitsCovered >= 0 })
    }

    func testUnknownEnumValuesFallBack() throws {
        let json = #"{"id":1,"type":"ANIME","format":"HOLOGRAM","status":"PAUSED_FOREVER"}"#
        let media = try JSONDecoder().decode(Media.self, from: Data(json.utf8))
        XCTAssertEqual(media.format, .unknown)
        XCTAssertEqual(media.status, .unknown)
    }

    func testActivityUnitsCovered() {
        func a(_ p: String?) -> ListActivity { ListActivity(id: 1, status: "watched episode", progress: p, createdAt: 0, media: nil) }
        XCTAssertEqual(a("4 - 6").unitsCovered, 3)
        XCTAssertEqual(a("7").unitsCovered, 1)
        XCTAssertEqual(a(nil).unitsCovered, 0)
    }
}

final class GraphQLTests: XCTestCase {
    func testVariablesDropNilAndEmpty() {
        var v = Variables()
        v.set("a", nil as Int?)
        v.set("b", "")
        v.set("c", [String]())
        v.set("d", 3)
        v.set("e", MediaType.manga)
        XCTAssertEqual(v.values.keys.sorted(), ["d", "e"])
        XCTAssertEqual(v.values["e"], .string("MANGA"))
    }

    func testCacheKeyIsStableAndVariableSensitive() {
        let a = Queries.detail(id: 1), b = Queries.detail(id: 1), c = Queries.detail(id: 2)
        XCTAssertEqual(a.cacheKey, b.cacheKey)
        XCTAssertNotEqual(a.cacheKey, c.cacheKey)
    }

    func testSearchOperationTranslatesQuery() {
        var q = DiscoveryQuery(text: nil, type: .anime)
        q.genresInclude = ["Fantasy"]
        q.maxEpisodes = 13
        q.yearFrom = 2010
        q.yearTo = 2019
        q.minScore = 80
        let op = Queries.search(q, page: 2)
        XCTAssertEqual(op.variables["genreIn"], .array([.string("Fantasy")]))
        XCTAssertEqual(op.variables["episodesLesser"], .int(14))
        XCTAssertEqual(op.variables["startGreater"], .int(20_100_000))
        XCTAssertEqual(op.variables["startLesser"], .int(20_200_000))
        XCTAssertEqual(op.variables["scoreGreater"], .int(79))
        XCTAssertNil(op.variables["search"], "nil variables must be omitted — AniList returns HTTP 500 for explicit nulls")
    }

    func testSaveEntryMutationVariables() {
        let change = EntryChange(mediaId: 5, status: .completed, progress: 12, score: 85, completedAt: FuzzyDate(year: 2024, month: 5, day: 2))
        let op = Queries.saveEntry(change)
        XCTAssertTrue(op.isMutation)
        XCTAssertTrue(op.requiresAuth)
        XCTAssertEqual(op.variables["scoreRaw"], .int(85))
        XCTAssertEqual(op.variables["completedAt"], .object(["year": .int(2024), "month": .int(5), "day": .int(2)]))
        XCTAssertNil(op.variables["notes"])
    }
}

final class RateLimiterTests: XCTestCase {
    func testWaitsWhenWindowIsFull() async throws {
        let clock = TestClock()
        let limiter = RateLimiter(limit: 3, window: 60, clock: clock.clock)
        for _ in 0..<3 { try await limiter.acquire() }
        XCTAssertTrue(clock.slept.isEmpty)
        try await limiter.acquire()
        XCTAssertEqual(clock.slept.count, 1)
        XCTAssertEqual(clock.slept[0], 60, accuracy: 0.01)
    }

    func testAdaptsToServerLimitAndBacksOff() async throws {
        let clock = TestClock()
        let limiter = RateLimiter(limit: 28, clock: clock.clock)
        await limiter.record(limitHeader: 90, remaining: 50)
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 88)
        await limiter.backOff(for: 30)
        try await limiter.acquire()
        XCTAssertEqual(clock.slept.first ?? 0, 30, accuracy: 0.01)
    }
}

final class ResponseCacheTests: XCTestCase {
    func testMemoryAndDiskRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anilite-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock()
        let cache = ResponseCache(directory: dir, memoryLimit: 2, clock: clock.clock)
        await cache.store(Data("one".utf8), for: "k1")
        let hit = await cache.entry(for: "k1")
        XCTAssertEqual(hit?.data, Data("one".utf8))

        // A fresh instance reads it back from disk with its timestamp intact.
        let reopened = ResponseCache(directory: dir, memoryLimit: 2, clock: clock.clock)
        let disk = await reopened.entry(for: "k1")
        XCTAssertEqual(disk?.data, Data("one".utf8))
        XCTAssertEqual(disk?.storedAt.timeIntervalSince1970 ?? 0, clock.now.timeIntervalSince1970, accuracy: 0.01)

        await reopened.remove("k1")
        let gone = await reopened.entry(for: "k1")
        XCTAssertNil(gone)
    }
}

final class AniListClientTests: XCTestCase {
    func makeClient(_ transport: MockTransport, clock: TestClock = TestClock()) -> (AniListClient, ResponseCache) {
        let cache = ResponseCache(directory: nil, clock: clock.clock)
        let client = AniListClient(transport: transport, cache: cache, limiter: RateLimiter(limit: 100, clock: clock.clock), clock: clock.clock)
        return (client, cache)
    }

    func testCacheFirstAvoidsSecondRequest() async throws {
        let body = String(decoding: try Fixture.data("detail"), as: UTF8.self)
        let transport = MockTransport([MockTransport.json(body)])
        let (client, _) = makeClient(transport)
        let first = try await client.fetchDetailed(Queries.detail(id: 154587))
        XCTAssertEqual(first.source, .network)
        let second = try await client.fetchDetailed(Queries.detail(id: 154587))
        XCTAssertEqual(second.source, .cache(stale: false))
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "User-Agent"), AniListClient.userAgent)
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testFallsBackToStaleCacheWhenOffline() async throws {
        let clock = TestClock()
        let body = String(decoding: try Fixture.data("detail"), as: UTF8.self)
        let transport = MockTransport([MockTransport.json(body)])
        let (client, _) = makeClient(transport, clock: clock)
        _ = try await client.fetch(Queries.detail(id: 154587))
        clock.advance(60 * 60 * 24 * 30)
        let stale = try await client.fetchDetailed(Queries.detail(id: 154587))
        XCTAssertEqual(stale.source, .cache(stale: true))
        XCTAssertEqual(stale.value.Media.id, 154587)
    }

    func testRetriesAfter429() async throws {
        let body = String(decoding: try Fixture.data("detail"), as: UTF8.self)
        let clock = TestClock()
        let transport = MockTransport([
            MockTransport.json(#"{"errors":[{"message":"Too Many Requests.","status":429}],"data":null}"#, status: 429, headers: ["Retry-After": "7"]),
            MockTransport.json(body)
        ])
        let (client, _) = makeClient(transport, clock: clock)
        let result = try await client.fetch(Queries.detail(id: 154587), policy: .networkOnly)
        XCTAssertEqual(result.Media.id, 154587)
        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertTrue(clock.slept.contains { abs($0 - 7) < 0.01 })
    }

    func testErrorMapping() async {
        let transport = MockTransport([MockTransport.json(#"{"errors":[{"message":"Private User","status":404}],"data":null}"#, status: 404)])
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.fetch(Queries.lists(userName: "someone"), policy: .networkOnly)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AniListError, .privateUser)
        }
        XCTAssertEqual(AniListClient.map(errors: [], status: 401), .unauthorized)
        XCTAssertEqual(AniListClient.map(errors: [], status: 503), .server(status: 503, message: "Server error"))
    }

    func testAuthRequiredWithoutToken() async {
        let (client, _) = makeClient(MockTransport())
        do {
            _ = try await client.fetch(Queries.viewer(), policy: .networkOnly)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AniListError, .authRequired)
        }
    }

    func testTokenSentOnlyForAuthenticatedOperations() async throws {
        let transport = MockTransport(fallback: MockTransport.json(#"{"data":{"Viewer":{"id":7,"name":"me"}}}"#))
        let (client, _) = makeClient(transport)
        await client.setToken("secret")
        let viewer = try await client.fetch(Queries.viewer(), policy: .networkOnly)
        XCTAssertEqual(viewer.Viewer.name, "me")
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testOfflineErrorIsRetryable() async {
        let (client, _) = makeClient(MockTransport())
        do {
            _ = try await client.fetch(Queries.detail(id: 9), policy: .networkFirst)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AniListError, .offline)
            XCTAssertTrue((error as? AniListError)?.isRetryable ?? false)
        }
    }
}
