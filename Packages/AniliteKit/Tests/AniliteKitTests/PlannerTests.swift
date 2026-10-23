import XCTest
@testable import AniliteKit

final class PlannerTests: XCTestCase {
    let start = utcDate(2024, 1, 1, 0)

    func testSequentialPlanRespectsDailyBudget() {
        let item = PlanItem(mediaId: 1, title: "Show", minutesPerUnit: 24, units: 3)
        let plan = BingePlanner.plan([item], budget: WeeklyBudget(minutes: Array(repeating: 60, count: 7)), start: start, calendar: utcCalendar)
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertEqual(plan.days[0].sessions.first?.units, 1...2)
        XCTAssertEqual(plan.days[1].sessions.first?.units, 3...3)
        XCTAssertTrue(plan.days.allSatisfy { $0.used <= $0.budget })
        XCTAssertEqual(plan.finishDate, utcDate(2024, 1, 2, 0))
        XCTAssertEqual(plan.totalMinutes, 72)
    }

    func testInterleavedSplitsTheEvening() {
        let a = PlanItem(mediaId: 1, title: "A", minutesPerUnit: 24, units: 6)
        let b = PlanItem(mediaId: 2, title: "B", minutesPerUnit: 24, units: 6)
        let plan = BingePlanner.plan([a, b], budget: WeeklyBudget(minutes: Array(repeating: 100, count: 7)), strategy: .interleaved,
                                     start: start, calendar: utcCalendar)
        XCTAssertEqual(Set(plan.days[0].sessions.map(\.mediaId)), [1, 2])
        XCTAssertTrue(plan.unfinished.isEmpty)
    }

    func testNeverSchedulesBeforeAiring() {
        let day2 = Int(utcDate(2024, 1, 3, 10).timeIntervalSince1970)
        let day3 = Int(utcDate(2024, 1, 4, 10).timeIntervalSince1970)
        let item = PlanItem(mediaId: 1, title: "Airing", minutesPerUnit: 24, units: 2, startUnit: 5, availability: [5: day2, 6: day3])
        let plan = BingePlanner.plan([item], budget: WeeklyBudget(minutes: Array(repeating: 200, count: 7)), start: start, calendar: utcCalendar)
        XCTAssertEqual(plan.finishDates[1], utcDate(2024, 1, 4, 0))
        XCTAssertTrue(plan.days[0].sessions.isEmpty)
        XCTAssertEqual(plan.activeDays.count, 2)
    }

    func testQuickWinsPutsShortestFirst() {
        let long = PlanItem(mediaId: 1, title: "Long", minutesPerUnit: 24, units: 24)
        let film = PlanItem(mediaId: 2, title: "Film", minutesPerUnit: 100, units: 1)
        let plan = BingePlanner.plan([long, film], budget: WeeklyBudget(minutes: Array(repeating: 120, count: 7)), strategy: .quickWins,
                                     start: start, calendar: utcCalendar)
        XCTAssertEqual(plan.days[0].sessions.first?.mediaId, 2)
    }

    func testUnitTooLongForAnyDayStaysUnfinished() {
        let film = PlanItem(mediaId: 1, title: "Epic", minutesPerUnit: 200, units: 1)
        let plan = BingePlanner.plan([film], budget: WeeklyBudget(minutes: Array(repeating: 60, count: 7)), start: start, horizonDays: 14, calendar: utcCalendar)
        XCTAssertEqual(plan.unfinished, [1])
        XCTAssertNil(plan.finishDate)
    }

    func testForecastAndBacklog() {
        let show = makeMedia(1, "Show", episodes: 12, duration: 24)
        let entry = makeEntry(show, .current, progress: 2)
        let pace = PaceEstimate(unitsPerDay: 2.5, minutesPerDay: 60, sampleDays: 30)
        let f = Forecast.make(for: entry, pace: pace, now: start)
        XCTAssertEqual(f.remainingMinutes, 240)
        XCTAssertEqual(f.days, 4)
        let backlog = Forecast.backlog(makeLibrary([entry, makeEntry(makeMedia(2, "Other", episodes: 5), .planning)]), pace: pace)
        XCTAssertEqual(backlog.minutes, 240 + 120)
        XCTAssertEqual(backlog.days, 6)
    }

