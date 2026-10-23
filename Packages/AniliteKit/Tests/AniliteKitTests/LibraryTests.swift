import XCTest
@testable import AniliteKit

final class MutationQueueTests: XCTestCase {
    func testSavesCoalescePerTitle() {
        var q = MutationQueue()
        q.enqueue(.save(EntryChange(mediaId: 1, progress: 3)))
        q.enqueue(.save(EntryChange(mediaId: 2, status: .planning)))
        q.enqueue(.save(EntryChange(mediaId: 1, progress: 4, score: 80)))
        XCTAssertEqual(q.count, 2)
        guard case .save(let merged)? = q.first else { return XCTFail() }
        XCTAssertEqual(merged.progress, 4)
        XCTAssertEqual(merged.score, 80)
    }

    func testDeleteSupersedesQueuedSaves() {
        var q = MutationQueue()
        q.enqueue(.save(EntryChange(mediaId: 1, progress: 3)))
        q.enqueue(.delete(mediaId: 1, remoteId: 99))
        XCTAssertEqual(q.items, [.delete(mediaId: 1, remoteId: 99)])
        q.removeFirst()
        XCTAssertTrue(q.isEmpty)
        q.removeFirst()
        XCTAssertTrue(q.isEmpty)
    }

    func testQueueSurvivesEncoding() throws {
        var q = MutationQueue()
        q.enqueue(.save(EntryChange(mediaId: 5, status: .completed, completedAt: FuzzyDate(year: 2024, month: 3, day: 2))))
        q.enqueue(.delete(mediaId: 6, remoteId: 7))
        let data = try JSONEncoder().encode(q)
        XCTAssertEqual(try JSONDecoder().decode(MutationQueue.self, from: data), q)
    }
}

final class LibraryReducerTests: XCTestCase {
    let show = makeMedia(1, "Show", episodes: 12)
    let now = utcDate(2024, 5, 10)

    func testStartingAndCompletingStampsDates() {
        var lib = Library.empty
        LibraryReducer.apply(EntryChange(mediaId: 1, status: .current, progress: 1), media: show, to: &lib, now: now, calendar: utcCalendar)
        XCTAssertEqual(lib.entry(for: 1)?.startedAt, FuzzyDate(year: 2024, month: 5, day: 10))
        LibraryReducer.apply(EntryChange(mediaId: 1, status: .completed), media: show, to: &lib, now: now, calendar: utcCalendar)
        XCTAssertEqual(lib.entry(for: 1)?.progress, 12)
        XCTAssertEqual(lib.entry(for: 1)?.completedAt, FuzzyDate(year: 2024, month: 5, day: 10))
    }

    func testClampsValuesAndIgnoresUnknownMedia() {
        var lib = Library.empty
        LibraryReducer.apply(EntryChange(mediaId: 1, progress: -4, score: 140), media: show, to: &lib, now: now)
        XCTAssertEqual(lib.entry(for: 1)?.progress, 0)
        XCTAssertEqual(lib.entry(for: 1)?.score, 100)
        LibraryReducer.apply(EntryChange(mediaId: 77, progress: 2), media: nil, to: &lib, now: now)
        XCTAssertNil(lib.entry(for: 77))
    }

    func testIncrementAutoStartsAndAutoCompletes() {
        let planned = makeEntry(show, .planning)
        XCTAssertEqual(LibraryReducer.increment(planned).status, .current)
        let last = makeEntry(show, .current, progress: 11)
        let change = LibraryReducer.increment(last)
        XCTAssertEqual(change.status, .completed)
        XCTAssertEqual(change.progress, 12)
        var rewatch = makeEntry(show, .repeating, progress: 11)
        rewatch.repeatCount = 1
        XCTAssertEqual(LibraryReducer.increment(rewatch).repeatCount, 2)

        let airing = makeMedia(2, "Airing", status: .releasing, episodes: 12)
        XCTAssertNil(LibraryReducer.increment(makeEntry(airing, .current, progress: 11)).status, "Airing shows don't auto-complete")
        XCTAssertEqual(LibraryReducer.increment(makeEntry(show, .current, progress: 0), by: -1).progress, 0)
    }

