import SwiftUI
import Observation
import AniliteKit

/// State for the Universe Atlas: the knowledge graph, its force layout, the orbit camera,
/// and on-demand expansion. Each expansion is one cached request.
@MainActor
@Observable
final class AtlasModel {
    private(set) var graph = AtlasGraph()
    private(set) var layout = ForceLayout()
    var camera = AtlasCamera()
    var selected: AtlasNodeID?
    var hiddenKinds: Set<AtlasKind> = []
    private(set) var state: LoadState = .idle
    private(set) var expanding: Set<AtlasNodeID> = []
    private(set) var seedTitle: String?
    private(set) var isFlat = false
    var isInteracting = false

    @ObservationIgnored private var simulation: Task<Void, Never>?
    @ObservationIgnored private var autoRotate = false

    var isEmpty: Bool { graph.nodes.isEmpty }

    func node(_ id: AtlasNodeID?) -> AtlasNode? { id.flatMap { graph.nodes[$0] } }

    func visibleNodes() -> [AtlasNode] {
        graph.nodeList.filter { !hiddenKinds.contains($0.id.kind) }
    }

    func count(of kind: AtlasKind) -> Int { graph.nodes.keys.filter { $0.kind == kind }.count }

    // MARK: Seeding

    /// Starts from what the viewer is watching (or loved most); trending titles otherwise.
    func seedFromLibrary(using model: AppModel) async {
        guard state != .loading else { return }
        let library = model.library
        var seeds: [Media] = library.all
            .filter { $0.status.isActive }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(2)
            .map(\.media)
        if seeds.isEmpty {
            seeds = library.all.filter { $0.status == .completed }
                .sorted { $0.score > $1.score }
                .prefix(2)
                .map(\.media)
        }
        if seeds.isEmpty, let trending = model.home?.trending.media.first {
            seeds = [trending]
        }
        guard !seeds.isEmpty else {
            state = .failed("Add a title to your library, or search for one, to start mapping its universe.")
            return
        }
        await seed(seeds, using: model)
    }

    func seed(_ seeds: [Media], using model: AppModel) async {
        state = .loading
        graph = AtlasGraph()
        layout = ForceLayout()
        layout.flat = isFlat
        selected = nil
        seedTitle = seeds.first.map { model.title($0) }
        var loadedAny = false
        var lastError: Error?
        for media in seeds {
            do {
                let detail = try await model.client.fetch(Queries.detail(id: media.id), policy: .cacheFirst).Media
                graph.expand(media: detail, library: model.library, policy: model.spoilerPolicy)
                loadedAny = true
            } catch {
                lastError = error
            }
        }
        guard loadedAny else {
            state = .failed(lastError.map(AppModel.message(for:)) ?? "Couldn't load this universe.")
            return
        }
        layout.sync(with: graph)
        if !autoRotateAllowed { layout.settle(graph: graph) }
        camera = AtlasCamera()
        if isFlat { camera.yaw = 0; camera.pitch = 0 }
        state = .loaded
        selected = seeds.first.map { AtlasNodeID($0.mediaType == .anime ? .anime : .manga, $0.id) }
    }

