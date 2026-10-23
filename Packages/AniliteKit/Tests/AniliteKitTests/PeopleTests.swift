import Foundation
import XCTest
@testable import AniliteKit

final class AtlasTimelineTests: XCTestCase {
    private func franchise() -> AtlasGraph {
        var graph = AtlasGraph()
        let original = makeMedia(1, "Original", year: 1998)
        let sequel = makeMedia(2, "Sequel", year: 2001)
        let remake = makeMedia(3, "Remake", year: 2023)
        let manga = makeMedia(4, "Manga", type: .manga, year: 1996)
        var undated = makeMedia(5, "Announced", year: 2030)
        undated.seasonYear = nil
        undated.startDate = nil
        for m in [original, sequel, remake, manga, undated] { graph.add(AtlasGraph.mediaNode(m)) }
        graph.link(AtlasNodeID(.anime, 1), AtlasNodeID(.anime, 2), "Sequel")
        graph.link(AtlasNodeID(.anime, 1), AtlasNodeID(.manga, 4), "Source")
        let hero = AtlasNode(id: AtlasNodeID(.character, 10), title: "Hero", subtitle: nil, imageURL: nil, colorHex: nil, isSpoilerHidden: false, weight: 1)
        let voice = AtlasNode(id: AtlasNodeID(.creator, 20), title: "Voice", subtitle: nil, imageURL: nil, colorHex: nil, isSpoilerHidden: false, weight: 1)
        let director = AtlasNode(id: AtlasNodeID(.creator, 21), title: "Director", subtitle: nil, imageURL: nil, colorHex: nil, isSpoilerHidden: false, weight: 1)
        for n in [hero, voice, director] { graph.add(n) }
        graph.link(AtlasNodeID(.anime, 2), hero.id, "Character")
        graph.link(hero.id, voice.id, "Voiced by")
        graph.link(AtlasNodeID(.anime, 3), director.id, "Director")
        return graph
    }

    func testTitlesRunInReleaseOrder() {
        let timeline = AtlasTimeline.layout(franchise())
        let x = { (kind: AtlasKind, id: Int) in timeline.positions[AtlasNodeID(kind, id)]!.x }
        XCTAssertLessThan(x(.manga, 4), x(.anime, 1))
        XCTAssertLessThan(x(.anime, 1), x(.anime, 2))
        XCTAssertLessThan(x(.anime, 2), x(.anime, 3))
        XCTAssertGreaterThan(x(.anime, 5), x(.anime, 3), "Undated titles go at the end")
        XCTAssertEqual(timeline.ticks.last?.year, nil)
        XCTAssertEqual(timeline.ticks.compactMap(\.year), [1996, 1998, 2001, 2023])
    }

    func testLongGapsAreCompressed() {
        let timeline = AtlasTimeline.layout(franchise())
        let ticks = timeline.ticks.filter { $0.year != nil }
        let shortGap = ticks[2].x - ticks[1].x   // 1998 → 2001
        let longGap = ticks[3].x - ticks[2].x    // 2001 → 2023
        XCTAssertLessThan(longGap, shortGap * 1.7, "22 years shouldn't take 7× the space of 3")
    }

    func testPeopleSitInLanesUnderTheirTitles() {
        let timeline = AtlasTimeline.layout(franchise())
        let sequel = timeline.positions[AtlasNodeID(.anime, 2)]!
        let hero = timeline.positions[AtlasNodeID(.character, 10)]!
        let voice = timeline.positions[AtlasNodeID(.creator, 20)]!
        let director = timeline.positions[AtlasNodeID(.creator, 21)]!
        XCTAssertEqual(hero.x, sequel.x, accuracy: 1e-9)
        XCTAssertGreaterThan(hero.y, timeline.axisY, "Characters below the titles")
        XCTAssertLessThan(director.y, timeline.axisY, "Creators above the titles")
        XCTAssertEqual(voice.x, hero.x, accuracy: 1e-9, "Voice actors follow their character")
        XCTAssertTrue(timeline.positions.values.allSatisfy { $0.z == 0 && $0.x.isFinite && $0.y.isFinite })
    }

    func testDeterministicAndCentred() {
        let a = AtlasTimeline.layout(franchise()), b = AtlasTimeline.layout(franchise())
        XCTAssertEqual(a.positions, b.positions)
        XCTAssertEqual(a.span.lowerBound, -a.span.upperBound, accuracy: 1e-9)
        XCTAssertTrue(AtlasTimeline.layout(AtlasGraph()).positions.isEmpty)
    }

    func testMediaNodesCarryYear() throws {
        let frieren = try Fixture.decode(MediaResponse.self, "detail").Media
        var graph = AtlasGraph()
        graph.expand(media: frieren)
        XCTAssertEqual(graph.nodes[AtlasNodeID(.anime, frieren.id)]?.year, frieren.year)
    }
}

final class PeopleTests: XCTestCase {
    private func user(_ id: Int, _ name: String) -> AniListUser { AniListUser(id: id, name: name) }

