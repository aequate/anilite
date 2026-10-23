import Foundation

/// A franchise as a graph of AniList entries, assembled incrementally from relation data.
public struct FranchiseGraph: Sendable {
    public struct Edge: Hashable, Sendable {
        public var type: MediaRelationType
        public var to: Int
    }

    public private(set) var nodes: [Int: Media] = [:]
    public private(set) var edges: [Int: [Edge]] = [:]
    public private(set) var expanded: Set<Int> = []
    public let seedId: Int

    /// Relations worth walking when mapping a franchise's story.
    public static let storyRelations: Set<MediaRelationType> = [.prequel, .sequel, .parent, .sideStory, .spinOff, .summary, .alternative, .compilation, .contains]

    public init(seed: Media) {
        seedId = seed.id
        merge(seed)
    }

    public mutating func merge(_ media: Media) {
        var stored = media
        if let existing = nodes[media.id] {
            // Keep the richer copy of the media fields.
            if existing.description != nil && media.description == nil { stored = existing; stored.relations = media.relations ?? existing.relations }
        }
        nodes[media.id] = stored
        guard let rel = media.relations?.edges else { return }
        expanded.insert(media.id)
        var list = edges[media.id] ?? []
        for edge in rel {
            guard let type = edge.relationType, let node = edge.node else { continue }
            if nodes[node.id] == nil { nodes[node.id] = node }
            let e = Edge(type: type, to: node.id)
            if !list.contains(e) { list.append(e) }
            // Mirror the edge so traversal works in both directions.
            if let inverse = Self.inverse(type) {
                var back = edges[node.id] ?? []
                let b = Edge(type: inverse, to: media.id)
                if !back.contains(b) { back.append(b) }
                edges[node.id] = back
            }
        }
        edges[media.id] = list
    }

    static func inverse(_ type: MediaRelationType) -> MediaRelationType? {
        switch type {
        case .prequel: return .sequel
        case .sequel: return .prequel
        case .parent: return .sideStory
        case .sideStory: return .parent
        case .source: return .adaptation
        case .adaptation: return .source
        case .summary: return nil
        case .alternative: return .alternative
        case .compilation: return .contains
        case .contains: return .compilation
        default: return nil
        }
    }

    /// Story-connected anime/manga ids we haven't fetched relations for yet.
    public func frontier(limit: Int = 50) -> [Int] {
        let reachable = component(from: seedId, via: Self.storyRelations.union([.source, .adaptation]))
        return reachable
            .filter { !expanded.contains($0) }
            .filter { id in
                guard let m = nodes[id] else { return false }
                return m.format != .music
            }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }

    public func component(from start: Int, via relations: Set<MediaRelationType>) -> Set<Int> {
        var seen: Set<Int> = [start]
        var queue = [start]
        while let current = queue.popLast() {
            for edge in edges[current] ?? [] where relations.contains(edge.type) && !seen.contains(edge.to) {
                seen.insert(edge.to)
                queue.append(edge.to)
            }
        }
        return seen
    }

    public func relation(from: Int, to: Int) -> MediaRelationType? {
        edges[from]?.first(where: { $0.to == to })?.type
    }

    /// The anime that anchors the franchise for a seed that may be a manga.
    public var animeAnchorId: Int? {
        if let seed = nodes[seedId], seed.mediaType == .anime { return seedId }
        let adaptations = (edges[seedId] ?? []).filter { $0.type == .adaptation }.compactMap { nodes[$0.to] }
            .filter { $0.mediaType == .anime && ($0.format?.isMainline ?? false) }
        return adaptations.min { ($0.startDate ?? FuzzyDate()) < ($1.startDate ?? FuzzyDate()) }?.id
    }

    public var sourceMedia: Media? {
        if let seed = nodes[seedId], seed.mediaType == .manga { return seed }
        for id in mainline.map(\.id) {
            if let src = (edges[id] ?? []).first(where: { $0.type == .source }).flatMap({ nodes[$0.to] }), src.mediaType == .manga {
                return src
            }
        }
        return nil
    }

