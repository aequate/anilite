import XCTest
@testable import AniliteKit

final class TasteTests: XCTestCase {
    func fantasyFan() -> Library {
        var entries: [LibraryEntry] = []
        for i in 0..<8 {
            let m = makeMedia(100 + i, "Fantasy \(i)", year: 2012 + i, score: 80, genres: ["Fantasy", "Adventure"], tags: [("Magic", 85), ("Travel", 70)])
            entries.append(makeEntry(m, .completed, score: 85 + Double(i % 3) * 5, completedAt: FuzzyDate(year: 2024, month: 1 + i, day: 1)))
        }
        for i in 0..<3 {
            let m = makeMedia(200 + i, "Horror \(i)", year: 2015, score: 70, genres: ["Horror"], tags: [("Gore", 80)])
            entries.append(makeEntry(m, .dropped, progress: 2, score: 30))
        }
        return makeLibrary(entries)
    }

    func testDNAFindsTopAndDislikedGenres() {
        let dna = TasteDNA.build(from: fantasyFan().all)
        XCTAssertTrue(dna.isMeaningful)
        XCTAssertEqual(Set(dna.topGenres.prefix(2)), ["Fantasy", "Adventure"])
        XCTAssertTrue(dna.dislikedGenres.contains("Horror"))
        XCTAssertGreaterThan(dna.dropRate, 0)
        XCTAssertFalse(dna.strands.isEmpty)
        XCTAssertFalse(dna.archetype.name.isEmpty)
    }

    func testEmptyLibraryGivesNewcomer() {
        let dna = TasteDNA.build(from: [])
        XCTAssertFalse(dna.isMeaningful)
        XCTAssertEqual(dna.sampleSize, 0)
    }

    func testRecommenderPrefersTasteAndExplains() {
        let library = fantasyFan()
        let dna = TasteDNA.build(from: library.all)
        let fantasy = makeMedia(300, "New Quest", score: 82, popularity: 20_000, genres: ["Fantasy", "Adventure"], tags: [("Magic", 90)])
        let horror = makeMedia(301, "Night Terror", score: 82, genres: ["Horror"], tags: [("Gore", 90)])
        let owned = library.all[0].media
        var adult = makeMedia(302, "Adult", genres: ["Fantasy"])
        adult.isAdult = true
        let ranked = Recommender.rank(candidates: [horror, fantasy, owned, adult], dna: dna, library: library)
        XCTAssertEqual(ranked.first?.media.id, 300)
        XCTAssertFalse(ranked.contains { $0.media.id == owned.id })
        XCTAssertFalse(ranked.contains { $0.media.id == 302 })
        XCTAssertFalse(ranked.first?.reasons.isEmpty ?? true)
        XCTAssertTrue(ranked.first?.isHiddenGem ?? false)
        XCTAssertTrue((0...100).contains(ranked.first?.matchPercent ?? -1))
    }

    func testRevivalsSuggestAcclaimedDrops() {
        var entries = fantasyFan().all
        let gem = makeMedia(400, "Paused Classic", score: 88, genres: ["Fantasy"])
        entries.append(makeEntry(gem, .paused, progress: 2))
        let library = makeLibrary(entries)
        let revivals = Recommender.revivals(library: library, dna: TasteDNA.build(from: library.all))
        XCTAssertEqual(revivals.first?.media.id, 400)
    }

    func testCompatibilityWithSelfIsHigh() {
        let library = fantasyFan()
        let report = Compatibility.compare(mine: library, theirs: library, theirName: "Twin")
        XCTAssertGreaterThanOrEqual(report.score, 85)
        XCTAssertEqual(report.sharedCount, library.all.count)
        XCTAssertFalse(report.sharedFavorites.isEmpty)
    }

    func testFingerprintRoundTrip() throws {
        let dna = TasteDNA.build(from: fantasyFan().all)
        let print = TasteFingerprint(name: "Me", dna: dna)
        let decoded = try XCTUnwrap(TasteFingerprint.decode(print.code))
        XCTAssertEqual(decoded, print)
        XCTAssertGreaterThanOrEqual(print.compatibility(with: decoded), 99)
        XCTAssertNil(TasteFingerprint.decode("garbage"))
    }
}

final class PathfinderTests: XCTestCase {
    func aotGraph() throws -> FranchiseGraph {
        let batch = try Fixture.decode(MediaBatchResponse.self, "relations")
        let media = batch.Page.media
        var graph = FranchiseGraph(seed: try XCTUnwrap(media.first { $0.id == 16498 }))
        for m in media { graph.merge(m) }
        return graph
    }

    func testMainlineIncludesSpecialFinaleAndSkipsExtras() throws {
        let graph = try aotGraph()
        let ids = graph.mainline.map(\.id)
        XCTAssertEqual(Array(ids.prefix(6)), [16498, 20958, 99147, 104578, 110277, 131681])
        XCTAssertEqual(ids.last, 146984, "The Final Chapters (SPECIAL) continues the story")
        XCTAssertFalse(ids.contains(20811), "No Regrets is a prequel side story")
        XCTAssertFalse(ids.contains(119113), "Recap films are not main story")
        XCTAssertEqual(graph.sourceMedia?.id, 53390)
    }

