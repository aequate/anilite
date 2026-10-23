import XCTest
@testable import AniliteKit

final class RichTextTests: XCTestCase {
    func testSpoilerMarkupAndCleaning() {
        let raw = "A <b>hero</b> rises.<br><br>~!She dies at the end.!~ Read [more](https://x.y) &amp; enjoy__!__ (Source: Crunchyroll)"
        let segs = RichText.segments(from: raw)
        XCTAssertEqual(segs.filter(\.isSpoiler).map(\.text), ["She dies at the end."])
        let plain = RichText.plain(raw)
        XCTAssertFalse(plain.contains("dies"))
        XCTAssertTrue(plain.contains("A hero rises."))
        XCTAssertTrue(plain.contains("Read more & enjoy!"))
        XCTAssertEqual(RichText.withoutSourceCredit("Story. (Source: Crunchyroll)"), "Story.")
    }

    func testHTMLSpoilerSpans() {
        let segs = RichText.segments(from: "Safe <span class='markdown_spoiler'>secret</span> end")
        XCTAssertEqual(segs.map(\.isSpoiler), [false, true, false])
    }

    func testEntityOrdering() {
        XCTAssertEqual(RichText.clean("&amp;lt;tag&amp;gt;"), "&lt;tag&gt;")
    }
}

final class SpoilerShieldTests: XCTestCase {
    let show = makeMedia(1, "Show", episodes: 24)

    func ctx(_ progress: Int, _ status: MediaListStatus? = .current) -> SpoilerContext {
        SpoilerContext(mediaId: 1, status: status, progress: progress, total: 24)
    }

    func testDescriptionsHideMarkedSpoilersUntilFinished() {
        let raw = "Setup. ~!Twist!~"
        let watching = SpoilerShield.segments(raw, context: ctx(3), policy: SpoilerPolicy())
        XCTAssertFalse(watching[1].visibility.isVisible)
        let done = SpoilerShield.segments(raw, context: ctx(24, .completed), policy: SpoilerPolicy())
        XCTAssertTrue(done.allSatisfy { $0.visibility.isVisible })
        let off = SpoilerShield.segments(raw, context: ctx(0), policy: SpoilerPolicy(level: .off))
        XCTAssertTrue(off.allSatisfy { $0.visibility.isVisible })
        let unlocked = SpoilerShield.segments(raw, context: ctx(0), policy: SpoilerPolicy(level: .strict, unlockedMediaIds: [1]))
        XCTAssertTrue(unlocked.allSatisfy { $0.visibility.isVisible })
    }

    func testEpisodesBeyondProgressAreHidden() {
        XCTAssertTrue(SpoilerShield.episode(5, context: ctx(4), policy: SpoilerPolicy()).isVisible)
        XCTAssertFalse(SpoilerShield.episode(6, context: ctx(4), policy: SpoilerPolicy()).isVisible)
        XCTAssertTrue(SpoilerShield.episode(20, context: ctx(4), policy: SpoilerPolicy(level: .relaxed)).isVisible)
    }

    func testTagsAndCharacters() {
        let tags = [MediaTag(id: 1, name: "Time Loop", rank: 90, isMediaSpoiler: true), MediaTag(id: 2, name: "Magic", rank: 80)]
        let result = SpoilerShield.tags(tags, context: ctx(2), policy: SpoilerPolicy())
        XCTAssertEqual(result.visible.map(\.name), ["Magic"])
        XCTAssertEqual(result.hiddenCount, 1)

        let late = SpoilerShield.character(role: .background, description: nil, index: 12, context: ctx(1), policy: SpoilerPolicy())
        XCTAssertFalse(late.showCard.isVisible)
        let main = SpoilerShield.character(role: .main, description: "~!secret!~", index: 0, context: ctx(1), policy: SpoilerPolicy())
        XCTAssertTrue(main.showCard.isVisible)
        XCTAssertFalse(main.showDescription.isVisible)
    }

    func testSequelsHiddenUntilFinished() {
        XCTAssertFalse(SpoilerShield.relation(.sequel, base: ctx(5), policy: SpoilerPolicy()).isVisible)
        XCTAssertTrue(SpoilerShield.relation(.sequel, base: ctx(24, .completed), policy: SpoilerPolicy()).isVisible)
        XCTAssertTrue(SpoilerShield.relation(.source, base: ctx(5), policy: SpoilerPolicy()).isVisible)
    }

    func testRecommendationOfLaterSeasonNeedsFranchiseStarted() {
        let s3 = makeMedia(3, "Mystery Show Season 3")
        XCTAssertFalse(SpoilerShield.isSafeRecommendation(s3, library: .empty, policy: SpoilerPolicy()))
        let lib = makeLibrary([makeEntry(makeMedia(2, "Mystery Show"), .current, progress: 4)])
        XCTAssertTrue(SpoilerShield.isSafeRecommendation(s3, library: lib, policy: SpoilerPolicy()))
    }

