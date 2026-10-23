import SwiftUI
import Observation
import QuartzCore
import AniliteKit

enum AtlasMode: String, CaseIterable, Identifiable {
    case web = "Web"
    case timeline = "Timeline"
    var id: String { rawValue }
}

/// State for the Universe Atlas: the knowledge graph and on-demand expansion. Everything
/// that changes every frame (layout, camera, morph) lives in `scene`, which SwiftUI
/// doesn't observe, so a moving map redraws only its canvas.
@MainActor
@Observable
final class AtlasModel {
    private(set) var graph = AtlasGraph()
    private(set) var selected: AtlasNodeID?
    private(set) var hiddenKinds: Set<AtlasKind> = []
    private(set) var state: LoadState = .idle
    private(set) var expanding: Set<AtlasNodeID> = []
    private(set) var seedTitle: String?
    private(set) var mode: AtlasMode = .web
    /// True while the canvas needs frames. The scene clears it once everything is at rest.
    private(set) var isLive = true

    @ObservationIgnored let scene = AtlasScene()
    /// False under Reduce Motion: layouts settle in one go and the camera jumps.
    @ObservationIgnored var animates = true {
        didSet { scene.animates = animates }
    }
    @ObservationIgnored private var wakeGeneration = 0
    @ObservationIgnored private var idleScheduled = false

    var isEmpty: Bool { graph.nodes.isEmpty }

    func node(_ id: AtlasNodeID?) -> AtlasNode? { id.flatMap { graph.nodes[$0] } }

    func visibleNodes() -> [AtlasNode] {
        graph.nodeList.filter { !hiddenKinds.contains($0.id.kind) }
    }

    func count(of kind: AtlasKind) -> Int { graph.nodes.keys.filter { $0.kind == kind }.count }

    func isExpanded(_ id: AtlasNodeID) -> Bool { graph.expanded.contains(id) }

    // MARK: Frames

    func wake() {
        wakeGeneration += 1
        if !isLive { isLive = true }
    }

    /// Called from the canvas when the scene has come to rest.
    func sceneDidSettle() {
        guard isLive, !idleScheduled else { return }
        idleScheduled = true
        let generation = wakeGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.idleScheduled = false
            if self.wakeGeneration == generation { self.isLive = false }
        }
    }

    // MARK: Selection and filters

    func select(_ id: AtlasNodeID?) {
        guard id != selected else { return }
        selected = id
        scene.focus(on: id)
        wake()
    }

    func toggle(_ kind: AtlasKind) {
        if hiddenKinds.contains(kind) { hiddenKinds.remove(kind) } else { hiddenKinds.insert(kind) }
        wake()
    }

    func setMode(_ newMode: AtlasMode) {
        guard newMode != mode else { return }
        mode = newMode
        scene.setMode(newMode, selected: selected)
        wake()
    }

    func recenter() {
        scene.frameAll(selected: selected)
        wake()
    }

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
        var fresh = AtlasGraph()
        var loadedAny = false
        var lastError: Error?
        for media in seeds {
            do {
                let detail = try await model.client.fetch(Queries.detail(id: media.id), policy: .cacheFirst).Media
                fresh.expand(media: detail, library: model.library, policy: model.spoilerPolicy)
                loadedAny = true
            } catch {
                lastError = error
            }
        }
        guard loadedAny else {
            state = .failed(lastError.map(AppModel.message(for:)) ?? "Couldn't load this universe.")
            return
        }
        graph = fresh
        selected = nil
        seedTitle = seeds.first.map { model.title($0) }
        let first = seeds.first.map { AtlasNodeID($0.mediaType == .anime ? .anime : .manga, $0.id) }
        scene.reset(graph: graph, mode: mode, bloomFrom: first)
        state = .loaded
        select(first)
        wake()
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
                model.showBanner("No title matched “\(trimmed)”.")
                return
            }
            await seed([first], using: model)
        } catch {
            model.showBanner(AppModel.message(for: error))
        }
    }

    // MARK: Expansion

    func expand(_ id: AtlasNodeID, using model: AppModel) async {
        guard !graph.expanded.contains(id), !expanding.contains(id), let node = graph.nodes[id], !node.isSpoilerHidden else { return }
        expanding.insert(id)
        defer { expanding.remove(id) }
        let client = model.client
        do {
            var next = graph
            switch id.kind {
            case .anime, .manga:
                let media = try await client.fetch(Queries.detail(id: id.id), policy: .cacheFirst).Media
                next.expand(media: media, library: model.library, policy: model.spoilerPolicy)
            case .character:
                let character = try await client.fetch(Queries.character(id: id.id), policy: .cacheFirst).Character
                let works = (character.media?.edges ?? []).compactMap(\.node)
                next.expand(hub: id, works: works, label: "Appears in")
            case .creator:
                let staff = try await client.fetch(Queries.staff(id: id.id), policy: .cacheFirst).Staff
                next.expand(hub: id, works: staff.staffMedia?.nodes ?? [], label: "Worked on")
            case .studio:
                let studio = try await client.fetch(Queries.studio(id: id.id), policy: .cacheFirst).Studio
                next.expand(hub: id, works: studio.media?.nodes ?? [], label: "Produced")
            case .theme:
                let works = try await client.fetch(Queries.byTag(node.title, type: .anime), policy: .cacheFirst).Page.media
                next.expand(hub: id, works: works, label: node.title, limit: 8)
            }
            graph = next
            scene.grow(graph: graph, from: id)
            wake()
            Haptics.tap(.soft)
        } catch {
            model.showBanner(AppModel.message(for: error))
            Haptics.warning()
        }
    }
}