    /// Main story: TV/film/ONA entries chained by prequel/sequel links, in release order.
    public var mainline: [Media] {
        guard let anchor = animeAnchorId else { return [] }
        let chain = component(from: anchor, via: [.prequel, .sequel]).compactMap { nodes[$0] }.filter { $0.mediaType == .anime }
        var included = Set(chain.filter { $0.format?.isMainline == true }.map(\.id))
        // OVAs/specials that directly continue the main story (AniList files some finales,
        // like Attack on Titan's "The Final Chapters", as SPECIAL) belong in the main line.
        // Short extras and prequel side stories don't.
        var changed = true
        while changed {
            changed = false
            for m in chain where !included.contains(m.id) && (m.format == .ova || m.format == .special) {
                let continuesMain = (edges[m.id] ?? []).contains { $0.type == .prequel && included.contains($0.to) }
                let substantial = (m.totalMinutes ?? 0) >= 45
                if continuesMain && substantial {
                    included.insert(m.id)
                    changed = true
                }
            }
        }
        return chain.filter { included.contains($0.id) }.sorted(by: Self.releaseOrder)
    }

    /// Every anime in the franchise, release order.
    public var allAnime: [Media] {
        guard let anchor = animeAnchorId else { return [] }
        return component(from: anchor, via: Self.storyRelations)
            .compactMap { nodes[$0] }
            .filter { $0.mediaType == .anime && $0.format != .music }
            .sorted(by: Self.releaseOrder)
    }

    static func releaseOrder(_ a: Media, _ b: Media) -> Bool {
        let ka = a.startDate?.sortKey ?? Int.max, kb = b.startDate?.sortKey ?? Int.max
        return ka == kb ? a.id < b.id : ka < kb
    }
}

public enum RouteKind: String, CaseIterable, Sendable, Identifiable {
    case essentials, release, completionist, mangaFirst
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .essentials: return "Story Essentials"
        case .release: return "Release Order"
        case .completionist: return "Completionist"
        case .mangaFirst: return "Manga First"
        }
    }

    public var subtitle: String {
        switch self {
        case .essentials: return "Only what the main story needs."
        case .release: return "Everything as fans saw it, recaps skipped."
        case .completionist: return "Every OVA, special and side story."
        case .mangaFirst: return "Read the source, then enjoy the animation."
        }
    }

    public var symbol: String {
        switch self {
        case .essentials: return "bolt.fill"
        case .release: return "calendar"
        case .completionist: return "square.stack.3d.up.fill"
        case .mangaFirst: return "book.fill"
        }
    }
}

public enum StepRole: String, Sendable {
    case main, film, sideStory, recap, spinOff, alternative, source, extra

    public var label: String {
        switch self {
        case .main: return "Main story"
        case .film: return "Film"
        case .sideStory: return "Side story"
        case .recap: return "Recap — safe to skip"
        case .spinOff: return "Spin-off"
        case .alternative: return "Alternate version"
        case .source: return "Source material"
        case .extra: return "Extra"
        }
    }
}

public struct RouteStep: Hashable, Sendable, Identifiable {
    public var media: Media
    public var role: StepRole
    public var isOptional: Bool
    public var minutes: Int
    public var note: String?
    public var id: Int { media.id }
}

public struct FranchiseRoute: Sendable, Identifiable {
    public var kind: RouteKind
    public var steps: [RouteStep]
    public var continuePoint: ContinuePoint?
    public var id: RouteKind { kind }

    public var totalMinutes: Int { steps.filter { !$0.isOptional }.reduce(0) { $0 + $1.minutes } }

    public func remainingMinutes(in library: Library) -> Int {
        steps.filter { !$0.isOptional }.reduce(0) { total, step in
            guard let entry = library.entry(for: step.media.id) else { return total + step.minutes }
            if entry.status == .completed { return total }
            let done = entry.progress * step.media.minutesPerUnit
            return total + max(0, step.minutes - done)
        }
    }

    public func completedSteps(in library: Library) -> Int {
        steps.filter { library.entry(for: $0.media.id)?.status == .completed }.count
    }

    /// The first unfinished required step — "what to watch next".
    public func nextStep(in library: Library) -> RouteStep? {
        steps.first { step in !step.isOptional && library.entry(for: step.media.id)?.status != .completed }
    }
}

