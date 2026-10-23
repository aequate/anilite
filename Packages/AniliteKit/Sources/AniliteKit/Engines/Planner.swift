import Foundation

/// How much time the viewer has on each weekday.
public struct WeeklyBudget: Codable, Hashable, Sendable {
    /// Minutes per weekday, index 0 = Sunday … 6 = Saturday.
    public var minutes: [Int]

    public init(minutes: [Int]) {
        var m = Array(minutes.prefix(7))
        while m.count < 7 { m.append(0) }
        self.minutes = m.map { max(0, $0) }
    }

    public static let standard = WeeklyBudget(minutes: [120, 45, 45, 45, 45, 60, 150])

    public func minutes(on date: Date, calendar: Calendar = .current) -> Int {
        minutes[calendar.component(.weekday, from: date) - 1]
    }

    public var weeklyTotal: Int { minutes.reduce(0, +) }
}

public struct PlanItem: Codable, Hashable, Sendable, Identifiable {
    public var mediaId: Int
    public var title: String
    public var minutesPerUnit: Int
    /// Units still to watch/read.
    public var units: Int
    /// First unit number to start from.
    public var startUnit: Int
    /// For airing shows: unit number → unix time it becomes available.
    public var availability: [Int: Int]
    public var id: Int { mediaId }

    public init(mediaId: Int, title: String, minutesPerUnit: Int, units: Int, startUnit: Int = 1, availability: [Int: Int] = [:]) {
        self.mediaId = mediaId
        self.title = title
        self.minutesPerUnit = max(1, minutesPerUnit)
        self.units = max(0, units)
        self.startUnit = max(1, startUnit)
        self.availability = availability
    }

    public init(entry: LibraryEntry, schedule: [AiringNode] = []) {
        let media = entry.media
        let total = media.totalUnits ?? max(entry.progress + 12, media.releasedUnits ?? 0)
        var available: [Int: Int] = [:]
        for node in schedule where node.episode > entry.progress { available[node.episode] = node.airingAt }
        self.init(mediaId: media.id, title: media.titleText, minutesPerUnit: media.minutesPerUnit,
                  units: max(0, total - entry.progress), startUnit: entry.progress + 1, availability: available)
    }

    public init(media: Media, startUnit: Int = 1, schedule: [AiringNode] = []) {
        let total = media.totalUnits ?? media.releasedUnits ?? 12
        var available: [Int: Int] = [:]
        for node in schedule where node.episode >= startUnit { available[node.episode] = node.airingAt }
        self.init(mediaId: media.id, title: media.titleText, minutesPerUnit: media.minutesPerUnit,
                  units: max(0, total - startUnit + 1), startUnit: startUnit, availability: available)
    }
}

public struct PlanSession: Hashable, Sendable, Identifiable {
    public var mediaId: Int
    public var title: String
    public var units: ClosedRange<Int>
    public var minutes: Int
    public var id: String { "\(mediaId)-\(units.lowerBound)" }
}

public struct PlanDay: Hashable, Sendable, Identifiable {
    public var date: Date
    public var sessions: [PlanSession]
    public var budget: Int
    public var used: Int { sessions.reduce(0) { $0 + $1.minutes } }
    public var id: Date { date }
}

public struct BingePlan: Hashable, Sendable {
    public var days: [PlanDay]
    /// When each title is finished.
    public var finishDates: [Int: Date]
    /// Titles that couldn't be finished inside the horizon.
    public var unfinished: [Int]
    public var totalMinutes: Int

    public var activeDays: [PlanDay] { days.filter { !$0.sessions.isEmpty } }
    public var finishDate: Date? { unfinished.isEmpty ? finishDates.values.max() : nil }
}

public enum PlanStrategy: String, CaseIterable, Codable, Sendable {
    /// Finish one title at a time, in the given order.
    case sequential
    /// Rotate between titles each day for variety.
    case interleaved
    /// Shortest titles first — clears the backlog count fastest.
    case quickWins

    public var label: String {
        switch self {
        case .sequential: return "One at a time"
        case .interleaved: return "Mix it up"
        case .quickWins: return "Quick wins first"
        }
    }
}

