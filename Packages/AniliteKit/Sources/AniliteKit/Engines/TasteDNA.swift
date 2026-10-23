import Foundation

public struct TasteArchetype: Codable, Hashable, Sendable {
    public var name: String
    public var summary: String
    public var symbol: String
}

public struct TasteStrand: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case genre, theme }
    public var name: String
    public var weight: Double
    public var kind: Kind
    public var id: String { kind.rawValue + name }
}

public struct TasteEra: Codable, Hashable, Sendable, Identifiable {
    public var year: Int
    public var topGenres: [String]
    public var count: Int
    public var id: Int { year }
}

/// Two titles from different genres that you loved for the same underlying reasons.
public struct TasteBridge: Hashable, Sendable, Identifiable {
    public var first: Media
    public var second: Media
    public var sharedThemes: [String]
    public var id: String { "\(first.id)-\(second.id)" }
}

/// A portable, evolving model of what someone enjoys.
public struct TasteDNA: Codable, Hashable, Sendable {
    public var genreWeights: [String: Double]
    public var tagWeights: [String: Double]
    public var vibe: VibeProfile
    public var formatShare: [String: Double]
    public var decadeShare: [Int: Double]
    public var meanScore: Double?
    public var scoreSpread: Double?
    public var completionRate: Double
    public var dropRate: Double
    /// 0 = deep cuts, 1 = what everyone watches.
    public var mainstreamIndex: Double
    public var mangaShare: Double
    public var sampleSize: Int
    public var archetype: TasteArchetype
    public var evolution: [TasteEra]

    public static let empty = TasteDNA(
        genreWeights: [:], tagWeights: [:], vibe: .neutral, formatShare: [:], decadeShare: [:],
        meanScore: nil, scoreSpread: nil, completionRate: 0, dropRate: 0, mainstreamIndex: 0.5,
        mangaShare: 0, sampleSize: 0,
        archetype: TasteArchetype(name: "The Newcomer", summary: "Your taste is a blank canvas. Rate a few titles and it will take shape.", symbol: "sparkles"),
        evolution: []
    )

    public var isMeaningful: Bool { sampleSize >= 3 }

    public var strands: [TasteStrand] {
        let g = genreWeights.filter { $0.value > 0 }.map { TasteStrand(name: $0.key, weight: $0.value, kind: .genre) }
        let t = tagWeights.filter { $0.value > 0 }.map { TasteStrand(name: $0.key, weight: $0.value, kind: .theme) }
        return (g.sorted { $0.weight > $1.weight }.prefix(6) + t.sorted { $0.weight > $1.weight }.prefix(6))
            .sorted { $0.weight > $1.weight }
    }

    public var topGenres: [String] {
        genreWeights.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
    }

    public var topThemes: [String] {
        tagWeights.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
    }

    public var dislikedGenres: [String] {
        genreWeights.filter { $0.value < -0.15 }.sorted { $0.value < $1.value }.map(\.key)
    }

    /// Sparse feature vector ("g:Action", "t:Isekai") used for cosine similarity.
    public var vector: [String: Double] {
        var v: [String: Double] = [:]
        for (k, w) in genreWeights { v["g:" + k] = w }
        for (k, w) in tagWeights { v["t:" + k] = w * 0.8 }
        return v
    }

    // MARK: Building

    static func statusWeight(_ status: MediaListStatus) -> Double {
        switch status {
        case .completed: return 1.0
        case .repeating: return 1.3
        case .current: return 0.7
        case .paused: return 0.25
        case .dropped: return -0.7
        case .planning: return 0.12
        }
    }

    /// How much an entry says about the user's taste (negative = dislike).
    public static func signal(for entry: LibraryEntry, mean: Double?, spread: Double?) -> Double {
        var w = statusWeight(entry.status)
        if entry.isScored, let mean {
            let z = clamp((entry.score - mean) / max(10, spread ?? 15), -1.6, 1.6)
            // Low scores deepen a dislike; high scores soften it (and vice versa for likes).
            w *= w >= 0 ? (1 + 0.6 * z) : (1 - 0.6 * z)
            if entry.score < 45 && entry.status == .completed { w = -0.5 }
        }
        return clamp(w, -1.2, 2.2)
    }

