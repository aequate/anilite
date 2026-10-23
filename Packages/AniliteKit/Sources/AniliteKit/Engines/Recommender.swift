import Foundation

public enum RecommendationReason: Hashable, Sendable {
    case sharesThemes([String])
    case becauseYouLoved(title: String)
    case communityPick(from: String, votes: Int)
    case hiddenGem(score: Int, popularity: Int)
    case fitsTime(minutes: Int)
    case moodMatch(Mood)
    case acclaimed(score: Int)

    public var text: String {
        switch self {
        case .sharesThemes(let themes): return "Matches your love of " + ListFormatting.join(themes.map { $0.lowercased() })
        case .becauseYouLoved(let title): return "Because you loved \(title)"
        case .communityPick(let from, let votes): return "\(votes) fans of \(from) recommend it"
        case .hiddenGem(let score, let popularity): return "Hidden gem — \(score)% rated, only \(Formatting.compact(popularity)) fans"
        case .fitsTime(let minutes): return "Fits in \(minutes / 60)h \(minutes % 60)m"
        case .moodMatch(let mood): return "Strong \(mood.label.lowercased()) vibe"
        case .acclaimed(let score): return "Acclaimed — \(score)% average score"
        }
    }

    public var symbol: String {
        switch self {
        case .sharesThemes: return "dna"
        case .becauseYouLoved: return "heart.fill"
        case .communityPick: return "person.3.fill"
        case .hiddenGem: return "diamond.fill"
        case .fitsTime: return "clock.fill"
        case .moodMatch: return "sparkles"
        case .acclaimed: return "star.fill"
        }
    }
}

public struct ScoredMedia: Hashable, Sendable, Identifiable {
    public var media: Media
    public var score: Double
    public var reasons: [RecommendationReason]
    public var isHiddenGem: Bool
    public var id: Int { media.id }

    /// 0–100 "match" shown in the UI.
    public var matchPercent: Int { Int((clamp(score) * 100).rounded()) }
}

/// Community "people who liked X also liked Y" votes gathered from AniList recommendations.
public struct CommunitySignal: Hashable, Sendable {
    public var fromTitle: String
    public var votes: Int
    public init(fromTitle: String, votes: Int) { self.fromTitle = fromTitle; self.votes = votes }
}

public enum Recommender {
    public static func isHiddenGem(_ media: Media) -> Bool {
        guard let score = media.averageScore, let pop = media.popularity else { return false }
        return score >= 74 && pop < 35_000 && pop > 800
    }