    func testPaceFromActivitiesFixture() throws {
        let page = try Fixture.decode(ActivityResponse.self, "activity")
        XCTAssertFalse(page.Page.activities.isEmpty)
        let latest = page.Page.activities.map(\.createdAt).max()!
        let pace = PaceEstimate.from(activities: page.Page.activities, now: Date(timeIntervalSince1970: TimeInterval(latest)))
        XCTAssertGreaterThan(pace.unitsPerDay, 0)
        XCTAssertGreaterThanOrEqual(pace.sampleDays, 7)
        XCTAssertEqual(PaceEstimate.from(activities: [], now: start), .fallback)
    }

    func testAiringCalendarFromFixture() throws {
        let response = try Fixture.decode(AiringResponse.self, "airing")
        let schedules = response.Page.airingSchedules
        XCTAssertFalse(schedules.isEmpty)
        let tracked = try XCTUnwrap(schedules.first?.media)
        let library = makeLibrary([makeEntry(tracked, .current, progress: max(0, schedules[0].episode - 1))])
        let days = AiringCalendar.group(schedules, library: library, calendar: utcCalendar)
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days.map(\.date), days.map(\.date).sorted())
        let first = try XCTUnwrap(days.first { $0.slots.contains { $0.media.id == tracked.id } })
        XCTAssertEqual(first.slots.first?.media.id, tracked.id, "Library titles sort first")
        XCTAssertTrue(first.slots.first?.isCaughtUp ?? false)
        let mine = AiringCalendar.group(schedules, library: library, onlyLibrary: true, calendar: utcCalendar)
        XCTAssertTrue(mine.flatMap(\.slots).allSatisfy(\.isInLibrary))
    }

    func testTonightPicks() {
        let nearlyDone = makeEntry(makeMedia(1, "Nearly", episodes: 12, duration: 24), .current, progress: 10)
        let longRun = makeEntry(makeMedia(2, "Long", episodes: 50, duration: 24), .current, progress: 3)
        let film = ScoredMedia(media: makeMedia(3, "Film", format: .movie, episodes: 1, duration: 95), score: 0.8, reasons: [], isHiddenGem: false)
        let picks = TonightPicker.picks(minutes: 100, library: makeLibrary([nearlyDone, longRun]), fresh: [film])
        XCTAssertEqual(picks.first { $0.media.id == 1 }?.kind, .finishIt)
        XCTAssertEqual(picks.first { $0.media.id == 2 }?.units, 4)
        XCTAssertEqual(picks.first { $0.media.id == 3 }?.kind, .film)
        XCTAssertTrue(picks.allSatisfy { $0.minutes <= 100 })
        XCTAssertTrue(TonightPicker.picks(minutes: 0, library: .empty, fresh: [film]).isEmpty)
    }
}

final class ClubTests: XCTestCase {
    func club() -> Club {
        Club(name: "Saturday Club", mediaId: 1, mediaTitle: "Show", mediaType: .anime, totalUnits: 12, unitsPerSession: 3,
             weekdays: [7], startDate: utcDate(2024, 1, 1, 0), host: "me")
    }

    func testScheduleAndStanding() {
        let sessions = club().schedule(calendar: utcCalendar)
        XCTAssertEqual(sessions.map(\.date), [utcDate(2024, 1, 6, 0), utcDate(2024, 1, 13, 0), utcDate(2024, 1, 20, 0), utcDate(2024, 1, 27, 0)])
        XCTAssertEqual(sessions.last?.units, 10...12)
        XCTAssertEqual(club().expectedProgress(on: utcDate(2024, 1, 14), calendar: utcCalendar), 6)
        XCTAssertEqual(club().standing(progress: 4, on: utcDate(2024, 1, 14), calendar: utcCalendar), .behind(2))
        XCTAssertEqual(club().standing(progress: 9, on: utcDate(2024, 1, 14), calendar: utcCalendar), .ahead(3))
        XCTAssertEqual(club().standing(progress: 6, on: utcDate(2024, 1, 14), calendar: utcCalendar), .onTrack)
        XCTAssertEqual(club().nextSession(after: utcDate(2024, 1, 14), calendar: utcCalendar)?.index, 2)
    }

    func testClubRoundTripsThroughLink() throws {
        let c = club()
        let link = try XCTUnwrap(c.link)
        guard case .club(let decoded)? = DeepLink.parse(link) else { return XCTFail("Expected club link") }
        XCTAssertEqual(decoded, c)
    }
}