public enum Pathfinder {
    static func minutes(for media: Media) -> Int {
        if let total = media.totalMinutes { return total }
        if let released = media.releasedUnits { return released * media.minutesPerUnit }
        return media.mediaType == .anime ? 12 * media.minutesPerUnit : 0
    }

    static func role(of media: Media, mainlineIds: Set<Int>, graph: FranchiseGraph) -> StepRole {
        if mainlineIds.contains(media.id) { return media.format == .movie ? .film : .main }
        for id in mainlineIds {
            switch graph.relation(from: id, to: media.id) {
            case .summary?: return .recap
            case .sideStory?: return .sideStory
            case .spinOff?: return .spinOff
            case .alternative?: return .alternative
            case .compilation?: return .recap
            default: continue
            }
        }
        if media.format == .special || media.format == .ova { return .extra }
        return .sideStory
    }

    public static func routes(for graph: FranchiseGraph) -> [FranchiseRoute] {
        let mainline = graph.mainline
        let mainIds = Set(mainline.map(\.id))
        let all = graph.allAnime
        let source = graph.sourceMedia
        let lastMain = mainline.last(where: { $0.status != .notYetReleased }) ?? mainline.last
        let continuePoint = lastMain.flatMap { ContinuePointResolver.resolve(anime: $0, mainline: mainline, source: source) }

        func step(_ m: Media, forceOptional: Bool = false) -> RouteStep {
            let role = role(of: m, mainlineIds: mainIds, graph: graph)
            var note: String?
            if m.status == .notYetReleased { note = "Upcoming" }
            else if m.status == .releasing { note = "Airing now" }
            else if role == .recap { note = "Retells earlier episodes" }
            if let filler = FillerGuide.info(for: m.id) {
                note = "\(filler.fillerCount) filler episodes — skipping saves \(Formatting.duration(minutes: filler.fillerCount * m.minutesPerUnit))"
            }
            let optional = forceOptional || role == .recap || role == .alternative || m.status == .notYetReleased
            return RouteStep(media: m, role: role, isOptional: optional, minutes: minutes(for: m), note: note)
        }

        var routes: [FranchiseRoute] = []
        if !mainline.isEmpty {
            routes.append(FranchiseRoute(kind: .essentials, steps: mainline.map { step($0) }, continuePoint: continuePoint))
        }
        let releaseSteps = all.filter { m in
            let r = role(of: m, mainlineIds: mainIds, graph: graph)
            return r != .recap && r != .alternative
        }.map { m -> RouteStep in
            var s = step(m)
            if !mainIds.contains(m.id) { s.isOptional = true }
            return s
        }
        if releaseSteps.count > mainline.count {
            routes.append(FranchiseRoute(kind: .release, steps: releaseSteps, continuePoint: continuePoint))
        }
        if all.count > releaseSteps.count {
            routes.append(FranchiseRoute(kind: .completionist, steps: all.map { m in
                var s = step(m)
                s.isOptional = s.role == .recap
                return s
            }, continuePoint: continuePoint))
        }
        if let source {
            var steps = [RouteStep(media: source, role: .source, isOptional: false, minutes: minutes(for: source), note: source.status == .releasing ? "Still being published" : nil)]
            steps += mainline.map { step($0, forceOptional: true) }
            routes.append(FranchiseRoute(kind: .mangaFirst, steps: steps, continuePoint: nil))
        }
        return routes
    }
}

// MARK: - Filler

public struct FillerInfo: Hashable, Sendable {
    public var ranges: [ClosedRange<Int>]
    public var fillerCount: Int { ranges.reduce(0) { $0 + $1.count } }

    public func isFiller(_ episode: Int) -> Bool { ranges.contains { $0.contains(episode) } }

    /// Canon-only episodes still left to watch after `progress`.
    public func canonRemaining(after progress: Int, total: Int) -> Int {
        guard total > progress else { return 0 }
        return ((progress + 1)...total).filter { !isFiller($0) }.count
    }
}

/// Community-maintained filler lists for long-running shows (anime-original episodes).
public enum FillerGuide {
    static let table: [Int: [ClosedRange<Int>]] = [
        // Naruto (2002)
        20: [26...26, 97...97, 101...106, 136...141, 143...220]
    ]

    public static func info(for mediaId: Int) -> FillerInfo? {
        table[mediaId].map(FillerInfo.init)
    }
}