    /// Ranks candidates for a user, explains each pick, and removes anything already
    /// in the library, adult titles, franchise duplicates and spoilery sequels.
    public static func rank(
        candidates: [Media],
        dna: TasteDNA,
        library: Library,
        community: [Int: CommunitySignal] = [:],
        policy: SpoilerPolicy = SpoilerPolicy(),
        moods: [Mood] = [],
        maxMinutes: Int? = nil,
        limit: Int = 30
    ) -> [ScoredMedia] {
        let lovedTitles = library.all
            .filter { ($0.status == .completed || $0.status == .repeating) && (!$0.isScored || $0.score >= 75) }
            .map(\.media)
        let lovedVectors = lovedTitles.map { ($0, TasteDNA.vector(for: $0)) }
        let maxVotes = Double(community.values.map(\.votes).max() ?? 1)

        var seenIds = Set<Int>()
        var seenRoots = Set(library.all.map { FranchiseNaming.rootTitle($0.media) })
        var results: [ScoredMedia] = []

        let ordered = candidates.sorted { (community[$0.id]?.votes ?? 0) > (community[$1.id]?.votes ?? 0) }
        for media in ordered {
            guard !seenIds.contains(media.id), library.entry(for: media.id) == nil, !(media.isAdult ?? false) else { continue }
            seenIds.insert(media.id)
            guard SpoilerShield.isSafeRecommendation(media, library: library, policy: policy) else { continue }
            let root = FranchiseNaming.rootTitle(media)
            if !root.isEmpty && seenRoots.contains(root) { continue }
            if let maxMinutes, let total = media.totalMinutes, total > maxMinutes { continue }

            let vector = TasteDNA.vector(for: media)
            let affinity = dna.isMeaningful ? max(0, TasteDNA.cosine(dna.vector, vector)) : 0.5
            let quality = Double(media.averageScore ?? 62) / 100
            let communityBoost = community[media.id].map { Double($0.votes) / maxVotes } ?? 0
            let gem = isHiddenGem(media)
            let vibe = VibeProfile.of(media)
            let moodFit = moods.isEmpty ? 0 : moods.map { vibe.moodScore($0) }.reduce(0, +) / Double(moods.count)

            var score = 0.5 * affinity + 0.25 * quality + 0.15 * communityBoost + (gem ? 0.06 : 0)
            if !moods.isEmpty { score = 0.6 * score + 0.4 * moodFit }
            // Penalise genres the user has repeatedly dropped.
            let disliked = Set(dna.dislikedGenres)
            if !disliked.isEmpty, !(media.genres ?? []).filter(disliked.contains).isEmpty { score -= 0.12 }

            var reasons: [RecommendationReason] = []
            if let best = lovedVectors.max(by: { TasteDNA.cosine($0.1, vector) < TasteDNA.cosine($1.1, vector) }),
               TasteDNA.cosine(best.1, vector) > 0.45 {
                reasons.append(.becauseYouLoved(title: best.0.titleText))
            }
            if let signal = community[media.id], signal.votes >= 3 {
                reasons.append(.communityPick(from: signal.fromTitle, votes: signal.votes))
            }
            let themes = dna.explain(media)
            if !themes.isEmpty { reasons.append(.sharesThemes(themes)) }
            if let mood = moods.first, moodFit > 0.5 { reasons.append(.moodMatch(mood)) }
            if gem, let s = media.averageScore, let p = media.popularity { reasons.append(.hiddenGem(score: s, popularity: p)) }
            if reasons.isEmpty, let s = media.averageScore, s >= 80 { reasons.append(.acclaimed(score: s)) }
            if let maxMinutes, let total = media.totalMinutes, total <= maxMinutes { reasons.append(.fitsTime(minutes: total)) }

            results.append(ScoredMedia(media: media, score: score, reasons: Array(reasons.prefix(3)), isHiddenGem: gem))
            if !root.isEmpty { seenRoots.insert(root) }
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Dropped or long-paused titles that are worth another try.
    public static func revivals(library: Library, dna: TasteDNA, limit: Int = 5) -> [ScoredMedia] {
        library.all
            .filter { entry in
                guard entry.status == .dropped || entry.status == .paused else { return false }
                let fraction = entry.completion ?? 0
                return fraction < 0.6 && (entry.media.averageScore ?? 0) >= 74
            }
            .map { entry -> ScoredMedia in
                let affinity = dna.isMeaningful ? max(0, dna.affinity(for: entry.media)) : 0.5
                let quality = Double(entry.media.averageScore ?? 0) / 100
                var reasons: [RecommendationReason] = []
                let themes = dna.explain(entry.media)
                if !themes.isEmpty { reasons.append(.sharesThemes(themes)) }
                if let s = entry.media.averageScore { reasons.append(.acclaimed(score: s)) }
                return ScoredMedia(media: entry.media, score: 0.6 * affinity + 0.4 * quality, reasons: reasons, isHiddenGem: false)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Compatibility

public struct SharedFavorite: Hashable, Sendable, Identifiable {
    public var media: Media
    public var myScore: Double
    public var theirScore: Double
    public var id: Int { media.id }
}

public struct CompatibilityReport: Sendable {
    public var score: Int
    public var verdict: String
    public var sharedFavorites: [SharedFavorite]
    public var sharedGenres: [String]
    public var theirStrengths: [String]
    public var myStrengths: [String]
    public var picksForMe: [ScoredMedia]
    public var picksForThem: [ScoredMedia]
    public var watchTogether: [Media]
    public var sharedCount: Int
}

public enum Compatibility {
    public static func compare(mine: Library, theirs: Library, theirName: String) -> CompatibilityReport {
        let myDNA = TasteDNA.build(from: mine.all)
        let theirDNA = TasteDNA.build(from: theirs.all)
        let tasteSimilarity = max(0, TasteDNA.cosine(myDNA.vector, theirDNA.vector))

        let shared = mine.all.compactMap { m -> (LibraryEntry, LibraryEntry)? in
            guard let t = theirs.entry(for: m.mediaId) else { return nil }
            return (m, t)
        }
        let bothScored = shared.filter { $0.0.isScored && $0.1.isScored }
        let agreement: Double? = bothScored.count >= 3
            ? 1 - bothScored.map { abs($0.0.score - $0.1.score) }.reduce(0, +) / Double(bothScored.count) / 100
            : nil

        let raw: Double
        if let agreement {
            let w = min(0.5, Double(bothScored.count) / 40)
            raw = (1 - w) * tasteSimilarity + w * agreement
        } else {
            raw = tasteSimilarity
        }
        // Cosine between real taste vectors rarely drops below 0.3; stretch to a 0–100 feel.
        let score = Int((clamp((raw - 0.25) / 0.7) * 100).rounded())

        let favorites = bothScored
            .filter { $0.0.score >= 75 && $0.1.score >= 75 }
            .sorted { ($0.0.score + $0.1.score) > ($1.0.score + $1.1.score) }
            .prefix(10)
            .map { SharedFavorite(media: $0.0.media, myScore: $0.0.score, theirScore: $0.1.score) }

        let myTop = Set(myDNA.topGenres.prefix(6))
        let theirTop = Set(theirDNA.topGenres.prefix(6))

        let picksForMe = Recommender.rank(candidates: lovedMedia(in: theirs), dna: myDNA, library: mine, limit: 8)
        let picksForThem = Recommender.rank(candidates: lovedMedia(in: mine), dna: theirDNA, library: theirs, limit: 8)

        // Titles both planned but neither started: perfect for a watch club.
        let together = mine.all
            .filter { $0.status == .planning && theirs.entry(for: $0.mediaId)?.status == .planning }
            .map(\.media)
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }

        let verdict: String
        switch score {
        case 85...: verdict = "Taste twins. You and \(theirName) are watching the same universe."
        case 70..<85: verdict = "Kindred spirits — lots of overlap with just enough difference to trade picks."
        case 50..<70: verdict = "Complementary tastes. Each of you can widen the other's horizons."
        case 30..<50: verdict = "Different orbits, a few shared stars."
        default: verdict = "Opposites! Perfect for daring each other to try something new."
        }

        return CompatibilityReport(
            score: score,
            verdict: verdict,
            sharedFavorites: Array(favorites),
            sharedGenres: Array(myTop.intersection(theirTop)).sorted(),
            theirStrengths: Array(theirTop.subtracting(myTop)).sorted(),
            myStrengths: Array(myTop.subtracting(theirTop)).sorted(),
            picksForMe: picksForMe,
            picksForThem: picksForThem,
            watchTogether: Array(together.prefix(8)),
            sharedCount: shared.count
        )
    }

    static func lovedMedia(in library: Library) -> [Media] {
        library.all
            .filter { ($0.status == .completed || $0.status == .repeating) && (!$0.isScored || $0.score >= 75) }
            .map(\.media)
    }
}

enum ListFormatting {
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return items[0] + " and " + items[1]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
