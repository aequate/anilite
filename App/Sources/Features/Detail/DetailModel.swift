import Foundation
import Observation
import AniliteKit

/// Loads one title: cached detail first, then a fresh copy, plus its artwork palette and
/// the franchise facts (continue point, ending assurance) derived from its relations.
@MainActor
@Observable
final class DetailModel {
    let mediaId: Int
    private(set) var media: Media?
    private(set) var atmosphere: Atmosphere = .brand
    private(set) var palette: ArtworkPalette = Theme.defaultPalette
    private(set) var continuePoint: ContinuePoint?
    private(set) var health: FranchiseHealth?
    private(set) var error: String?
    private(set) var isRefreshing = false

    init(mediaId: Int, seed: Media? = nil) {
        self.mediaId = mediaId
        self.media = seed
        if let seed { atmosphere = Atmosphere.resolve(for: seed, palette: .from(hex: seed.coverImage?.color)) }
    }

    func load(client: AniListClient, force: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if force {
                apply(try await client.fetch(Queries.detail(id: mediaId), policy: .networkFirst).Media)
            } else {
                for try await fetched in client.stream(Queries.detail(id: mediaId)) {
                    apply(fetched.value.Media)
                }
            }
            error = nil
        } catch {
            if media == nil { self.error = AppModel.message(for: error) }
        }
        guard let media else { return }
        let palette = await ImagePipeline.shared.palette(for: media.coverImage?.thumbnail, hint: media.coverImage?.color)
        self.palette = palette
        atmosphere = Atmosphere.resolve(for: media, palette: palette)
    }

    private func apply(_ media: Media) {
        self.media = media
        // Tint with AniList's cover colour straight away; the palette read from the cover's
        // pixels replaces it a moment later.
        if palette == Theme.defaultPalette {
            atmosphere = Atmosphere.resolve(for: media, palette: .from(hex: media.coverImage?.color))
        }
        let graph = FranchiseGraph(seed: media)
        if media.mediaType == .anime {
            continuePoint = ContinuePointResolver.resolve(anime: media, mainline: graph.mainline, source: graph.sourceMedia)
        } else {
            continuePoint = nil
        }
        health = FranchiseHealth.assess(media: media, graph: graph, continuePoint: continuePoint)
    }
}