    func testRebaseReappliesPendingChanges() {
        let server = makeLibrary([makeEntry(show, .current, progress: 2), makeEntry(makeMedia(2, "Gone"), .planning)])
        var q = MutationQueue()
        q.enqueue(.save(EntryChange(mediaId: 1, progress: 5)))
        q.enqueue(.delete(mediaId: 2, remoteId: 1))
        let rebased = LibraryReducer.rebase(server: server, pending: q, now: now)
        XCTAssertEqual(rebased.entry(for: 1)?.progress, 5)
        XCTAssertNil(rebased.entry(for: 2))
    }

    func testScoreFormats() {
        XCTAssertEqual(ScoreFormat.point10.display(85), "9")
        XCTAssertEqual(ScoreFormat.point10Decimal.display(85), "8.5")
        XCTAssertEqual(ScoreFormat.point100.display(85), "85")
        XCTAssertEqual(ScoreFormat.point5.display(80), "★★★★")
        XCTAssertEqual(ScoreFormat.point3.display(90), "🙂")
        XCTAssertEqual(ScoreFormat.point10.display(0), "–")
    }
}

final class CollectionsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testBuiltInSmartShelves() {
        let almost = makeEntry(makeMedia(1, "Almost", episodes: 12, duration: 24), .current, progress: 10, updated: now)
        let dusty = makeEntry(makeMedia(2, "Dusty", episodes: 24), .paused, progress: 3, updated: now.addingTimeInterval(-60 * 86_400))
        let fame = makeEntry(makeMedia(3, "Fame"), .completed, score: 95)
        let lib = makeLibrary([almost, dusty, fame])
        func shelf(_ name: String) -> [Int] {
            Shelf.builtIns.first { $0.name == name }!.rule!.apply(to: lib, now: now).map(\.mediaId)
        }
        XCTAssertEqual(shelf("Almost Done"), [1])
        XCTAssertEqual(shelf("Gathering Dust"), [2])
        XCTAssertEqual(shelf("Hall of Fame"), [3])
        let manual = Shelf(name: "Mine", mediaIds: [3, 1, 404])
        XCTAssertEqual(manual.entries(in: lib).map(\.mediaId), [3, 1])
    }

    func testAchievements() {
        let jp = makeEntry(makeMedia(1, "One", episodes: 120, year: 1998, genres: ["Action"]), .completed,
                           completedAt: FuzzyDate(year: 2024, month: 2, day: 1), startedAt: FuzzyDate(year: 2022, month: 1, day: 1))
        let achievements = Achievements.evaluate(library: makeLibrary([jp]))
        func a(_ id: String) -> Achievement { achievements.first { $0.id == id }! }
        XCTAssertTrue(a("first").isUnlocked)
        XCTAssertTrue(a("marathon").isUnlocked)
        XCTAssertTrue(a("revive").isUnlocked)
        XCTAssertFalse(a("anime25").isUnlocked)
        XCTAssertEqual(a("anime25").progress, 1.0 / 25, accuracy: 0.0001)
        XCTAssertTrue(Achievements.evaluate(library: .empty).allSatisfy { !$0.isUnlocked })
    }

    func testYearRecap() {
        let a = makeEntry(makeMedia(1, "A", episodes: 12, duration: 24, genres: ["Drama"]), .completed, score: 90, completedAt: FuzzyDate(year: 2025, month: 3, day: 2))
        let b = makeEntry(makeMedia(2, "B", episodes: 24, duration: 24, genres: ["Drama", "Comedy"]), .completed, score: 70, completedAt: FuzzyDate(year: 2025, month: 8, day: 9))
        let old = makeEntry(makeMedia(3, "Old"), .completed, completedAt: FuzzyDate(year: 2019, month: 1, day: 1))
        let recap = YearRecap.build(year: 2025, library: makeLibrary([a, b, old]), calendar: utcCalendar)
        XCTAssertEqual(Set(recap.completedAnime.map(\.mediaId)), [1, 2])
        XCTAssertEqual(recap.topGenres.first?.0, "Drama")
        XCTAssertEqual(recap.topRated.first?.mediaId, 1)
        XCTAssertEqual(recap.firstFinish?.mediaId, 1)
        XCTAssertGreaterThanOrEqual(recap.minutes, 36 * 24)
        XCTAssertEqual(recap.monthlyMinutes.count, 12)
        XCTAssertTrue(YearRecap.build(year: 2001, library: makeLibrary([a]), calendar: utcCalendar).isEmpty)
    }

    func testPersistentStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anilite-store-\(UUID().uuidString)")
        let store = PersistentStore(directory: dir)
        defer { store.removeAll() }
        let journal = [JournalEntry(mediaId: 1, mediaTitle: "Show", unit: 3, text: "Wow", feeling: .hyped, createdAt: now)]
        try store.save(journal, key: "journal")
        XCTAssertEqual(store.load([JournalEntry].self, key: "journal"), journal)
        store.remove(key: "journal")
        XCTAssertNil(store.load([JournalEntry].self, key: "journal"))
        XCTAssertNil(store.load([JournalEntry].self, key: "missing"))
    }
}