// MARK: - Scene

/// Per-frame state for the Atlas canvas: the force layout, the timeline layout and the
/// morph between them, and a camera that eases to where it's sent and coasts after a flick.
@MainActor
final class AtlasScene {
    struct ScreenNode {
        var center: CGPoint
        var radius: CGFloat
        var depth: Double
    }

    private struct Flight {
        var node: AtlasNodeID?
        var target: Vec3
        var distance: Double?
        var yaw: Double?
        var pitch: Double?
    }

    static let webYaw = 0.45
    static let webPitch = -0.28

    private(set) var layout = ForceLayout()
    private(set) var timeline = AtlasTimeline()
    var camera = AtlasCamera()
    var animates = true
    /// Slow drift when nothing is selected (full effects only).
    var ambient = false
    /// Travelling pulses on the selection's edges (full effects only).
    var pulses = false
    private(set) var morph = 0.0
    private var morphGoal = 0.0
    private(set) var time = CACurrentMediaTime()
    private var lastTick: Double?
    private var stepDebt = 0.0
    private var flight: Flight?
    private var spinYaw = 0.0, spinPitch = 0.0
    private var panVelocity = CGVector.zero
    private(set) var born: [AtlasNodeID: Double] = [:]
    private(set) var selected: AtlasNodeID?
    private(set) var selectedAt = -10.0
    var isInteracting = false
    /// Last drawn screen positions, for hit testing.
    var screen: [AtlasNodeID: ScreenNode] = [:]
    var viewport = CGSize(width: 390, height: 700)
    /// Motes at fixed depths. They move with the camera, which is what makes the web read as 3D.
    let dust: [Vec3]

