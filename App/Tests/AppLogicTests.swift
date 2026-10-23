import XCTest
import SwiftUI
import AniliteKit
@testable import Anilite

private func anime(_ id: Int, title: String, episodes: Int? = 12, next: (episode: Int, at: Date)? = nil) -> Media {
    var media = Media(id: id, type: .anime, episodes: episodes, duration: 24, title: MediaTitle(romaji: title, english: title))
    if let next {
        media.nextAiringEpisode = NextAiringEpisode(airingAt: Int(next.at.timeIntervalSince1970), episode: next.episode)
    }
    return media
}

private func library(_ entries: [LibraryEntry]) -> Library {
    Library(entries: Dictionary(uniqueKeysWithValues: entries.map { ($0.mediaId, $0) }), isReadOnly: false)
}

final class AiringReminderPlanTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLeadMinutesShiftFireDateAfterAiring() {
        let airs = now.addingTimeInterval(3_600)
        let lib = library([LibraryEntry(media: anime(1, title: "Frieren", next: (5, airs)), status: .current, progress: 4)])
        let plans = AiringReminders.plan(library: lib, language: .english, leadMinutes: 30, now: now)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].fireDate, airs.addingTimeInterval(30 * 60))
        XCTAssertEqual(plans[0].id, "airing-1-5")
        XCTAssertTrue(plans[0].body.contains("caught up"))
    }

    func testSkipsPastEpisodesMangaAndInactiveEntries() {
        let past = now.addingTimeInterval(-60)
        let future = now.addingTimeInterval(600)
        var manga = Media(id: 3, type: .manga, format: .manga, chapters: 100, title: MediaTitle(english: "Manga"))
        manga.nextAiringEpisode = NextAiringEpisode(airingAt: Int(future.timeIntervalSince1970), episode: 2)
        let lib = library([
            LibraryEntry(media: anime(1, title: "Aired", next: (2, past)), status: .current, progress: 1),
            LibraryEntry(media: anime(2, title: "Dropped", next: (2, future)), status: .dropped, progress: 1),
            LibraryEntry(media: manga, status: .current, progress: 1),
            LibraryEntry(media: anime(4, title: "Planned", next: (1, future)), status: .planning)
        ])
        let plans = AiringReminders.plan(library: lib, language: .english, leadMinutes: 0, now: now)
        XCTAssertEqual(plans.map(\.mediaId), [4])
        XCTAssertTrue(plans[0].body.contains("plan list"))
    }

    func testBehindCountAndSorting() {
        let lib = library([
            LibraryEntry(media: anime(1, title: "Later", next: (10, now.addingTimeInterval(7_200))), status: .current, progress: 6),
            LibraryEntry(media: anime(2, title: "Sooner", next: (3, now.addingTimeInterval(600))), status: .current, progress: 2)
        ])
        let plans = AiringReminders.plan(library: lib, language: .english, leadMinutes: 0, now: now)
        XCTAssertEqual(plans.map(\.mediaId), [2, 1])
        XCTAssertTrue(plans[1].body.contains("3 behind"), plans[1].body)
    }

    func testCapsPendingNotifications() {
        let entries = (1...80).map { id in
            LibraryEntry(media: anime(id, title: "Show \(id)", next: (2, now.addingTimeInterval(Double(id) * 60))), status: .current, progress: 1)
        }
        let plans = AiringReminders.plan(library: library(entries), language: .english, leadMinutes: 0, now: now)
        XCTAssertEqual(plans.count, AiringReminders.maxPending)
        XCTAssertEqual(plans.first?.mediaId, 1)
    }
}

final class AppSettingsTests: XCTestCase {
    func testDecodingFillsMissingKeysWithDefaults() throws {
        let json = Data(#"{"haptics": false, "tonightMinutes": 120}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.haptics)
        XCTAssertEqual(settings.tonightMinutes, 120)
        XCTAssertEqual(settings.titleLanguage, AppSettings().titleLanguage)
        XCTAssertEqual(settings.spoilerLevel, AppSettings().spoilerLevel)
        XCTAssertFalse(settings.hasOnboarded)
    }

    func testDecodingSurvivesWrongTypes() throws {
        let json = Data(#"{"haptics": "yes", "reminderLeadMinutes": 15}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.haptics)
        XCTAssertEqual(settings.reminderLeadMinutes, 15)
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.regionOverride = "GB"
        settings.airingReminders = true
        settings.hasOnboarded = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.region, "GB")
    }
}

final class TextFormattingTests: XCTestCase {
    func testClubStanding() {
        XCTAssertEqual(ClubText.standing(.onTrack, unit: "episodes"), "On track")
        XCTAssertEqual(ClubText.standing(.ahead(2), unit: "episodes"), "2 episodes ahead")
        XCTAssertEqual(ClubText.standing(.behind(3), unit: "chapters"), "3 chapters behind")
    }

    func testClubWeekdaysAreSortedAndValidated() {
        let symbols = Calendar.current.shortWeekdaySymbols
        XCTAssertEqual(ClubText.weekdays([7, 1, 9]), "\(symbols[0]), \(symbols[6])")
        XCTAssertEqual(ClubText.weekdays([]), "")
    }

    func testLibraryProgressText() {
        let watching = LibraryEntry(media: anime(1, title: "A", episodes: 24), status: .current, progress: 5, score: 85)
        let text = LibraryText.progress(watching)
        XCTAssertTrue(text.hasPrefix(MediaListStatus.current.label(for: .anime)))
        XCTAssertTrue(text.contains("Ep 5/24"), text)
        XCTAssertTrue(text.contains("★ 8.5"), text)

        let planning = LibraryEntry(media: anime(2, title: "B"), status: .planning)
        XCTAssertEqual(LibraryText.progress(planning), MediaListStatus.planning.label(for: .anime))
    }

    func testSmartShelfDescription() {
        let rule = SmartRule(type: .anime, statuses: [.planning], genres: ["Drama"], maxRemainingMinutes: 120)
        let text = ShelfView.describe(rule)
        XCTAssertTrue(text.hasPrefix("Smart shelf: Anime"), text)
        XCTAssertTrue(text.contains("Drama"))
        XCTAssertTrue(text.contains("under 2h left"), text)
    }
}

@MainActor
final class RouterTests: XCTestCase {
    func testPushSwitchesToTargetTab() {
        let router = Router()
        router.push(.settings, on: .you)
        XCTAssertEqual(router.tab, .you)
        XCTAssertEqual(router.paths[.you]?.count, 1)
        router.push(.glossary)
        XCTAssertEqual(router.paths[.you]?.count, 2)
    }

    func testSearchHandsQueryToFindAndResetsIt() {
        let router = Router()
        router.push(.glossary, on: .find)
        router.select(.discover)
        router.search("cozy fantasy")
        XCTAssertEqual(router.tab, .find)
        XCTAssertEqual(router.pendingSearch, "cozy fantasy")
        XCTAssertEqual(router.paths[.find]?.count, 0)
    }

    func testReselectingTabPopsToRoot() {
        let router = Router()
        router.push(.settings, on: .discover)
        router.select(.discover)
        XCTAssertEqual(router.paths[.discover]?.count, 0)
    }
}
