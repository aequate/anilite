import Foundation

/// Lays the Atlas out as a chronology: titles sit on a year axis, and the people, studios
/// and themes around them sit in lanes above and below, under the titles they belong to.
///
/// Long gaps between years are compressed so a franchise with a 1998 original and a 2023
/// sequel still fits on one screen.
public struct AtlasTimeline: Sendable {
    public struct Tick: Hashable, Sendable {
        /// nil marks the "unknown year" column at the end.
        public var year: Int?
        public var x: Double
    }

    public enum Lane: Int, CaseIterable, Sendable {
        case studios, creators, titles, characters, themes

        /// -1 above the title row, +1 below it.
        var side: Double {
            switch self {
            case .studios, .creators: return -1
            case .titles: return 0
            case .characters, .themes: return 1
            }
        }

        static func of(_ kind: AtlasKind) -> Lane {
            switch kind {
            case .anime, .manga: return .titles
            case .character: return .characters
            case .creator: return .creators
            case .studio: return .studios
            case .theme: return .themes
            }
        }
    }

    public private(set) var positions: [AtlasNodeID: Vec3] = [:]
    public private(set) var ticks: [Tick] = []
    /// Horizontal extent of the axis, centred on zero.
    public private(set) var span: ClosedRange<Double> = 0...0

    public init() {}

    public static func layout(_ graph: AtlasGraph, yearSpacing: Double = 72, rowGap: Double = 60, laneGap: Double = 44) -> AtlasTimeline {
        var result = AtlasTimeline()
        let titles = graph.nodes.values.filter { Lane.of($0.id.kind) == .titles }
        guard !titles.isEmpty || !graph.nodes.isEmpty else { return result }

        // Columns: one per distinct year, plus one for undated titles.
        let years = Array(Set(titles.compactMap(\.year))).sorted()
        var columnX: [Int: Double] = [:]
        var x = 0.0
        for (index, year) in years.enumerated() {
            if index > 0 {
                let gap = Double(year - years[index - 1])
                x += yearSpacing * min(1.6, max(1, gap.squareRoot()))
            }
            columnX[year] = x
            result.ticks.append(Tick(year: year, x: x))
        }
        let hasUndated = titles.contains { $0.year == nil }
        let undatedX = years.isEmpty ? 0 : x + yearSpacing * 1.4
        if hasUndated { result.ticks.append(Tick(year: nil, x: undatedX)) }

        // Titles stack within their column: 0, -1, +1, -2, +2 … rows from the axis.
        var columns: [Double: [AtlasNode]] = [:]
        for node in titles {
            let cx = node.year.flatMap { columnX[$0] } ?? undatedX
            columns[cx, default: []].append(node)
        }
        var tallest = 1
        for (cx, nodes) in columns {
            let ordered = nodes.sorted { a, b in
                if a.id.kind != b.id.kind { return a.id.kind == .anime }
                if a.weight != b.weight { return a.weight > b.weight }
                return a.id.description < b.id.description
            }
            tallest = max(tallest, ordered.count)
            for (row, node) in ordered.enumerated() {
                let step = Double((row + 1) / 2) * (row % 2 == 0 ? 1 : -1)
                result.positions[node.id] = Vec3(cx, step * rowGap, 0)
            }
        }

        // Everything else hangs under the titles it links to. Voice actors link only to
        // characters, so a second pass places nodes that link to already-placed ones.
        let others = graph.nodes.values.filter { Lane.of($0.id.kind) != .titles }
            .sorted { $0.id.description < $1.id.description }
        var anchorX: [AtlasNodeID: Double] = [:]
        for pass in 0..<2 {
            for node in others where anchorX[node.id] == nil {
                let linked = graph.neighbors(of: node.id).compactMap { id -> Double? in
                    if let p = result.positions[id] { return p.x }
                    return pass == 1 ? anchorX[id] : nil
                }
                if !linked.isEmpty { anchorX[node.id] = linked.reduce(0, +) / Double(linked.count) }
            }
        }

        // Lanes stack outward from the title block. Within a lane, nodes that would overlap
        // drop to the next sub-row.
        let titleHalf = (Double(tallest / 2) + 0.5) * rowGap
        var edgeAbove = titleHalf, edgeBelow = titleHalf
        let laneOrder: [Lane] = [.creators, .studios, .characters, .themes]
        let minGap = 50.0
        for lane in laneOrder {
            let inLane: [AtlasNode] = others.filter { Lane.of($0.id.kind) == lane }
            let members: [(node: AtlasNode, x: Double)] = inLane.map { node in (node: node, x: anchorX[node.id] ?? 0) }
                .sorted { a, b in
                    if a.x != b.x { return a.x < b.x }
                    return a.node.id.description < b.node.id.description
                }
            guard !members.isEmpty else { continue }
            var rowEnds: [Double] = []
            var rowsUsed = 0
            for member in members {
                let node = member.node, nx = member.x
                var row = rowEnds.firstIndex { nx - $0 >= minGap }
                if row == nil {
                    if rowEnds.count < 3 {
                        rowEnds.append(-.infinity)
                        row = rowEnds.count - 1
                    } else {
                        row = rowEnds.indices.min { rowEnds[$0] < rowEnds[$1] }
                    }
                }
                let r = row ?? 0
                rowEnds[r] = max(rowEnds[r], nx)
                rowsUsed = max(rowsUsed, r + 1)
                let base = lane.side < 0 ? edgeAbove : edgeBelow
                let y = lane.side * (base + laneGap * (Double(r) + 1))
                result.positions[node.id] = Vec3(nx, y, 0)
            }
            let height = laneGap * Double(rowsUsed) + laneGap * 0.4
            if lane.side < 0 { edgeAbove += height } else { edgeBelow += height }
        }

        // Centre the whole thing on the origin.
        let xs = result.positions.values.map(\.x)
        let ys = result.positions.values.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return result }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        for (id, p) in result.positions { result.positions[id] = Vec3(p.x - cx, p.y - cy, 0) }
        result.ticks = result.ticks.map { Tick(year: $0.year, x: $0.x - cx) }
        result.axisY = -cy
        result.span = (minX - cx)...(maxX - cx)
        return result
    }

    /// Vertical position of the year axis (the title row) after centring.
    public private(set) var axisY: Double = 0
}