    func search(_ text: String, using model: AppModel) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            var found: [Media] = []
            for type in [MediaType.anime, .manga] where found.isEmpty {
                var query = DiscoveryQuery(text: trimmed, type: type)
                query.sort = .relevance
                found = try await model.client.fetch(Queries.search(query), policy: .cacheFirst).Page.media
            }
            guard let first = found.first else {
                state = .failed("No title matched “\(trimmed)”.")
                return
            }
            await seed([first], using: model)
        } catch {
            state = .failed(AppModel.message(for: error))
        }
    }

    // MARK: Expansion

    func isExpanded(_ id: AtlasNodeID) -> Bool { graph.expanded.contains(id) }

    func expand(_ id: AtlasNodeID, using model: AppModel) async {
        guard !graph.expanded.contains(id), !expanding.contains(id), let node = graph.nodes[id], !node.isSpoilerHidden else { return }
        expanding.insert(id)
        defer { expanding.remove(id) }
        let client = model.client
        do {
            switch id.kind {
            case .anime, .manga:
                let media = try await client.fetch(Queries.detail(id: id.id), policy: .cacheFirst).Media
                graph.expand(media: media, library: model.library, policy: model.spoilerPolicy)
            case .character:
                let character = try await client.fetch(Queries.character(id: id.id), policy: .cacheFirst).Character
                let works = (character.media?.edges ?? []).compactMap(\.node)
                graph.expand(hub: id, works: works, label: "Appears in")
            case .creator:
                let staff = try await client.fetch(Queries.staff(id: id.id), policy: .cacheFirst).Staff
                graph.expand(hub: id, works: staff.staffMedia?.nodes ?? [], label: "Worked on")
            case .studio:
                let studio = try await client.fetch(Queries.studio(id: id.id), policy: .cacheFirst).Studio
                graph.expand(hub: id, works: studio.media?.nodes ?? [], label: "Produced")
            case .theme:
                let works = try await client.fetch(Queries.byTag(node.title, type: .anime), policy: .cacheFirst).Page.media
                graph.expand(hub: id, works: works, label: node.title, limit: 8)
            }
            layout.sync(with: graph)
            layout.reheat(0.7)
            if !autoRotateAllowed { layout.settle(graph: graph) }
            Haptics.tap(.soft)
        } catch {
            model.showBanner(AppModel.message(for: error))
            Haptics.warning()
        }
    }

    // MARK: Camera & layout

    func setFlat(_ flat: Bool) {
        isFlat = flat
        layout.flat = flat
        if flat {
            camera.yaw = 0
            camera.pitch = 0
        } else {
            camera.yaw = 0.4
            camera.pitch = -0.25
            // Nudge nodes off the plane so the 3D layout can unfold.
            for (index, id) in graph.nodes.keys.sorted(by: { $0.description < $1.description }).enumerated() {
                if let p = layout.positions[id] {
                    layout.move(id, to: Vec3(p.x, p.y, Double(index % 7) * 12 - 36))
                }
            }
        }
        layout.reheat(0.9)
        if !autoRotateAllowed { layout.settle(graph: graph) }
    }

    func center(on id: AtlasNodeID) {
        guard let p = layout.positions[id] else { return }
        camera.target = p
    }

    func pan(dx: Double, dy: Double) {
        let s = camera.focalLength / camera.distance
        let t = camera.target
        camera.target = Vec3(t.x - dx / s, t.y - dy / s, t.z)
    }

    func reset() {
        camera = AtlasCamera()
        if isFlat { camera.yaw = 0; camera.pitch = 0 }
    }

    // MARK: Simulation

    /// Without a running simulation (Reduce Motion), layouts are settled in one go.
    private var autoRotateAllowed: Bool { simulation != nil }

    /// Runs the force simulation on the main actor at the effects budget's frame rate. The
    /// loop idles (no work, no redraws) once the layout settles and nothing is moving.
    func startSimulation(interval: Double, autoRotate: Bool) {
        stopSimulation()
        self.autoRotate = autoRotate
        let nanos = UInt64(max(interval, 1.0 / 60.0) * 1_000_000_000)
        simulation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.layout.isSettled {
                    self.layout.step(graph: self.graph)
                }
                if self.autoRotate, !self.isFlat, !self.isInteracting, self.state == .loaded {
                    self.camera.yaw += 0.0016
                }
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stopSimulation() {
        simulation?.cancel()
        simulation = nil
    }
}

extension AtlasKind {
    var tint: Color {
        switch self {
        case .anime: return Theme.brand
        case .manga: return Theme.brandCool
        case .character: return Theme.caution
        case .creator: return Theme.positive
        case .studio: return Color(hex: 0xB69CFF)
        case .theme: return Color(hex: 0x9A97AB)
        }
    }

    var radius: CGFloat {
        switch self {
        case .anime, .manga: return 20
        case .character, .creator: return 15
        case .studio: return 14
        case .theme: return 10
        }
    }

    var hasPortrait: Bool { self != .studio && self != .theme }
}

extension AtlasNode {
    var route: Route {
        switch id.kind {
        case .anime, .manga: return .media(id.id)
        case .character: return .character(id.id)
        case .creator: return .staff(id.id)
        case .studio: return .studio(id.id)
        case .theme: return .tag(title, .anime)
        }
    }

    var tint: Color { Color(anilistHex: colorHex) ?? id.kind.tint }
}