    public static func build(from entries: [LibraryEntry], calendar: Calendar = Calendar(identifier: .gregorian)) -> TasteDNA {
        let relevant = entries.filter { !($0.media.isAdult ?? false) }
        guard !relevant.isEmpty else { return .empty }

        let scored = relevant.filter(\.isScored).map(\.score)
        let mean = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let spread: Double? = {
            guard let mean, scored.count > 2 else { return nil }
            let variance = scored.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scored.count)
            return sqrt(variance)
        }()

        var genres: [String: Double] = [:]
        var tags: [String: Double] = [:]
        var formats: [String: Double] = [:]
        var decades: [Int: Double] = [:]
        var vibeSum = [Double](repeating: 0, count: 7)
        var vibeWeight = 0.0
        var popularityLogSum = 0.0
        var popularityCount = 0.0
        var mangaCount = 0.0

        for entry in relevant {
            let w = signal(for: entry, mean: mean, spread: spread)
            for genre in entry.media.genres ?? [] { genres[genre, default: 0] += w }
            for tag in entry.media.tags ?? [] where !tag.isSpoiler {
                tags[tag.name, default: 0] += w * Double(tag.rank ?? 50) / 100
            }
            if w > 0 {
                formats[entry.media.formatLabel, default: 0] += 1
                if let year = entry.media.year { decades[(year / 10) * 10, default: 0] += 1 }
                let vibe = VibeProfile.of(entry.media).dimensions.map(\.value)
                for i in 0..<7 { vibeSum[i] += vibe[i] * w }
                vibeWeight += w
                if let pop = entry.media.popularity, pop > 0 {
                    popularityLogSum += log10(Double(pop))
                    popularityCount += 1
                }
            }
            if entry.type == .manga { mangaCount += 1 }
        }

        let genreMax = genres.values.map(abs).max() ?? 1
        let tagMax = tags.values.map(abs).max() ?? 1
        let normGenres = genres.mapValues { $0 / max(genreMax, 0.0001) }
        // Keep the 40 strongest themes so the model stays compact and portable.
        let normTags = Dictionary(uniqueKeysWithValues: tags
            .map { ($0.key, $0.value / max(tagMax, 0.0001)) }
            .sorted { abs($0.1) > abs($1.1) }
            .prefix(40)
            .map { ($0.0, $0.1) })

        let formatTotal = formats.values.reduce(0, +)
        let decadeTotal = decades.values.reduce(0, +)
        let vibe: VibeProfile = {
            guard vibeWeight > 0 else { return .neutral }
            let v = vibeSum.map { clamp($0 / vibeWeight) }
            return VibeProfile(intensity: v[0], darkness: v[1], humor: v[2], warmth: v[3], complexity: v[4], romance: v[5], pace: v[6])
        }()

        let finishedOrDropped = relevant.filter { $0.status == .completed || $0.status == .dropped || $0.status == .repeating }
        let completed = finishedOrDropped.filter { $0.status != .dropped }.count
        let dropped = finishedOrDropped.count - completed
        let attempted = Double(max(1, finishedOrDropped.count))

        // log10(popularity): ~3.5 for niche titles, ~5.8 for the most popular.
        let mainstream = popularityCount > 0 ? clamp((popularityLogSum / popularityCount - 3.6) / 2.0) : 0.5