public enum BingePlanner {
    /// Greedy day-by-day scheduler. Never schedules an episode before it airs and never
    /// splits a unit across days (a 2h film needs a 2h evening).
    public static func plan(_ items: [PlanItem], budget: WeeklyBudget, strategy: PlanStrategy = .sequential,
                            start: Date, horizonDays: Int = 365, calendar: Calendar = .current) -> BingePlan {
        var queue = items.filter { $0.units > 0 }
        if strategy == .quickWins { queue.sort { $0.units * $0.minutesPerUnit < $1.units * $1.minutesPerUnit } }
        var nextUnit = Dictionary(uniqueKeysWithValues: queue.map { ($0.mediaId, $0.startUnit) })
        let lastUnit = Dictionary(uniqueKeysWithValues: queue.map { ($0.mediaId, $0.startUnit + $0.units - 1) })
        var finish: [Int: Date] = [:]
        var days: [PlanDay] = []
        var day = calendar.startOfDay(for: start)
        var rotation = 0

        func isDone(_ item: PlanItem) -> Bool { nextUnit[item.mediaId, default: 0] > lastUnit[item.mediaId, default: 0] }

        for _ in 0..<horizonDays {
            if queue.allSatisfy(isDone) { break }
            let dayBudget = budget.minutes(on: day, calendar: calendar)
            var remaining = dayBudget
            var sessions: [PlanSession] = []
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { break }

            var order = queue.indices.map { $0 }
            if strategy == .interleaved, !order.isEmpty {
                let shift = rotation % order.count
                order = Array(order[shift...] + order[..<shift])
                rotation += 1
            }

            var progressed = true
            while remaining > 0 && progressed {
                progressed = false
                for index in order {
                    let item = queue[index]
                    guard !isDone(item) else { continue }
                    var u = nextUnit[item.mediaId]!
                    let first = u
                    var used = 0
                    while u <= lastUnit[item.mediaId]!, item.minutesPerUnit <= remaining - used {
                        if let airs = item.availability[u], Double(airs) >= dayEnd.timeIntervalSince1970 { break }
                        used += item.minutesPerUnit
                        u += 1
                        if strategy == .interleaved && u - first >= 3 { break }
                    }
                    if u > first {
                        if let i = sessions.lastIndex(where: { $0.mediaId == item.mediaId && $0.units.upperBound == first - 1 }) {
                            sessions[i].units = sessions[i].units.lowerBound...(u - 1)
                            sessions[i].minutes += used
                        } else {
                            sessions.append(PlanSession(mediaId: item.mediaId, title: item.title, units: first...(u - 1), minutes: used))
                        }
                        nextUnit[item.mediaId] = u
                        remaining -= used
                        progressed = true
                        if isDone(item) { finish[item.mediaId] = day }
                    }
                    if strategy == .sequential && !isDone(item) { break }
                    if remaining <= 0 { break }
                }
                if strategy == .sequential { break }
            }
            days.append(PlanDay(date: day, sessions: sessions, budget: dayBudget))
            day = dayEnd
        }
        let unfinished = queue.filter { !isDone($0) }.map(\.mediaId)
        let total = items.reduce(0) { $0 + $1.units * $1.minutesPerUnit }
        return BingePlan(days: days, finishDates: finish, unfinished: unfinished, totalMinutes: total)
    }
}

// MARK: - Pace & forecast

public struct PaceEstimate: Hashable, Sendable {
    /// Units per day the viewer typically gets through (averaged over active stretch).
    public var unitsPerDay: Double
    public var minutesPerDay: Double
    public var sampleDays: Int

    public static let fallback = PaceEstimate(unitsPerDay: 1.5, minutesPerDay: 40, sampleDays: 0)

    /// Builds a pace from AniList list activities (each covers one or more units).
    public static func from(activities: [ListActivity], now: Date = Date(), windowDays: Int = 60) -> PaceEstimate {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let recent = activities.filter { Date(timeIntervalSince1970: TimeInterval($0.createdAt)) >= cutoff }
        guard !recent.isEmpty else { return .fallback }
        var units = 0.0, minutes = 0.0
        for a in recent {
            let count = Double(a.unitsCovered)
            units += count
            minutes += count * Double(a.media?.minutesPerUnit ?? 24)
        }
        let first = recent.map(\.createdAt).min() ?? Int(now.timeIntervalSince1970)
        let span = max(7, Int(now.timeIntervalSince1970 - TimeInterval(first)) / 86_400)
        return PaceEstimate(unitsPerDay: units / Double(span), minutesPerDay: minutes / Double(span), sampleDays: span)
    }
}

public struct Forecast: Hashable, Sendable {
    public var mediaId: Int
    public var remainingMinutes: Int
    public var finishDate: Date?
    public var days: Int?

    public static func make(for entry: LibraryEntry, pace: PaceEstimate, now: Date = Date()) -> Forecast {
        let remaining = entry.remainingMinutes ?? 0
        guard remaining > 0, pace.minutesPerDay > 0 else {
            return Forecast(mediaId: entry.mediaId, remainingMinutes: remaining, finishDate: remaining == 0 ? now : nil, days: remaining == 0 ? 0 : nil)
        }
        let days = Int((Double(remaining) / pace.minutesPerDay).rounded(.up))
        return Forecast(mediaId: entry.mediaId, remainingMinutes: remaining, finishDate: now.addingTimeInterval(Double(days) * 86_400), days: days)
    }

