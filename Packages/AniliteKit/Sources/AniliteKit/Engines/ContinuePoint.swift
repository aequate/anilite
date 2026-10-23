import Foundation

/// Where to pick up the source after finishing an anime.
public struct ContinuePoint: Hashable, Sendable {
    public enum Confidence: String, Hashable, Sendable {
        /// From a hand-checked table; may vary by about one chapter between editions.
        case curated
        /// Estimated from episode counts and typical adaptation pace.
        case estimated
        /// The anime adapts the whole source.
        case complete
    }

    public var animeId: Int
    public var sourceId: Int?
    public var sourceTitle: String?
    public var sourceFormat: MediaFormat
    /// Chapter (manga) or volume (light novel) to start from.
    public var unit: Int?
    public var confidence: Confidence
    public var animeTitle: String

    public var unitName: String { sourceFormat == .novel ? "volume" : "chapter" }

    public var headline: String {
        switch confidence {
        case .complete:
            return "The anime covers the whole \(sourceFormat == .novel ? "novel series" : "manga")."
        case .curated, .estimated:
            guard let unit else { return "Continue with the source." }
            return "Continue from \(unitName) \(unit)"
        }
    }

    public var detail: String {
        switch confidence {
        case .curated:
            return "After \(animeTitle). Checked against the source — may differ by a chapter between editions."
        case .estimated:
            return "Estimated from the anime's length and typical adaptation pace. Back up a few \(unitName)s to be safe."
        case .complete:
            return "There's nothing left to read after \(animeTitle), though the source may include extra scenes."
        }
    }
}

public enum ContinuePointResolver {
    struct Curated { var source: Int; var next: Int? }

    /// Anime id → source manga id and the first chapter after the anime ends.
    /// `next == nil` means the anime finishes the source.
    static let curated: [Int: Curated] = [
        // Attack on Titan
        16498: Curated(source: 53390, next: 34),
        20958: Curated(source: 53390, next: 51),
        99147: Curated(source: 53390, next: 70),
        104578: Curated(source: 53390, next: 91),
        110277: Curated(source: 53390, next: 117),
        131681: Curated(source: 53390, next: 128),
        146984: Curated(source: 53390, next: nil),
        // Demon Slayer
        101922: Curated(source: 87216, next: 54),
        112151: Curated(source: 87216, next: 67),
        129874: Curated(source: 87216, next: 67),
        142329: Curated(source: 87216, next: 98),
        145139: Curated(source: 87216, next: 128),
        166240: Curated(source: 87216, next: 137),
        // Jujutsu Kaisen
        113415: Curated(source: 101517, next: 64),
        145064: Curated(source: 101517, next: 137),
        131573: Curated(source: 105469, next: nil),
        // Chainsaw Man
        127230: Curated(source: 105778, next: 39),
        171627: Curated(source: 105778, next: 53),
        // Frieren
        154587: Curated(source: 118586, next: 61),
        // Oshi no Ko
        150672: Curated(source: 117195, next: 41),
        166531: Curated(source: 117195, next: 82),
        // Vinland Saga
        101348: Curated(source: 30642, next: 55),
        136430: Curated(source: 30642, next: 101),
        // Hunter x Hunter (2011)
        11061: Curated(source: 30026, next: 340),
        // Mob Psycho 100 III
        140439: Curated(source: 85189, next: nil)
    ]

    /// Typical chapters adapted per episode for weekly shounen-style manga.
    static let chaptersPerEpisode = 2.6
    /// Typical TV episodes per light-novel volume.
    static let episodesPerVolume = 3.5

    public static func hasCurated(_ animeId: Int) -> Bool { curated[animeId] != nil }

    /// - Parameters:
    ///   - anime: the entry the viewer just finished (or is about to).
    ///   - mainline: the franchise's main anime entries in release order, used for estimates.
    ///   - source: the source manga/novel if known.
    public static func resolve(anime: Media, mainline: [Media] = [], source: Media?) -> ContinuePoint? {
        if let entry = curated[anime.id] {
            return ContinuePoint(
                animeId: anime.id, sourceId: entry.source, sourceTitle: source?.id == entry.source ? source?.titleText : nil,
                sourceFormat: .manga, unit: entry.next, confidence: entry.next == nil ? .complete : .curated,
                animeTitle: anime.titleText
            )
        }
        guard let source, source.mediaType == .manga else { return nil }
        let format = source.format ?? .manga
        guard format == .manga || format == .novel else { return nil }

        // Episodes adapted up to and including this entry.
        let chain = mainline.isEmpty ? [anime] : mainline
        let index = chain.firstIndex(where: { $0.id == anime.id }) ?? (chain.count - 1)
        let episodes = chain.prefix(index + 1).reduce(0) { total, m in
            if m.format == .movie { return total + 4 }
            return total + (m.releasedUnits ?? m.episodes ?? 0)
        }
        guard episodes > 0 else { return nil }

        let unit: Int
        if format == .novel {
            unit = Int((Double(episodes) / episodesPerVolume).rounded(.down)) + 1
            if let volumes = source.volumes, source.status == .finished, unit > volumes {
                return ContinuePoint(animeId: anime.id, sourceId: source.id, sourceTitle: source.titleText, sourceFormat: .novel, unit: nil, confidence: .complete, animeTitle: anime.titleText)
            }
        } else {
            unit = Int((Double(episodes) * chaptersPerEpisode).rounded()) + 1
            if let chapters = source.chapters, source.status == .finished, unit > chapters {
                return ContinuePoint(animeId: anime.id, sourceId: source.id, sourceTitle: source.titleText, sourceFormat: .manga, unit: nil, confidence: .complete, animeTitle: anime.titleText)
            }
        }
        return ContinuePoint(animeId: anime.id, sourceId: source.id, sourceTitle: source.titleText, sourceFormat: format, unit: unit, confidence: .estimated, animeTitle: anime.titleText)
    }
}