    init() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        dust = (0..<140).map { _ in
            let u = next() * 2 - 1, theta = next() * 2 * .pi, r = 380 + pow(next(), 0.6) * 900
            let s = (1 - u * u).squareRoot()
            return Vec3(r * s * cos(theta), r * u * 0.7, r * s * sin(theta))
        }
    }

    var morphEased: Double { morph * morph * (3 - 2 * morph) }

    /// Where a node is drawn this frame: between its web and timeline positions.
    func position(_ id: AtlasNodeID) -> Vec3? {
        let web = layout.positions[id], line = timeline.positions[id]
        switch (web, line) {
        case let (w?, l?):
            let t = morphEased
            return w + (l - w) * t
        case let (w?, nil): return w
        case let (nil, l?): return l
        default: return nil
        }
    }

    func birthProgress(_ id: AtlasNodeID) -> Double {
        guard let start = born[id] else { return 1 }
        let t = min(1, max(0, (time - start) / 0.7))
        return t * t * (3 - 2 * t)
    }

    var selectionProgress: Double {
        let t = min(1, max(0, (time - selectedAt) / 0.35))
        return t * t * (3 - 2 * t)
    }

    // MARK: Changes

    func reset(graph: AtlasGraph, mode: AtlasMode, bloomFrom origin: AtlasNodeID?) {
        layout = ForceLayout()
        layout.sync(with: graph)
        timeline = AtlasTimeline.layout(graph)
        born = [:]
        selected = nil
        flight = nil
        spinYaw = 0; spinPitch = 0; panVelocity = .zero
        camera = AtlasCamera()
        camera.yaw = Self.webYaw
        camera.pitch = Self.webPitch
        morph = mode == .timeline ? 1 : 0
        morphGoal = morph
        if animates {
            bloom(graph.nodes.keys.filter { $0 != origin }, from: origin)
        } else {
            layout.settle(graph: graph)
        }
        frameAll(selected: nil)
        if !animates { snapFlight() }
    }

    func grow(graph: AtlasGraph, from origin: AtlasNodeID) {
        let before = Set(layout.positions.keys)
        layout.sync(with: graph)
        timeline = AtlasTimeline.layout(graph)
        let added = graph.nodes.keys.filter { !before.contains($0) }
        if animates {
            bloom(added, from: origin)
            layout.reheat(0.75)
        } else {
            layout.settle(graph: graph)
        }
        if morphGoal == 1 { frameAll(selected: selected) }
    }

    /// New nodes start almost on top of their parent and spread out as the layout runs.
    private func bloom(_ ids: [AtlasNodeID], from origin: AtlasNodeID?) {
        let center = origin.flatMap { layout.positions[$0] }
        let now = CACurrentMediaTime()
        for id in ids {
            born[id] = now
            if let center, let p = layout.positions[id] {
                layout.move(id, to: center + (p - center) * 0.12)
            }
        }
    }

    func focus(on id: AtlasNodeID?) {
        selected = id
        selectedAt = CACurrentMediaTime()
        guard let id, let p = position(id) else { return }
        spinYaw = 0; spinPitch = 0; panVelocity = .zero
        let closer = morphGoal == 1 ? nil : min(camera.distance, 560)
        flight = Flight(node: id, target: p, distance: closer, yaw: nil, pitch: nil)
        if !animates { snapFlight() }
    }

    func setMode(_ mode: AtlasMode, selected: AtlasNodeID?) {
        morphGoal = mode == .timeline ? 1 : 0
        if !animates { morph = morphGoal }
        frameAll(selected: selected)
        if !animates { snapFlight() }
    }

    /// Fits the whole map (or centres the selection) for the current mode.
    func frameAll(selected: AtlasNodeID?) {
        let focal = camera.focalLength
        if morphGoal == 1 {
            let width = max(200, timeline.span.upperBound - timeline.span.lowerBound + 160)
            let fit = focal * width / max(200, Double(viewport.width))
            let target = selected.flatMap { timeline.positions[$0] }.map { Vec3($0.x, timeline.axisY, 0) } ?? Vec3(0, timeline.axisY, 0)
            flight = Flight(node: nil, target: target, distance: min(1500, max(420, fit)), yaw: 0, pitch: 0)
        } else {
            let target = selected.flatMap { layout.positions[$0] } ?? centroid()
            flight = Flight(node: selected, target: target, distance: 700, yaw: Self.webYaw, pitch: Self.webPitch)
        }
    }

    private func centroid() -> Vec3 {
        let all = layout.positions.values
        guard !all.isEmpty else { return .zero }
        return all.reduce(Vec3.zero, +) * (1 / Double(all.count))
    }

    private func snapFlight() {
        guard let flight else { return }
        camera.target = flight.node.flatMap { position($0) } ?? flight.target
        if let d = flight.distance { camera.distance = d }
        if let y = flight.yaw { camera.yaw = y }
        if let p = flight.pitch { camera.pitch = p }
        self.flight = nil
    }

    // MARK: Gestures

    func beginInteraction() {
        isInteracting = true
        flight = nil
        spinYaw = 0; spinPitch = 0; panVelocity = .zero
    }

    func drag(dx: Double, dy: Double) {
        if morphGoal == 1 {
            pan(dx: dx, dy: dy)
        } else {
            camera.orbit(dx: dx, dy: dy)
        }
    }

    func endInteraction(velocity: CGSize) {
        isInteracting = false
        guard animates else { return }
        if morphGoal == 1 {
            panVelocity = CGVector(dx: velocity.width, dy: velocity.height)
        } else {
            // orbit() turns 0.008 rad per point.
            spinYaw = max(-5, min(5, Double(velocity.width) * 0.008))
            spinPitch = max(-3, min(3, Double(velocity.height) * 0.008))
        }
    }

    private func pan(dx: Double, dy: Double) {
        let s = camera.focalLength / camera.distance
        let t = camera.target
        camera.target = Vec3(t.x - dx / s, t.y - dy / s, t.z)
    }

    // MARK: Frame

    /// Advances one frame. Returns true while anything is still moving.
    @discardableResult
    func tick(graph: AtlasGraph) -> Bool {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 20, max(0, now - (lastTick ?? now)))
        lastTick = now
        time = now
        var moving = false

        // Physics at a steady 60 Hz whatever the display rate, and only while the web shows.
        if morph < 1, !layout.isSettled {
            if animates {
                stepDebt = min(stepDebt + dt, 3.0 / 60)
                while stepDebt >= 1.0 / 60 {
                    layout.step(graph: graph)
                    stepDebt -= 1.0 / 60
                }
                moving = true
            } else {
                layout.settle(graph: graph)
            }
        }

        if morph != morphGoal {
            let step = dt / 0.9
            morph = morphGoal > morph ? min(morphGoal, morph + step) : max(morphGoal, morph - step)
            moving = true
        }

        if !isInteracting {
            if spinYaw != 0 || spinPitch != 0 {
                camera.yaw += spinYaw * dt
                camera.pitch = min(1.3, max(-1.3, camera.pitch + spinPitch * dt))
                let decay = exp(-dt * 3.2)
                spinYaw *= decay; spinPitch *= decay
                if abs(spinYaw) < 0.01 && abs(spinPitch) < 0.01 { spinYaw = 0; spinPitch = 0 }
                moving = true
            }
            if panVelocity != .zero {
                pan(dx: Double(panVelocity.dx) * dt, dy: Double(panVelocity.dy) * dt)
                let decay = CGFloat(exp(-dt * 3.6))
                panVelocity = CGVector(dx: panVelocity.dx * decay, dy: panVelocity.dy * decay)
                if abs(panVelocity.dx) < 4 && abs(panVelocity.dy) < 4 { panVelocity = .zero }
                moving = true
            }
        }

        if var f = flight {
            if let id = f.node, let p = position(id) { f.target = p }
            flight = f
            let k = 1 - exp(-dt * 4.2)
            let t = camera.target
            camera.target = t + (f.target - t) * k
            var remaining = (f.target - camera.target).length
            if let d = f.distance {
                camera.distance += (d - camera.distance) * k
                remaining += abs(d - camera.distance)
            }
            if let y = f.yaw {
                camera.yaw += angleDelta(from: camera.yaw, to: y) * k
                remaining += abs(angleDelta(from: camera.yaw, to: y)) * 400
            }
            if let p = f.pitch {
                camera.pitch += (p - camera.pitch) * k
                remaining += abs(p - camera.pitch) * 400
            }
            // Keep following a node while the layout is still moving it.
            if remaining < 0.5 && (layout.isSettled || morph == 1) {
                flight = nil
            } else {
                moving = true
            }
        }

        if ambient, animates, selected == nil, !isInteracting, morph == 0, morphGoal == 0, spinYaw == 0 {
            camera.yaw += 0.05 * dt
            moving = true
        }
        if animates, born.values.contains(where: { now - $0 < 0.75 }) { moving = true }
        if animates, now - selectedAt < 0.4 { moving = true }
        if pulses, animates, selected != nil { moving = true }
        return moving
    }

    private func angleDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}

extension AtlasKind {
    /// Pigments for each kind, drawn from the app's ink-and-paper palette.
    var tint: Color {
        switch self {
        case .anime: return Theme.accent
        case .manga: return Theme.accentCool
        case .character: return Color(hex: 0xD98A73)
        case .creator: return Theme.positive
        case .studio: return Theme.textSecondary
        case .theme: return Theme.textTertiary
        }
    }

    var isTitle: Bool { self == .anime || self == .manga }
    var hasPortrait: Bool { self == .anime || self == .manga || self == .character || self == .creator }
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