    func testSharedNotesRespectReaderProgress() {
        let note = SharedNote(author: "a", mediaId: 1, atProgress: 10, text: "wow")
        XCTAssertFalse(SpoilerShield.sharedNote(note, readerProgress: 4, readerFinished: false, policy: SpoilerPolicy()).isVisible)
        XCTAssertTrue(SpoilerShield.sharedNote(note, readerProgress: 10, readerFinished: false, policy: SpoilerPolicy()).isVisible)
    }
}

final class NaturalQueryParserTests: XCTestCase {
    let parser = NaturalQueryParser(now: utcDate(2026, 10, 1), calendar: utcCalendar)

    func testCompoundRequest() {
        let p = parser.parse("short cozy fantasy from the 2010s, no romance")
        XCTAssertEqual(p.query.moods, [.cozy])
        XCTAssertEqual(p.query.genresInclude, ["Fantasy"])
        XCTAssertEqual(p.query.genresExclude, ["Romance"])
        XCTAssertEqual(p.query.yearFrom, 2010)
        XCTAssertEqual(p.query.yearTo, 2019)
        XCTAssertTrue(p.chips.contains { $0.kind == .era && $0.label == "2010s" })
        XCTAssertTrue(p.chips.contains { $0.kind == .exclude })
    }

    func testLikeTitleWithMood() {
        let p = parser.parse("something like Frieren but darker")
        XCTAssertEqual(p.query.likeTitle, "frieren")
        XCTAssertEqual(p.query.moods, [.dark])
    }

    func testTimeBudget() {
        XCTAssertEqual(parser.parse("I have 3 hours, something funny").query.maxTotalMinutes, 180)
        XCTAssertEqual(parser.parse("anything for 90 minutes").query.maxTotalMinutes, 90)
    }

    func testHiddenGemMoviesAndManhwa() {
        let p = parser.parse("hidden gem sci-fi movies")
        XCTAssertEqual(p.query.formats, [.movie])
        XCTAssertEqual(p.query.genresInclude, ["Sci-Fi"])
        XCTAssertEqual(p.query.maxPopularity, 40_000)

        let m = parser.parse("manhwa with revenge")
        XCTAssertEqual(m.query.type, .manga)
        XCTAssertEqual(m.query.country, "KR")
        XCTAssertEqual(m.query.tagsInclude, ["Revenge"])
    }

    func testPlainTitleFallsBackToSearch() {
        let p = parser.parse("Monster")
        XCTAssertEqual(p.query.text, "Monster")
        XCTAssertTrue(p.chips.isEmpty)
    }

    func testLexiconMatchesAniListTaxonomy() throws {
        let taxonomy = try Fixture.decode(TaxonomyResponse.self, "tags")
        let tagNames = Set(taxonomy.MediaTagCollection.map(\.name))
        let genreNames = Set(taxonomy.GenreCollection)
        for (_, tag) in NaturalQueryParser.tagLexicon {
            XCTAssertTrue(tagNames.contains(tag), "Unknown AniList tag in lexicon: \(tag)")
        }
        for (_, genre) in NaturalQueryParser.genreLexicon {
            XCTAssertTrue(genreNames.contains(genre), "Unknown AniList genre in lexicon: \(genre)")
        }
        for mood in Mood.allCases {
            if let anchor = mood.anchorGenre { XCTAssertTrue(genreNames.contains(anchor)) }
            for tag in mood.signals.tags.keys { XCTAssertTrue(tagNames.contains(tag), "Unknown tag in \(mood) signals: \(tag)") }
            for g in mood.signals.genres.keys { XCTAssertTrue(genreNames.contains(g), "Unknown genre in \(mood) signals: \(g)") }
        }
    }

    func testDiscoveryRefineFiltersRuntimeAndRanksMood() {
        var q = DiscoveryQuery()
        q.maxTotalMinutes = 300
        q.moods = [.funny]
        let comedy = makeMedia(1, "Gag", episodes: 12, genres: ["Comedy"])
        let drama = makeMedia(2, "Sad", episodes: 12, genres: ["Drama"])
        let long = makeMedia(3, "Long", episodes: 50, genres: ["Comedy"])
        let refined = q.refine([drama, long, comedy])
        XCTAssertEqual(refined.map(\.id), [1, 2])
        XCTAssertEqual(q.preparedForServer().genresInclude, ["Comedy"])
    }
}

final class MoodTests: XCTestCase {
    func testVibeProfileReflectsGenres() {
        let cozy = VibeProfile.of(makeMedia(1, "Camp", genres: ["Slice of Life", "Comedy"], tags: [("Iyashikei", 90)]))
        let grim = VibeProfile.of(makeMedia(2, "Grim", genres: ["Horror", "Psychological"], tags: [("Gore", 80)]))
        XCTAssertGreaterThan(cozy.moodScore(.cozy), grim.moodScore(.cozy))
        XCTAssertGreaterThan(grim.moodScore(.dark), cozy.moodScore(.dark))
        XCTAssertGreaterThan(cozy.distance(to: grim), 0.5)
    }
}