    /// Time to clear the whole planning + watching backlog at the current pace.
    public static func backlog(_ library: Library, pace: PaceEstimate) -> (minutes: Int, days: Int?) {
        let minutes = library.all
            .filter { $0.status == .planning || $0.status == .current || $0.status == .paused }
            .reduce(0) { $0 + ($1.remainingMinutes ?? 0) }
        guard pace.minutesPerDay > 0 else { return (minutes, nil) }
        return (minutes, Int((Double(minutes) / pace.minutesPerDay).rounded(.up)))
    }
}

// MARK: - Airing calendar

public struct AiringSlot: Hashable, Sendable, Identifiable {
    public var media: Media
    public var episode: Int
    public var airingAt: Date
    public var isInLibrary: Bool
    /// Viewer has seen every released episode — this is the next one they'll watch.
    public var isCaughtUp: Bool
    public var id: String { "\(media.id)-\(episode)" }
}

public struct AiringDay: Hashable, Sendable, Identifiable {
    public var date: Date
    public var slots: [AiringSlot]
    public var id: Date { date }
}

public enum AiringCalendar {
    public static func group(_ schedules: [AiringSchedule], library: Library, onlyLibrary: Bool = false, calendar: Calendar = .current) -> [AiringDay] {
        var byDay: [Date: [AiringSlot]] = [:]
        var seen = Set<String>()
        for s in schedules {
            guard let media = s.media, !(media.isAdult ?? false) else { continue }
            let entry = library.entry(for: media.id)
            if onlyLibrary && entry == nil { continue }
            let slot = AiringSlot(
                media: media, episode: s.episode, airingAt: Date(timeIntervalSince1970: TimeInterval(s.airingAt)),
                isInLibrary: entry != nil, isCaughtUp: entry.map { $0.progress >= s.episode - 1 } ?? false
            )
            guard seen.insert(slot.id).inserted else { continue }
            byDay[calendar.startOfDay(for: slot.airingAt), default: []].append(slot)
        }
        return byDay.keys.sorted().map { day in
            AiringDay(date: day, slots: byDay[day]!.sorted {
                if $0.isInLibrary != $1.isInLibrary { return $0.isInLibrary }
                return $0.airingAt == $1.airingAt ? ($0.media.popularity ?? 0) > ($1.media.popularity ?? 0) : $0.airingAt < $1.airingAt
            })
        }
    }
}

// MARK: - Tonight

public struct TonightPick: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case continueWatching, finishIt, startFresh, film }
    public var media: Media
    public var kind: Kind
    public var units: Int
    public var minutes: Int
    public var reason: String
    public var id: Int { media.id }
}

/// "I have 90 minutes — what should I do with them?"
public enum TonightPicker {
    public static func picks(minutes budget: Int, library: Library, fresh: [ScoredMedia], limit: Int = 6) -> [TonightPick] {
        guard budget > 0 else { return [] }
        var picks: [TonightPick] = []

        for entry in library.all where entry.status == .current || entry.status == .repeating {
            guard let remaining = entry.remainingUnits, remaining > 0 else { continue }
            let per = entry.media.minutesPerUnit
            let fit = min(remaining, budget / per)
            guard fit > 0 else { continue }
            if fit == remaining {
                picks.append(TonightPick(media: entry.media, kind: .finishIt, units: fit, minutes: fit * per,
                                         reason: "Finish it tonight — \(fit) \(entry.media.unitName)\(fit == 1 ? "" : "s") left"))
            } else {
                picks.append(TonightPick(media: entry.media, kind: .continueWatching, units: fit, minutes: fit * per,
                                         reason: "\(entry.media.unitShort) \(entry.progress + 1)–\(entry.progress + fit) fits your time"))
            }
        }

        for rec in fresh {
            let media = rec.media
            if media.format == .movie, let total = media.totalMinutes, total <= budget {
                picks.append(TonightPick(media: media, kind: .film, units: 1, minutes: total, reason: "A complete film in \(Formatting.duration(minutes: total))"))
            } else if let total = media.totalMinutes, total <= budget {
                picks.append(TonightPick(media: media, kind: .finishIt, units: media.totalUnits ?? 1, minutes: total, reason: "Start and finish tonight"))
            } else {
                let fit = budget / media.minutesPerUnit
                if fit >= 2 {
                    picks.append(TonightPick(media: media, kind: .startFresh, units: fit, minutes: fit * media.minutesPerUnit,
                                             reason: rec.reasons.first?.text ?? "Start something new"))
                }
            }
        }

        func rank(_ p: TonightPick) -> Double {
            let kindBoost: Double
            switch p.kind {
            case .finishIt: kindBoost = 0.35
            case .continueWatching: kindBoost = 0.3
            case .film: kindBoost = 0.2
            case .startFresh: kindBoost = 0.1
            }
            let fill = Double(p.minutes) / Double(budget)
            return kindBoost + 0.4 * fill + 0.25 * Double(p.media.averageScore ?? 60) / 100
        }
        var seen = Set<Int>()
        return picks.sorted { rank($0) > rank($1) }.filter { seen.insert($0.media.id).inserted }.prefix(limit).map { $0 }
    }
}
