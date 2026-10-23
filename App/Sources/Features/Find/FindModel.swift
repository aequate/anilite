import Foundation
import Observation
import AniliteKit

/// Natural-language discovery. Parsing is on-device and instant; the network is only hit
/// when the user submits, which keeps well inside AniList's rate limit.
@MainActor
@Observable
final class FindModel {
    var text = ""
    private(set) var query: DiscoveryQuery?
    private(set) var chips: [InterpretationChip] = []
    private(set) var alsoSearchTitle: String?
    private(set) var results: [Media] = []
    private(set) var titleMatches: [Media] = []
    private(set) var seed: Media?
    private(set) var state: LoadState = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Live preview of how the text will be understood, shown while typing.
    var preview: [InterpretationChip] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return [] }
        return NaturalQueryParser().parse(trimmed).chips
    }

    var hasSearched: Bool { query != nil }

    func submit(using model: AppModel) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.rememberSearch(trimmed)
        let parsed = NaturalQueryParser().parse(trimmed)
        query = parsed.query
        chips = parsed.chips
        alsoSearchTitle = parsed.alsoSearchTitle
        run(using: model)
    }

    func clear() {
        task?.cancel()
        text = ""
        query = nil
        chips = []
        results = []
        titleMatches = []
        seed = nil
        state = .idle
        hasMore = false
    }

    /// Removes one interpretation and searches again with the edited query.
    func remove(_ chip: InterpretationChip, using model: AppModel) {
        guard var q = query else { return }
        switch chip.kind {
        case .similar: q.likeTitle = nil; seed = nil
        case .type: q.type = .anime; q.country = nil; q.formats.removeAll { $0 == .novel || $0 == .oneShot }
        case .format: q.formats = []
        case .time: q.maxTotalMinutes = nil
        case .length: q.maxEpisodes = nil; q.minEpisodes = nil; q.maxEpisodeMinutes = nil
        case .era: q.yearFrom = nil; q.yearTo = nil
        case .status: q.status = nil
        case .quality: q.sort = nil; q.minScore = nil; q.maxPopularity = nil; q.minPopularity = nil
        case .exclude:
            let name = chip.label.hasPrefix("No ") ? String(chip.label.dropFirst(3)) : chip.label
            q.genresExclude.removeAll { $0 == name }
            q.tagsExclude.removeAll { $0 == name }
        case .mood: q.moods.removeAll { $0.label == chip.label }
        case .genre: q.genresInclude.removeAll { $0 == chip.label }
        case .tag: q.tagsInclude.removeAll { $0 == chip.label }
        }
        chips.removeAll { $0 == chip }
        query = q
        Haptics.tap(.soft)
        if chips.isEmpty && (q.text ?? "").isEmpty && q.likeTitle == nil {
            clear()
        } else {
            run(using: model)
        }
    }

    private func run(using model: AppModel) {
        guard let q = query else { return }
        task?.cancel()
        state = .loading
        page = 1
        let client = model.client
        let title = alsoSearchTitle
        task = Task { [weak self] in
            do {
                let outcome = try await Self.fetch(q, page: 1, client: client)
                guard !Task.isCancelled, let self else { return }
                self.results = outcome.results
                self.seed = outcome.seed
                self.hasMore = outcome.hasMore
                self.state = .loaded
                if outcome.results.isEmpty { Haptics.warning() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .failed(AppModel.message(for: error))
            }
            if let title, let self {
                var titleQuery = DiscoveryQuery(text: title, type: q.type)
                titleQuery.sort = .relevance
                let matches = (try? await client.fetch(Queries.search(titleQuery), policy: .cacheFirst).Page.media) ?? []
                guard !Task.isCancelled else { return }
                let shown = Set(self.results.prefix(10).map(\.id))
                self.titleMatches = Array(matches.filter { !shown.contains($0.id) }.prefix(5))
            } else {
                self?.titleMatches = []
            }
        }
    }

    func loadMore(using model: AppModel) {
        guard hasMore, !isLoadingMore, let q = query, q.likeTitle == nil else { return }
        isLoadingMore = true
        let next = page + 1
        let client = model.client
        Task { [weak self] in
            let outcome = try? await Self.fetch(q, page: next, client: client)
            guard let self else { return }
            self.isLoadingMore = false
            guard let outcome else { return }
            let known = Set(self.results.map(\.id))
            self.results += outcome.results.filter { !known.contains($0.id) }
            self.hasMore = outcome.hasMore
            self.page = next
        }
    }

    private struct Outcome: Sendable {
        var results: [Media]
        var seed: Media?
        var hasMore: Bool
    }

    private static func fetch(_ q: DiscoveryQuery, page: Int, client: AniListClient) async throws -> Outcome {
        guard let like = q.likeTitle else {
            let response = try await client.fetch(Queries.search(q.preparedForServer(), page: page), policy: .cacheFirst)
            return Outcome(results: q.refine(response.Page.media), seed: nil, hasMore: response.Page.pageInfo?.hasNextPage ?? false)
        }

        // "Like X": find X, then blend AniList's community recommendations with a filtered
        // search around X's genres, ranked by thematic similarity to X.
        var seedQuery = DiscoveryQuery(text: like, type: q.type)
        seedQuery.sort = .relevance
        guard let seedCard = try await client.fetch(Queries.search(seedQuery), policy: .cacheFirst).Page.media.first else {
            throw AniListError.notFound
        }
        let seed = (try? await client.fetch(Queries.detail(id: seedCard.id), policy: .cacheFirst).Media) ?? seedCard
        var pool = (seed.recommendations?.nodes ?? []).compactMap(\.mediaRecommendation)

        var around = q
        around.likeTitle = nil
        around.text = nil
        if around.genresInclude.isEmpty, around.tagsInclude.isEmpty, let genre = seed.genres?.first {
            around.genresInclude = [genre]
        }
        if around.sort == nil { around.sort = .score }
        if let more = try? await client.fetch(Queries.search(around.preparedForServer()), policy: .cacheFirst).Page.media {
            pool += more
        }

        let seedVector = TasteDNA.vector(for: seed)
        var seen: Set<Int> = [seed.id]
        let excluded = Set(q.genresExclude)
        let ranked = pool
            .filter { seen.insert($0.id).inserted }
            .filter { media in excluded.isDisjoint(with: media.genres ?? []) }
            .filter { q.formats.isEmpty || q.formats.contains($0.format ?? .unknown) }
            .map { media in (media, TasteDNA.cosine(seedVector, TasteDNA.vector(for: media)) + Double(media.averageScore ?? 60) / 400) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return Outcome(results: q.refine(ranked), seed: seed, hasMore: false)
    }
}
