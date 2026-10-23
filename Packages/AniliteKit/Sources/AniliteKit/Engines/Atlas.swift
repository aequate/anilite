import Foundation

/// A node in the Universe Atlas knowledge graph.
public enum AtlasKind: String, CaseIterable, Codable, Sendable {
    case anime, manga, character, creator, studio, theme

    public var label: String {
        switch self {
        case .anime: return "Anime"
        case .manga: return "Manga"
        case .character: return "Characters"
        case .creator: return "Creators"
        case .studio: return "Studios"
        case .theme: return "Themes"
        }
    }

    public var symbol: String {
        switch self {
        case .anime: return "play.rectangle.fill"
        case .manga: return "book.fill"
        case .character: return "person.fill"
        case .creator: return "paintbrush.pointed.fill"
        case .studio: return "building.2.fill"
        case .theme: return "number"
        }
    }

    /// Visual weight of the node (radius multiplier).
    var mass: Double {
        switch self {
        case .anime, .manga: return 1.4
        case .studio, .creator: return 1.1
        case .character: return 0.9
        case .theme: return 0.75
        }
    }
}

public struct AtlasNodeID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var kind: AtlasKind
    public var id: Int
    public init(_ kind: AtlasKind, _ id: Int) { self.kind = kind; self.id = id }
    public var description: String { "\(kind.rawValue):\(id)" }
}

public struct AtlasNode: Hashable, Sendable, Identifiable {
    public var id: AtlasNodeID
    public var title: String
    public var subtitle: String?
    public var imageURL: String?
    public var colorHex: String?
    public var isSpoilerHidden: Bool
    public var weight: Double
}

public struct AtlasEdge: Hashable, Sendable {
    public var a: AtlasNodeID
    public var b: AtlasNodeID
    public var label: String
    public var strength: Double
}

public struct AtlasGraph: Sendable {
    public private(set) var nodes: [AtlasNodeID: AtlasNode] = [:]
    public private(set) var edges: [AtlasEdge] = []
    public private(set) var expanded: Set<AtlasNodeID> = []
    private var edgeKeys: Set<String> = []
    public var maxNodes = 160

    public init() {}

    public var nodeList: [AtlasNode] { Array(nodes.values) }

    public func neighbors(of id: AtlasNodeID) -> [AtlasNodeID] {
        edges.compactMap { $0.a == id ? $0.b : ($0.b == id ? $0.a : nil) }
    }

    @discardableResult
    mutating func add(_ node: AtlasNode) -> Bool {
        if var existing = nodes[node.id] {
            existing.weight = max(existing.weight, node.weight)
            if existing.imageURL == nil { existing.imageURL = node.imageURL }
            nodes[node.id] = existing
            return true
        }
        guard nodes.count < maxNodes else { return false }
        nodes[node.id] = node
        return true
    }

    mutating func link(_ a: AtlasNodeID, _ b: AtlasNodeID, _ label: String, _ strength: Double = 1) {
        guard a != b, nodes[a] != nil, nodes[b] != nil else { return }
        let key = [a.description, b.description].sorted().joined(separator: "|")
        guard edgeKeys.insert(key).inserted else { return }
        edges.append(AtlasEdge(a: a, b: b, label: label, strength: strength))
    }