        var dna = TasteDNA(
            genreWeights: normGenres,
            tagWeights: normTags,
            vibe: vibe,
            formatShare: formatTotal > 0 ? formats.mapValues { $0 / formatTotal } : [:],
            decadeShare: decadeTotal > 0 ? decades.mapValues { $0 / decadeTotal } : [:],
            meanScore: mean,
            scoreSpread: spread,
            completionRate: Double(completed) / attempted,
            dropRate: Double(dropped) / attempted,
            mainstreamIndex: mainstream,
            mangaShare: mangaCount / Double(relevant.count),
            sampleSize: relevant.filter { $0.status != .planning }.count,
            archetype: TasteDNA.empty.archetype,
            evolution: evolution(of: relevant, calendar: calendar)
        )
        dna.archetype = archetype(for: dna)
        return dna
    }

    static func evolution(of entries: [LibraryEntry], calendar: Calendar) -> [TasteEra] {
        var byYear: [Int: [String: Double]] = [:]
        var counts: [Int: Int] = [:]
        for entry in entries where entry.status == .completed || entry.status == .current || entry.status == .repeating {
            let year = entry.completedAt?.year ?? entry.startedAt?.year ?? calendar.component(.year, from: entry.updatedAt)
            counts[year, default: 0] += 1
            for genre in entry.media.genres ?? [] {
                byYear[year, default: [:]][genre, default: 0] += max(0.2, entry.isScored ? entry.score / 100 : 0.7)
            }
        }
        return byYear.keys.sorted().map { year in
            let top = (byYear[year] ?? [:]).sorted { $0.value > $1.value }.prefix(3).map(\.key)
            return TasteEra(year: year, topGenres: top, count: counts[year] ?? 0)
        }
    }

    static func archetype(for dna: TasteDNA) -> TasteArchetype {
        guard dna.isMeaningful else { return TasteDNA.empty.archetype }
        let v = dna.vibe
        let g = dna.genreWeights
        func genre(_ name: String) -> Double { max(0, g[name] ?? 0) }
        let genreCount = Double(g.filter { $0.value > 0.35 }.count)

        let candidates: [(Double, TasteArchetype)] = [
            (v.warmth * 1.2 + (1 - v.intensity) * 0.6 + genre("Slice of Life") * 0.5,
             TasteArchetype(name: "The Cozy Wanderer", summary: "You collect warm, gentle stories with room to breathe — comfort over chaos.", symbol: "cup.and.saucer.fill")),
            (v.intensity * 1.2 + v.pace * 0.6 + genre("Action") * 0.5,
             TasteArchetype(name: "The Adrenaline Seeker", summary: "You chase momentum: big fights, high stakes, no filler.", symbol: "flame.fill")),
            (v.complexity * 1.3 + genre("Mystery") * 0.4 + genre("Psychological") * 0.4,
             TasteArchetype(name: "The Puzzle Hunter", summary: "Twists, unreliable narrators, big ideas — you like stories that make you work.", symbol: "brain.head.profile")),
            (v.darkness * 1.3 + genre("Horror") * 0.4 + genre("Psychological") * 0.3,
             TasteArchetype(name: "The Abyss Gazer", summary: "You're drawn to heavy themes and morally grey worlds.", symbol: "moon.stars.fill")),
            (v.romance * 1.4 + genre("Romance") * 0.5,
             TasteArchetype(name: "The Heart Collector", summary: "Chemistry, longing and slow burns are your favourite genre of all.", symbol: "heart.fill")),
            (v.humor * 1.3 + genre("Comedy") * 0.5,
             TasteArchetype(name: "The Comedy Connoisseur", summary: "Timing is everything, and you can spot a great bit from a mile away.", symbol: "face.smiling.inverse")),
            ((genre("Adventure") + genre("Fantasy")) * 0.8 + v.intensity * 0.3 + v.complexity * 0.3,
             TasteArchetype(name: "The Epic Voyager", summary: "Vast worlds, long journeys and lore you can get lost in.", symbol: "mountain.2.fill")),
            ((1 - dna.mainstreamIndex) * 1.8,
             TasteArchetype(name: "The Deep Diver", summary: "You find gems long before the crowd does — your list is full of deep cuts.", symbol: "water.waves")),
            (min(1, genreCount / 9) * 1.6,
             TasteArchetype(name: "The Explorer", summary: "No genre is off limits. Your taste is wide and refuses to be boxed in.", symbol: "safari.fill"))
        ]
        return candidates.max { $0.0 < $1.0 }?.1 ?? TasteDNA.empty.archetype
    }

    // MARK: Similarity

    public static func vector(for media: Media) -> [String: Double] {
        var v: [String: Double] = [:]
        for genre in media.genres ?? [] { v["g:" + genre] = 1 }
        for tag in media.tags ?? [] where !tag.isSpoiler {
            v["t:" + tag.name] = Double(tag.rank ?? 50) / 100 * 0.8
        }
        return v
    }

    public static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        var dot = 0.0
        for (k, x) in a { if let y = b[k] { dot += x * y } }
        let na = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let nb = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }

    public func affinity(for media: Media) -> Double {
        TasteDNA.cosine(vector, TasteDNA.vector(for: media))
    }

    /// The features that most explain why `media` matches this taste.
    public func explain(_ media: Media, limit: Int = 3) -> [String] {
        let mv = TasteDNA.vector(for: media)
        let mine = vector
        return mv.compactMap { key, value -> (String, Double)? in
            guard let w = mine[key], w > 0.15 else { return nil }
            return (String(key.dropFirst(2)), w * value)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    /// Pairs of loved titles from different genres that share themes.
    public static func bridges(in entries: [LibraryEntry], limit: Int = 3) -> [TasteBridge] {
        let loved = entries
            .filter { ($0.status == .completed || $0.status == .repeating) && (!$0.isScored || $0.score >= 70) }
            .sorted { $0.score > $1.score }
            .prefix(40)
            .map(\.media)
        var results: [(TasteBridge, Double)] = []
        for i in 0..<loved.count {
            for j in (i + 1)..<loved.count {
                let a = loved[i], b = loved[j]
                guard let ga = a.genres?.first, let gb = b.genres?.first, ga != gb,
                      Set(a.genres ?? []).intersection(b.genres ?? []).count <= 1 else { continue }
                let ta = Set(a.safeTags.prefix(10).map(\.name))
                let tb = Set(b.safeTags.prefix(10).map(\.name))
                let shared = ta.intersection(tb)
                guard shared.count >= 2 else { continue }
                let score = Double(shared.count) / Double(max(1, ta.union(tb).count))
                results.append((TasteBridge(first: a, second: b, sharedThemes: Array(shared).sorted()), score))
            }
        }
        var used = Set<Int>()
        var out: [TasteBridge] = []
        for (bridge, _) in results.sorted(by: { $0.1 > $1.1 }) where !used.contains(bridge.first.id) && !used.contains(bridge.second.id) {
            out.append(bridge)
            used.insert(bridge.first.id)
            used.insert(bridge.second.id)
            if out.count == limit { break }
        }
        return out
    }
}

// MARK: - Sharing

/// A compact, privacy-light summary of a taste that can be shared as a code.
public struct TasteFingerprint: Codable, Hashable, Sendable {
    public var name: String
    public var archetype: String
    public var weights: [String: Double]
    public var vibe: [Double]

    public init(name: String, dna: TasteDNA) {
        self.name = name
        self.archetype = dna.archetype.name
        let top = dna.vector.sorted { abs($0.value) > abs($1.value) }.prefix(24)
        self.weights = Dictionary(uniqueKeysWithValues: top.map { ($0.key, (($0.value * 100).rounded() / 100)) })
        self.vibe = dna.vibe.dimensions.map { ($0.value * 100).rounded() / 100 }
    }

    public var code: String { ShareCodec.encode(self, prefix: "DNA") ?? "" }

    public static func decode(_ code: String) -> TasteFingerprint? {
        ShareCodec.decode(TasteFingerprint.self, from: code, prefix: "DNA")
    }

    public func compatibility(with other: TasteFingerprint) -> Int {
        let c = TasteDNA.cosine(weights, other.weights)
        let vibeDistance = sqrt(zip(vibe, other.vibe).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }) / sqrt(7)
        let combined = 0.7 * max(0, c) + 0.3 * (1 - vibeDistance)
        return Int((combined * 100).rounded())
    }
}