    func testRoutes() throws {
        let graph = try aotGraph()
        let routes = Pathfinder.routes(for: graph)
        let essentials = try XCTUnwrap(routes.first { $0.kind == .essentials })
        XCTAssertTrue(essentials.steps.allSatisfy { !$0.isOptional })
        XCTAssertGreaterThan(essentials.totalMinutes, 80 * 20)
        XCTAssertEqual(essentials.continuePoint?.confidence, .complete, "The finale adapts the whole manga")
        let mangaFirst = try XCTUnwrap(routes.first { $0.kind == .mangaFirst })
        XCTAssertEqual(mangaFirst.steps.first?.role, .source)
        if let completionist = routes.first(where: { $0.kind == .completionist }) {
            XCTAssertTrue(completionist.steps.contains { $0.role == .recap && $0.isOptional })
        }

        // Progress through the library moves "next step" forward.
        let s1 = try XCTUnwrap(graph.nodes[16498])
        let library = makeLibrary([makeEntry(s1, .completed)])
        XCTAssertEqual(essentials.nextStep(in: library)?.media.id, 20958)
        XCTAssertLessThan(essentials.remainingMinutes(in: library), essentials.totalMinutes)
    }

    func testFrontierListsUnexpandedStoryNodes() throws {
        let graph = try aotGraph()
        let frontier = graph.frontier()
        XCTAssertTrue(frontier.contains(146984))
        XCTAssertFalse(frontier.contains(16498))
    }

    func testCuratedContinuePoints() {
        let s1 = makeMedia(16498, "Attack on Titan", episodes: 25)
        let p = ContinuePointResolver.resolve(anime: s1, source: nil)
        XCTAssertEqual(p?.unit, 34)
        XCTAssertEqual(p?.confidence, .curated)
        XCTAssertEqual(p?.headline, "Continue from chapter 34")

        let jjk0 = makeMedia(131573, "JJK 0", format: .movie, episodes: 1)
        XCTAssertEqual(ContinuePointResolver.resolve(anime: jjk0, source: nil)?.confidence, .complete)
    }

    func testEstimatedContinuePoints() {
        let anime = makeMedia(9_000_001, "Show", episodes: 12)
        let manga = makeMedia(9_000_002, "Show", type: .manga, format: .manga, status: .releasing, chapters: nil)
        let p = ContinuePointResolver.resolve(anime: anime, source: manga)
        XCTAssertEqual(p?.unit, 32)
        XCTAssertEqual(p?.confidence, .estimated)

        let novel = makeMedia(9_000_003, "Show LN", type: .manga, format: .novel, status: .releasing)
        let ln = ContinuePointResolver.resolve(anime: anime, source: novel)
        XCTAssertEqual(ln?.unit, 4)
        XCTAssertEqual(ln?.unitName, "volume")

        let shortManga = makeMedia(9_000_004, "Short", type: .manga, format: .manga, status: .finished, chapters: 20)
        XCTAssertEqual(ContinuePointResolver.resolve(anime: anime, source: shortManga)?.confidence, .complete)
    }

    func testEndingAssurance() throws {
        let finishedManga = makeMedia(1, "Done", type: .manga, format: .manga, status: .finished, chapters: 100)
        XCTAssertEqual(FranchiseHealth.assess(media: finishedManga, graph: nil, continuePoint: nil).verdict, .complete)

        let airing = makeMedia(2, "Airing", status: .releasing)
        XCTAssertEqual(FranchiseHealth.assess(media: airing, graph: nil, continuePoint: nil).verdict, .ongoing)

        let sequel = makeMedia(4, "Show 2", status: .notYetReleased, year: 2027)
        let first = makeMedia(3, "Show", relations: [(.sequel, sequel)])
        let graph = FranchiseGraph(seed: first)
        let health = FranchiseHealth.assess(media: first, graph: graph, continuePoint: nil)
        XCTAssertEqual(health.verdict, .sequelAnnounced)
        XCTAssertTrue(health.detail.contains("2027"))

        let source = makeMedia(6, "Src", type: .manga, format: .manga, status: .releasing)
        let adapted = makeMedia(5, "Adapted", year: 2019, relations: [(.source, source)])
        let g2 = FranchiseGraph(seed: adapted)
        let cp = ContinuePointResolver.resolve(anime: adapted, source: source)
        XCTAssertEqual(FranchiseHealth.assess(media: adapted, graph: g2, continuePoint: cp, now: utcDate(2026, 1, 1)).verdict, .sourceAhead)
    }

    func testFillerGuide() throws {
        let naruto = try XCTUnwrap(FillerGuide.info(for: 20))
        XCTAssertTrue(naruto.isFiller(150))
        XCTAssertFalse(naruto.isFiller(142))
        XCTAssertEqual(naruto.canonRemaining(after: 135, total: 220), 1)
        XCTAssertEqual(naruto.fillerCount, 1 + 1 + 6 + 6 + 78)
    }
}