    static func mediaNode(_ m: Media, hidden: Bool = false, weight: Double = 1) -> AtlasNode {
        AtlasNode(
            id: AtlasNodeID(m.mediaType == .anime ? .anime : .manga, m.id),
            title: hidden ? "Hidden entry" : m.titleText,
            subtitle: [m.formatLabel, m.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
            imageURL: hidden ? nil : m.coverImage?.thumbnail,
            colorHex: m.coverImage?.color,
            isSpoilerHidden: hidden,
            weight: weight
        )
    }

    /// Adds a title's world: franchise relations, main cast, creators, studio and themes.
    public mutating func expand(media m: Media, library: Library = .empty, policy: SpoilerPolicy = SpoilerPolicy()) {
        let center = Self.mediaNode(m, weight: 1.5)
        add(center)
        expanded.insert(center.id)
        let ctx = SpoilerContext(media: m, entry: library.entry(for: m.id))

        for edge in m.relationEdges {
            guard let type = edge.relationType, let node = edge.node, type != .character || (node.popularity ?? 0) > 20_000 else { continue }
            if node.format == .music { continue }
            let visibility = SpoilerShield.relation(type, base: ctx, policy: policy)
            let n = Self.mediaNode(node, hidden: !visibility.isVisible, weight: 1)
            if add(n) { link(center.id, n.id, type.label, type == .sequel || type == .prequel || type == .source || type == .adaptation ? 1.4 : 0.8) }
        }

        let cast = (m.characters?.edges ?? []).filter { $0.role == .main }.prefix(6)
        for (index, edge) in cast.enumerated() {
            guard let c = edge.node else { continue }
            let vis = SpoilerShield.character(role: edge.role, description: c.description, index: index, context: ctx, policy: policy)
            let node = AtlasNode(id: AtlasNodeID(.character, c.id), title: c.name?.full ?? "Character", subtitle: "Main character",
                                 imageURL: c.image?.best, colorHex: nil, isSpoilerHidden: !vis.showCard.isVisible, weight: 0.8)
            if add(node) { link(center.id, node.id, "Character", 1) }
            if let va = edge.voiceActors?.first {
                let vaNode = AtlasNode(id: AtlasNodeID(.creator, va.id), title: va.name?.full ?? "Voice actor", subtitle: "Voice actor",
                                       imageURL: va.image?.best, colorHex: nil, isSpoilerHidden: false, weight: 0.6)
                if add(vaNode) { link(node.id, vaNode.id, "Voiced by", 0.6) }
            }
        }

        let keyRoles = ["Original Creator", "Original Story", "Director", "Story & Art", "Story", "Art", "Series Composition", "Music", "Character Design"]
        let staff = (m.staff?.edges ?? []).filter { e in keyRoles.contains { (e.role ?? "").hasPrefix($0) } }.prefix(5)
        for e in staff {
            guard let s = e.node else { continue }
            let node = AtlasNode(id: AtlasNodeID(.creator, s.id), title: s.name?.full ?? "Creator", subtitle: e.role,
                                 imageURL: s.image?.best, colorHex: nil, isSpoilerHidden: false, weight: 1)
            if add(node) { link(center.id, node.id, e.role ?? "Staff", 1.1) }
        }

        for studio in (m.studios?.nodes ?? []).prefix(2) {
            let node = AtlasNode(id: AtlasNodeID(.studio, studio.id), title: studio.name, subtitle: "Studio", imageURL: nil, colorHex: nil, isSpoilerHidden: false, weight: 1)
            if add(node) { link(center.id, node.id, "Animated by", 1.1) }
        }

        for tag in m.safeTags.prefix(4) where (tag.rank ?? 0) >= 70 {
            let node = AtlasNode(id: AtlasNodeID(.theme, tag.id), title: tag.name, subtitle: tag.category, imageURL: nil, colorHex: nil, isSpoilerHidden: false, weight: 0.7)
            if add(node) { link(center.id, node.id, "Theme", 0.7) }
        }
    }

    /// Adds every other title a person, character or studio is connected to.
    public mutating func expand(hub: AtlasNodeID, works: [Media], label: String, limit: Int = 10) {
        guard nodes[hub] != nil else { return }
        expanded.insert(hub)
        let sorted = works.filter { !($0.isAdult ?? false) && $0.format != .music }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        var seen = Set<Int>()
        for m in sorted where seen.insert(m.id).inserted {
            if seen.count > limit { break }
            let n = Self.mediaNode(m, weight: 0.9)
            if add(n) { link(hub, n.id, label, 0.8) }
        }
    }

    /// Titles in the graph that share this node's neighbours — "unexpected connections".
    public func bridges(from id: AtlasNodeID, limit: Int = 5) -> [(AtlasNode, [AtlasNode])] {
        let mine = Set(neighbors(of: id))
        var counts: [AtlasNodeID: [AtlasNodeID]] = [:]
        for hub in mine where hub.kind != .anime && hub.kind != .manga {
            for other in neighbors(of: hub) where other != id && (other.kind == .anime || other.kind == .manga) && !mine.contains(other) {
                counts[other, default: []].append(hub)
            }
        }
        return counts.sorted { $0.value.count > $1.value.count }.prefix(limit).compactMap { key, hubs in
            guard let node = nodes[key] else { return nil }
            return (node, hubs.compactMap { nodes[$0] })
        }
    }
}

// MARK: - 3D force layout

public struct Vec3: Hashable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    var length: Double { sqrt(x * x + y * y + z * z) }
}

/// Deterministic force-directed layout (springs + repulsion + centering) in 3D.
/// O(n²) per step, which is fine for the Atlas' bounded node count.
public struct ForceLayout: Sendable {
    public private(set) var positions: [AtlasNodeID: Vec3] = [:]
    private var velocities: [AtlasNodeID: Vec3] = [:]
    public var pinned: Set<AtlasNodeID> = []
    public private(set) var temperature: Double = 1
    public var restLength: Double = 90
    public var repulsion: Double = 9000
    public var springK: Double = 0.04
    public var damping: Double = 0.82
    public var flat = false

    public init() {}

    public var isSettled: Bool { temperature < 0.02 }