final class SharingTests: XCTestCase {
    func testDeepLinks() throws {
        let auth = DeepLink.parse(URL(string: "anilite://auth-callback#access_token=abc&token_type=Bearer&expires_in=31536000")!)
        XCTAssertEqual(auth, .auth(token: "abc", expiresIn: 31_536_000, error: nil))
        let denied = DeepLink.parse(URL(string: "anilite://auth-callback?error=access_denied")!)
        if case .auth(let token, _, let error)? = denied {
            XCTAssertNil(token)
            XCTAssertEqual(error, "access_denied")
        } else { XCTFail("Expected auth link") }
        XCTAssertEqual(DeepLink.parse(URL(string: "anilite://media/154587")!), .media(id: 154587))
        XCTAssertEqual(DeepLink.parse(URL(string: "anilite://media?id=5")!), .media(id: 5))
        XCTAssertEqual(DeepLink.parse(URL(string: "anilite://user/Josh")!), .user(name: "Josh"))
        XCTAssertNil(DeepLink.parse(URL(string: "https://example.com/media/1")!))
        XCTAssertNil(DeepLink.parse(URL(string: "anilite://list?d=not-base64!")!))
    }

    func testSharedListStripsSpoilersAndRoundTrips() throws {
        let entries = (1...70).map { makeEntry(makeMedia($0, "Show \($0)"), .completed) }
        let list = SharedList.from(title: "Faves", curator: "me", entries: entries,
                                   notes: [1: "Great start. ~!The mentor dies.!~", 2: "~!only spoilers!~"])
        XCTAssertEqual(list.items.count, 60)
        XCTAssertEqual(list.items[0].note, "Great start.")
        XCTAssertNil(list.items[1].note)
        XCTAssertTrue(list.code.hasPrefix("LIST-"))
        let decoded = try XCTUnwrap(ShareCodec.decode(SharedList.self, from: list.code, prefix: SharedList.prefix))
        XCTAssertEqual(decoded, list)
        let link = try XCTUnwrap(list.link)
        XCTAssertEqual(DeepLink.parse(link), .sharedList(list))
        // A full link pasted in place of a code still decodes.
        XCTAssertEqual(ShareCodec.decode(SharedList.self, from: link.absoluteString, prefix: SharedList.prefix), list)
        XCTAssertNil(ShareCodec.decode(SharedList.self, from: list.code, prefix: Club.prefix))
    }

    func testFingerprintLink() throws {
        let dna = TasteDNA.build(from: [makeEntry(makeMedia(1, "A", genres: ["Drama"]), .completed, score: 90)])
        let fp = TasteFingerprint(name: "Me", dna: dna)
        let link = try XCTUnwrap(ShareCodec.link(kind: "dna", code: fp.code))
        XCTAssertEqual(DeepLink.parse(link), .fingerprint(fp))
    }
}