// MARK: - Ending Assurance

/// Answers "will I get an ending?" before someone invests 20 hours.
public struct FranchiseHealth: Hashable, Sendable {
    public enum Verdict: String, Hashable, Sendable {
        case complete, ongoing, sequelAnnounced, sourceAhead, sourceFinishedAnimeStopped, cancelled, unknown
    }

    public var verdict: Verdict
    public var headline: String
    public var detail: String
    public var symbol: String

    public static func assess(media: Media, graph: FranchiseGraph?, continuePoint: ContinuePoint?, now: Date = Date()) -> FranchiseHealth {
        let mainline = graph?.mainline ?? []
        let source = graph?.sourceMedia
        let upcoming = mainline.first { $0.status == .notYetReleased }

        if media.status == .cancelled {
            return FranchiseHealth(verdict: .cancelled, headline: "Production was cancelled", detail: "This entry never finished airing.", symbol: "xmark.octagon")
        }
        if media.mediaType == .manga {
            switch media.status {
            case .finished?:
                return FranchiseHealth(verdict: .complete, headline: "Complete story", detail: "\(media.chapters.map { "\($0) chapters" } ?? "Finished") — you'll get an ending.", symbol: "checkmark.seal.fill")
            case .hiatus?:
                return FranchiseHealth(verdict: .ongoing, headline: "On hiatus", detail: "Publication is paused; the story isn't finished yet.", symbol: "pause.circle")
            case .releasing?:
                return FranchiseHealth(verdict: .ongoing, headline: "Still being published", detail: "New chapters are coming out.", symbol: "arrow.triangle.2.circlepath")
            default:
                return FranchiseHealth(verdict: .unknown, headline: "Status unknown", detail: "AniList doesn't say whether this is finished.", symbol: "questionmark.circle")
            }
        }
        if media.status == .releasing {
            return FranchiseHealth(verdict: .ongoing, headline: "Airing now", detail: "New episodes arrive weekly.", symbol: "dot.radiowaves.left.and.right")
        }
        if let upcoming {
            let when = upcoming.startDate?.year.map { " (\($0))" } ?? ""
            return FranchiseHealth(verdict: .sequelAnnounced, headline: "Sequel announced", detail: "\(upcoming.titleText)\(when) continues the story.", symbol: "sparkles")
        }
        if continuePoint?.confidence == .complete {
            return FranchiseHealth(verdict: .complete, headline: "Complete adaptation", detail: "The anime tells the whole story.", symbol: "checkmark.seal.fill")
        }
        if let source {
            let lastYear = mainline.compactMap { $0.endDate?.year ?? $0.startDate?.year }.max() ?? media.endDate?.year
            let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
            let dormant = lastYear.map { currentYear - $0 >= 4 } ?? false
            let readFrom = continuePoint?.unit.map { " Pick up the \(continuePoint?.unitName ?? "chapter") \($0)." } ?? ""
            if source.status == .finished && dormant {
                return FranchiseHealth(verdict: .sourceFinishedAnimeStopped, headline: "Anime ends early — the source is finished", detail: "No new anime for years, but the full story exists in the source.\(readFrom)", symbol: "book.closed.fill")
            }
            if source.status == .releasing || source.status == .hiatus {
                return FranchiseHealth(verdict: .sourceAhead, headline: "The source keeps going", detail: "The anime stops partway; the story continues in the source.\(readFrom)", symbol: "book.fill")
            }
            if source.status == .finished {
                return FranchiseHealth(verdict: .sourceAhead, headline: "Finish the story in the source", detail: "The source is complete — the anime may not adapt all of it.\(readFrom)", symbol: "book.fill")
            }
        }
        if media.status == .finished && media.source == "ORIGINAL" {
            return FranchiseHealth(verdict: .complete, headline: "Complete story", detail: "An original or complete production with its own ending.", symbol: "checkmark.seal.fill")
        }
        return FranchiseHealth(verdict: .unknown, headline: "Ending not confirmed", detail: "We couldn't confirm whether the story concludes here.", symbol: "questionmark.circle")
    }
}