    /// Places new nodes near a connected neighbour (or on a sphere) using a stable hash.
    public mutating func sync(with graph: AtlasGraph) {
        for id in positions.keys where graph.nodes[id] == nil {
            positions[id] = nil
            velocities[id] = nil
        }
        var added = false
        let order = graph.nodes.keys.sorted { $0.description < $1.description }
        for id in order where positions[id] == nil {
            let seed = Double(StableHash.value(id.description) % 10_000) / 10_000
            let seed2 = Double(StableHash.value(id.description + "#") % 10_000) / 10_000
            let anchor = graph.neighbors(of: id).compactMap { positions[$0] }.first ?? .zero
            let theta = seed * 2 * .pi
            let phi = acos(2 * seed2 - 1)
            let r = restLength * (anchor == .zero ? 1.5 : 0.9)
            var p = anchor + Vec3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
            if flat { p.z = 0 }
            positions[id] = p
            velocities[id] = .zero
            added = true
        }
        if added { temperature = max(temperature, 0.6) }
    }

    public mutating func reheat(_ t: Double = 0.8) { temperature = max(temperature, t) }

    /// Advances the simulation one step. Returns false once settled.
    @discardableResult
    public mutating func step(graph: AtlasGraph, dt: Double = 1) -> Bool {
        guard !isSettled else { return false }
        let ids = Array(positions.keys)
        var forces = Dictionary(uniqueKeysWithValues: ids.map { ($0, Vec3.zero) })

        for i in 0..<ids.count {
            let a = ids[i]
            guard let pa = positions[a] else { continue }
            for j in (i + 1)..<max(i + 1, ids.count) where j < ids.count {
                let b = ids[j]
                guard let pb = positions[b] else { continue }
                var d = pa - pb
                var dist = d.length
                if dist < 0.01 {
                    d = Vec3(0.5 - Double(i % 3) * 0.3, 0.3, 0.1)
                    dist = d.length
                }
                let massA = graph.nodes[a]?.id.kind.mass ?? 1, massB = graph.nodes[b]?.id.kind.mass ?? 1
                let f = repulsion * massA * massB / (dist * dist)
                let push = d * (f / dist)
                forces[a] = forces[a]! + push
                forces[b] = forces[b]! - push
            }
        }
        for e in graph.edges {
            guard let pa = positions[e.a], let pb = positions[e.b] else { continue }
            let d = pb - pa
            let dist = max(0.01, d.length)
            let target = restLength / max(0.5, e.strength)
            let pull = d * (springK * e.strength * (dist - target) / dist)
            forces[e.a] = forces[e.a]! + pull
            forces[e.b] = forces[e.b]! - pull
        }

        var energy = 0.0
        for id in ids {
            guard !pinned.contains(id), var p = positions[id], var v = velocities[id] else { continue }
            // Gentle gravity keeps disconnected clusters on screen.
            let f = forces[id]! - p * 0.012
            v = (v + f * (dt * temperature)) * damping
            let speed = v.length
            let cap = 40.0
            if speed > cap { v = v * (cap / speed) }
            p = p + v * dt
            if flat { p.z = 0; v.z = 0 }
            positions[id] = p
            velocities[id] = v
            energy += v.length
        }
        let mean = ids.isEmpty ? 0 : energy / Double(ids.count)
        temperature = max(0, temperature * 0.985 - (mean < 0.15 ? 0.02 : 0))
        return !isSettled
    }

    public mutating func settle(graph: AtlasGraph, maxSteps: Int = 600) {
        var n = 0
        while step(graph: graph) && n < maxSteps { n += 1 }
    }

    public mutating func move(_ id: AtlasNodeID, to p: Vec3) {
        positions[id] = p
        velocities[id] = .zero
        reheat(0.3)
    }
}

/// Orbit camera that projects 3D positions to the screen with perspective.
public struct AtlasCamera: Hashable, Sendable {
    public var yaw: Double = 0.4
    public var pitch: Double = -0.25
    public var distance: Double = 700
    public var focalLength: Double = 600
    public var target: Vec3 = .zero

    public init() {}

    public struct Projected: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var scale: Double
        public var depth: Double
    }

    public func project(_ p: Vec3) -> Projected? {
        let q = p - target
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let x1 = cy * q.x + sy * q.z
        let z1 = -sy * q.x + cy * q.z
        let y2 = cp * q.y - sp * z1
        let z2 = sp * q.y + cp * z1
        let depth = z2 + distance
        guard depth > 40 else { return nil }
        let s = focalLength / depth
        return Projected(x: x1 * s, y: y2 * s, scale: s, depth: depth)
    }

    public mutating func orbit(dx: Double, dy: Double) {
        yaw += dx * 0.008
        pitch = min(1.3, max(-1.3, pitch + dy * 0.008))
    }

    public mutating func zoom(by factor: Double) {
        distance = min(2200, max(180, distance / factor))
    }
}