    func testSeedsPreferHighScoresThenNiche() {
        let hit = makeMedia(1, "Hit", popularity: 900_000)
        let niche = makeMedia(2, "Niche", popularity: 4_000)
        let meh = makeMedia(3, "Meh")
        let planned = makeMedia(4, "Planned")
        let library = makeLibrary([
            makeEntry(hit, .completed, score: 90),
            makeEntry(niche, .completed, score: 90),
            makeEntry(meh, .completed, score: 40),
            makeEntry(planned, .planning, score: 0)
        ])
        let seeds = PeopleFinder.seeds(from: library)
        XCTAssertEqual(seeds.map(\.id), [2, 1], "Low scores and plans aren't taste signals")
    }

    func testRankRewardsOverlapAcrossTitles() {
        let a = makeMedia(1, "Mushishi", popularity: 20_000)
        let b = makeMedia(2, "Frieren", popularity: 400_000)
        let signals: [String: PeopleSignalPage] = [
            "r0": PeopleSignalPage(reviews: [
                ReviewSignal(id: 1, score: 95, mediaId: 1, user: user(10, "Ginko")),
                ReviewSignal(id: 2, score: 30, mediaId: 1, user: user(11, "Hater"))
            ]),
            "a0": PeopleSignalPage(activities: [
                ActivitySignal(id: 5, status: "completed", media: .init(id: 1), user: user(12, "Both")),
                ActivitySignal(id: 6, status: "watched episode", media: .init(id: 1), user: user(10, "Ginko"))
            ]),
            "a1": PeopleSignalPage(activities: [
                ActivitySignal(id: 7, status: "completed", media: .init(id: 2), user: user(12, "Both")),
                ActivitySignal(id: 8, status: "plans to watch", media: .init(id: 2), user: user(13, "Later")),
                ActivitySignal(id: 9, status: "completed", media: .init(id: 2), user: user(99, "Me"))
            ])
        ]
        let ranked = PeopleFinder.rank(signals: signals, seeds: [a, b], excluding: ["me"])
        XCTAssertEqual(ranked.first?.user.name, "Both", "Two shared titles beat one strong review")
        XCTAssertEqual(ranked.map(\.user.name).prefix(2), ["Both", "Ginko"])
        XCTAssertFalse(ranked.contains { $0.user.name == "Me" })
        XCTAssertFalse(ranked.contains { $0.user.name == "Hater" }, "A low review isn't shared taste")
        let ginko = ranked.first { $0.user.name == "Ginko" }!
        XCTAssertEqual(ginko.reasons.count, 1, "One reason per title, keeping the strongest")
        XCTAssertEqual(ginko.reasons.first?.signal, .reviewed(score: 95))
        XCTAssertEqual(ginko.summary, "reviewed Mushishi (95)")
        XCTAssertEqual(ranked.last?.user.name, "Later")
    }

    func testSignalsQueryAliasesEachTitle() {
        let op = Queries.peopleSignals(mediaIds: [1, 2, 3, 4, 5])
        XCTAssertEqual(op.variables.count, 4, "Capped at four titles per request")
        XCTAssertTrue(op.query.contains("r3: Page"))
        XCTAssertTrue(op.query.contains("a0: Page"))
        XCTAssertFalse(op.query.contains("$m4"))
        XCTAssertFalse(op.requiresAuth)
        XCTAssertTrue(Queries.toggleFollow(userId: 1).requiresAuth)
        XCTAssertTrue(Queries.toggleFollow(userId: 1).isMutation)
        XCTAssertTrue(Queries.userProfile(name: "x").attachesToken)
        XCTAssertTrue(Queries.followingFeed().requiresAuth)
    }

    func testDecodesSignalPagesAndProfile() throws {
        let signals = """
        {"data":{"r0":{"reviews":[{"id":1,"score":88,"mediaId":5,"user":{"id":3,"name":"Ann","avatar":{"large":"l"}}}]},
                 "a0":{"activities":[{"id":2,"status":"completed","createdAt":1700000000,"media":{"id":5},"user":{"id":4,"name":"Bo"}},{}]}}}
        """
        struct Envelope: Decodable { var data: [String: PeopleSignalPage] }
        // Unions return {} for non-list activities; those must not break decoding.
        let decoded = try JSONDecoder().decode(Envelope.self, from: Data(signals.utf8)).data
        XCTAssertEqual(decoded["r0"]?.reviews?.first?.user?.name, "Ann")
        XCTAssertEqual(decoded["a0"]?.activities?.count, 2)

        let profile = """
        {"id":7,"name":"Ann","about":"Hi! __Loves__ [Mushishi](https://anilist.co/anime/457) ~!secret ending!~ img220(https://x/y.png)","isFollowing":true,"isFollower":true,
         "statistics":{"anime":{"count":120,"minutesWatched":28800,"meanScore":78.5}},
         "favourites":{"anime":{"nodes":[{"id":457,"title":{"romaji":"Mushishi"}}]},"characters":{"nodes":[{"id":1,"name":{"full":"Ginko"}}]}}}
        """
        let user = try JSONDecoder().decode(UserProfile.self, from: Data(profile.utf8))
        XCTAssertEqual(user.aboutText, "Hi! Loves Mushishi")
        XCTAssertTrue(user.isMutual)
        XCTAssertEqual(user.daysWatched, 20, accuracy: 1e-9)
        XCTAssertEqual(user.favouriteTitles.map(\.id), [457])
    }
}
