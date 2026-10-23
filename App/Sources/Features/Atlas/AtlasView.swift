import SwiftUI
import QuartzCore
import AniliteKit

/// Universe Atlas: how titles, characters, creators, studios and themes connect, as a 3D
/// web or as a timeline. Drag to turn (or pan the timeline), pinch to zoom, tap to focus,
/// tap a focused node again to open up its connections. VoiceOver gets a grouped list.
struct AtlasView: View {
    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var atlas = AtlasModel()
    @State private var searchText = ""
    @State private var showsSearch = false
    @State private var showsList = false
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: Double?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground(atmosphere: backdrop, intensity: 0.32)
            content
            header
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if atlas.isEmpty { await atlas.seedFromLibrary(using: model) }
        }
        .onAppear(perform: applyBudget)
        .onChange(of: budget.level) { _, _ in applyBudget() }
    }

    /// The ink behind the map takes on the focused title's colour.
    private var backdrop: Atmosphere {
        guard let node = atlas.node(atlas.selected), node.id.kind.isTitle, let hex = node.colorHex else { return .night }
        return Atmosphere(mode: .stars, palette: ArtworkPalette.from(hex: hex), energy: 0.3, density: 0.5)
    }

    private func applyBudget() {
        atlas.animates = budget.allowsPhysics
        atlas.scene.ambient = budget.level == .full
        atlas.scene.pulses = budget.level == .full
        atlas.wake()
    }

    @ViewBuilder private var content: some View {
        switch atlas.state {
        case .failed(let message):
            VStack(spacing: 16) {
                Spacer()
                EmptyStateView(symbol: "point.3.connected.trianglepath.dotted", title: "Map a universe", message: message,
                               actionTitle: "Search a title") { showsSearch = true; searchFocused = true }
                Spacer()
            }
            .padding(Theme.gutter)
        case .loaded:
            if showsList || voiceOver {
                AtlasList(atlas: atlas)
                    .padding(.top, 150)
            } else {
                canvas
                    .overlay(alignment: .bottom) { selectionCard }
            }
        default:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Charting connections")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atlas")
                        .font(Typo.screenTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let seed = atlas.seedTitle, atlas.state == .loaded {
                        Text("Around \(seed), \(atlas.graph.nodes.count) connections")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    iconButton(showsSearch ? "xmark" : "magnifyingglass", label: showsSearch ? "Close search" : "Search a title") {
                        withAnimation(Motion.standard) { showsSearch.toggle() }
                        searchFocused = showsSearch
                    }
                    if !voiceOver {
                        iconButton(showsList ? "point.3.connected.trianglepath.dotted" : "list.bullet", label: showsList ? "Show map" : "Show as list") {
                            showsList.toggle()
                        }
                    }
                }
            }
            if showsSearch {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Centre the map on a title", text: $searchText)
                        .submitLabel(.go)
                        .focused($searchFocused)
                        .onSubmit {
                            let text = searchText
                            showsSearch = false
                            Task { await atlas.search(text, using: model) }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .surface(interactive: true)
                .transition(.opacity)
            }
            if atlas.state == .loaded {
                if !showsList && !voiceOver {
                    Picker("Layout", selection: Binding(get: { atlas.mode }, set: { mode in
                        Haptics.tick()
                        atlas.setMode(mode)
                    })) {
                        ForEach(AtlasMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                kindFilter
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 42, height: 42)
                .capsuleSurface(interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AtlasKind.allCases, id: \.self) { kind in
                    let count = atlas.count(of: kind)
                    let hidden = atlas.hiddenKinds.contains(kind)
                    if count > 0 {
                        Button {
                            Haptics.tick()
                            atlas.toggle(kind)
                        } label: {
                            HStack(spacing: 6) {
                                KindMark(kind: kind, filled: !hidden)
                                Text("\(kind.label) \(count)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(hidden ? Theme.textTertiary : Theme.textPrimary)
                            .capsuleSurface()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(kind.label), \(count)")
                        .accessibilityValue(hidden ? "Hidden" : "Shown")
                    }
                }
            }
        }
        .padding(.horizontal, -Theme.gutter)
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
    }

    // MARK: Canvas

    private var canvas: some View {
        let nodes = atlas.visibleNodes()
        let images = nodes.filter { $0.id.kind.hasPortrait && $0.imageURL != nil && !$0.isSpoilerHidden }
        let graph = atlas.graph
        let selected = atlas.selected
        let expanded = graph.expanded
        let scene = atlas.scene
        let model = atlas
        return GeometryReader { geo in
            TimelineView(.animation(minimumInterval: budget.level == .full ? nil : 1.0 / 30, paused: !atlas.isLive)) { _ in
                Canvas(rendersAsynchronously: false) { context, size in
                    scene.viewport = size
                    let moving = scene.tick(graph: graph)
                    AtlasPainter(scene: scene, graph: graph, nodes: nodes, selected: selected, expanded: expanded)
                        .draw(in: &context, size: size)
                    if !moving { model.sceneDidSettle() }
                } symbols: {
                    ForEach(images) { node in
                        Group {
                            if node.id.kind.isTitle {
                                RemoteImage(node.imageURL, points: 90, placeholder: node.tint.opacity(0.5))
                                    .frame(width: 60, height: 88)
                                    .clipped()
                            } else {
                                RemoteImage(node.imageURL, points: 60, placeholder: Theme.ink2)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                            }
                        }
                        .tag(node.id)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(coordinateSpace: .local) { location in tap(at: location) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Universe map with \(nodes.count) connected nodes")
            .accessibilityHint("Switch to the list to browse them")
            .onChange(of: geo.size) { _, _ in atlas.wake() }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func tap(at location: CGPoint) {
        let id = hit(location)
        if let id, id == atlas.selected {
            if !atlas.isExpanded(id) {
                Haptics.tap(.soft)
                Task { await atlas.expand(id, using: model) }
            }
            return
        }
        withAnimation(Motion.standard) { atlas.select(id) }
        if id != nil { Haptics.tick() }
    }

    private func hit(_ location: CGPoint) -> AtlasNodeID? {
        var best: (id: AtlasNodeID, depth: Double)?
        for (id, node) in atlas.scene.screen {
            let reach = max(22, node.radius + 6)
            guard hypot(node.center.x - location.x, node.center.y - location.y) <= reach else { continue }
            if best == nil || node.depth < best!.depth { best = (id, node.depth) }
        }
        return best?.id
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if lastDrag == .zero && !atlas.scene.isInteracting { atlas.scene.beginInteraction() }
                let dx = value.translation.width - lastDrag.width
                let dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                atlas.scene.drag(dx: Double(dx), dy: Double(dy))
                atlas.wake()
            }
            .onEnded { value in
                lastDrag = .zero
                atlas.scene.endInteraction(velocity: value.velocity)
                atlas.wake()
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if lastMagnification == nil { atlas.scene.beginInteraction() }
                let previous = lastMagnification ?? 1
                atlas.scene.camera.zoom(by: Double(value.magnification) / previous)
                lastMagnification = Double(value.magnification)
                atlas.wake()
            }
            .onEnded { _ in
                lastMagnification = nil
                atlas.scene.endInteraction(velocity: .zero)
                atlas.wake()
            }
    }

    // MARK: Selection card

    @ViewBuilder private var selectionCard: some View {
        if let node = atlas.node(atlas.selected) {
            AtlasNodeCard(node: node, atlas: atlas)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Dock.height + 16)
                .transition(.opacity.combined(with: .offset(y: 12)))
                .id(node.id)
        }
    }
}

// MARK: - Painter

/// Draws one frame of the Atlas: motes, threads, then nodes from back to front.
@MainActor
private struct AtlasPainter {
    let scene: AtlasScene
    let graph: AtlasGraph
    let nodes: [AtlasNode]
    let selected: AtlasNodeID?
    let expanded: Set<AtlasNodeID>

    private struct Placed {
        var node: AtlasNode
        var proj: AtlasCamera.Projected
        var point: CGPoint
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let camera = scene.camera
        let origin = CGPoint(x: size.width / 2, y: size.height / 2 + 24)
        func screen(_ p: AtlasCamera.Projected) -> CGPoint { CGPoint(x: origin.x + CGFloat(p.x), y: origin.y + CGFloat(p.y)) }

        var placed: [AtlasNodeID: Placed] = [:]
        for node in nodes {
            guard let p = scene.position(node.id), let proj = camera.project(p) else { continue }
            placed[node.id] = Placed(node: node, proj: proj, point: screen(proj))
        }
        let focus: Set<AtlasNodeID> = selected.map { Set(graph.neighbors(of: $0)).union([$0]) } ?? []
        let morph = scene.morphEased

        drawDust(in: &context, camera: camera, screen: screen, fade: 1 - morph)
        if morph > 0.01 { drawRuler(in: &context, size: size, camera: camera, screen: screen, alpha: morph) }
        drawEdges(in: &context, placed: placed, camera: camera, morph: morph)

        var hits: [AtlasNodeID: AtlasScene.ScreenNode] = [:]
        let ordered = placed.values.sorted { $0.proj.depth > $1.proj.depth }
        for item in ordered {
            let radius = drawNode(item, in: &context, camera: camera, focus: focus)
            hits[item.node.id] = AtlasScene.ScreenNode(center: item.point, radius: radius, depth: item.proj.depth)
        }
        scene.screen = hits
    }

    // MARK: Layers

    private func drawDust(in context: inout GraphicsContext, camera: AtlasCamera, screen: (AtlasCamera.Projected) -> CGPoint, fade: Double) {
        guard fade > 0.01 else { return }
        for mote in scene.dust {
            guard let p = camera.project(mote + camera.target) else { continue }
            let near = min(1, max(0, 1.4 - p.depth / (camera.distance + 900)))
            let r = CGFloat(0.6 + near * 1.1)
            let pt = screen(p)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.textPrimary.opacity((0.05 + near * 0.13) * fade)))
        }
    }

    /// Year ruler across the top of the canvas, with faint guides down each column.
    private func drawRuler(in context: inout GraphicsContext, size: CGSize, camera: AtlasCamera, screen: (AtlasCamera.Projected) -> CGPoint, alpha: Double) {
        let timeline = scene.timeline
        let rulerY: CGFloat = 168
        var lastLabelX = -CGFloat.infinity
        for tick in timeline.ticks {
            guard let p = camera.project(Vec3(tick.x, timeline.axisY, 0)) else { continue }
            let x = screen(p).x
            guard x > -40, x < size.width + 40 else { continue }
            var guide = Path()
            guide.move(to: CGPoint(x: x, y: rulerY + 12))
            guide.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(guide, with: .color(Theme.textPrimary.opacity(0.05 * alpha)), lineWidth: 1)
            // Skip labels that would collide when zoomed out.
            guard x - lastLabelX > 34 else { continue }
            lastLabelX = x
            let label = tick.year.map(String.init) ?? "Later"
            let text = context.resolve(Text(label).font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(Theme.textSecondary.opacity(alpha)))
            context.draw(text, at: CGPoint(x: x, y: rulerY), anchor: .center)
        }
    }

    private func drawEdges(in context: inout GraphicsContext, placed: [AtlasNodeID: Placed], camera: AtlasCamera, morph: Double) {
        let selectedTint = graph.nodes[selected ?? AtlasNodeID(.anime, -1)]?.tint ?? Theme.accent
        var focusEdges: [(CGPoint, CGPoint, CGPoint, AtlasEdge)] = []
        for edge in graph.edges {
            guard let a = placed[edge.a], let b = placed[edge.b] else { continue }
            let birth = min(scene.birthProgress(edge.a), scene.birthProgress(edge.b))
            guard birth > 0.02 else { continue }
            var pa = a.point, pb = b.point
            let isFocus = selected != nil && (edge.a == selected || edge.b == selected)
            if isFocus && edge.b == selected { swap(&pa, &pb) }
            let control = Self.control(pa, pb, seed: edge.a.id &+ edge.b.id, bend: 0.16 * (1 - 0.6 * morph))
            var path = Path()
            path.move(to: pa)
            path.addQuadCurve(to: pb, control: control)
            let depth = (a.proj.depth + b.proj.depth) / 2
            let fog = min(1, max(0.2, 1.6 - depth / camera.distance))
            if isFocus {
                context.stroke(path, with: .color(selectedTint.opacity(0.7 * birth)), lineWidth: 1.3)
                focusEdges.append((pa, control, pb, edge))
            } else {
                let base = selected == nil ? 0.17 : 0.05
                context.stroke(path, with: .color(Theme.textPrimary.opacity(base * fog * birth)),
                               lineWidth: CGFloat(0.6 + edge.strength * 0.35))
            }
        }

        // Pulses travel outward from the focused node; labels sit on the thread.
        for (index, item) in focusEdges.enumerated() {
            let (pa, control, pb, edge) = item
            if scene.pulses {
                let phase = (scene.time * 0.42 + Double(index) * 0.137).truncatingRemainder(dividingBy: 1)
                let pt = Self.point(on: pa, control, pb, t: phase)
                let fade = sin(phase * .pi)
                context.fill(Path(ellipseIn: CGRect(x: pt.x - 2.2, y: pt.y - 2.2, width: 4.4, height: 4.4)),
                             with: .color(selectedTint.opacity(0.9 * fade)))
            }
            if focusEdges.count <= 14 {
                let mid = Self.point(on: pa, control, pb, t: 0.5)
                let text = context.resolve(Text(edge.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary))
                let measured = text.measure(in: CGSize(width: 160, height: 20))
                let pill = CGRect(x: mid.x - measured.width / 2 - 6, y: mid.y - measured.height / 2 - 2.5,
                                  width: measured.width + 12, height: measured.height + 5)
                context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(Theme.ink0.opacity(0.85)))
                context.draw(text, at: mid)
            }
        }
    }

    /// Draws a node and returns its hit radius.
    private func drawNode(_ item: Placed, in context: inout GraphicsContext, camera: AtlasCamera, focus: Set<AtlasNodeID>) -> CGFloat {
        let node = item.node
        let id = node.id
        let isSelected = id == selected
        let birth = scene.birthProgress(id)
        let emphasis = isSelected ? scene.selectionProgress : 0
        let scale = CGFloat(min(2.2, max(0.35, item.proj.scale))) * CGFloat(0.45 + 0.55 * birth) * CGFloat(1 + 0.12 * emphasis)
        let fog = min(1, max(0.3, 1.55 - item.proj.depth / camera.distance))
        let dimmed = selected != nil && !focus.contains(id)
        var layer = context
        layer.opacity = (dimmed ? 0.28 : 1) * fog * birth
        let c = item.point
        let weight = CGFloat(0.8 + min(1.5, node.weight) * 0.2)
        let showLabel = isSelected || (selected != nil && focus.contains(id)) || (selected == nil && scale > 0.85)

        switch id.kind {
        case .anime, .manga:
            let w = 27 * scale * weight, h = w * 1.45
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: max(2, 3.5 * scale))
            if node.isSpoilerHidden {
                layer.fill(shape, with: .color(Theme.ink2))
                drawGlyph("eye.slash", in: rect, layer: &layer)
            } else if let symbol = layer.resolveSymbol(id: id) {
                layer.clipToLayer { clip in clip.fill(shape, with: .color(.black)) }
                layer.draw(symbol, in: rect)
                layer = context
                layer.opacity = (dimmed ? 0.28 : 1) * fog * birth
            } else {
                layer.fill(shape, with: .color(node.tint.opacity(0.85)))
                drawGlyph(id.kind.symbol, in: rect, layer: &layer, color: Theme.ink0.opacity(0.7))
            }
            layer.stroke(shape, with: .color(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.16)), lineWidth: isSelected ? 1.5 : 0.6)
            if !expanded.contains(id) && !node.isSpoilerHidden {
                let r = max(2, 2.6 * scale)
                layer.fill(Path(ellipseIn: CGRect(x: rect.maxX - r * 1.2, y: rect.minY - r * 0.8, width: r * 2, height: r * 2)),
                           with: .color(Theme.accent))
            }
            if showLabel { drawLabel(node.title, below: rect.maxY, x: c.x, scale: scale, strong: isSelected, layer: &layer) }
            return max(w, h) / 2

        case .character, .creator:
            let r = 12.5 * scale * weight
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let shape = Path(ellipseIn: rect)
            if node.isSpoilerHidden {
                layer.fill(shape, with: .color(Theme.ink2))
                drawGlyph("eye.slash", in: rect, layer: &layer)
            } else if let symbol = layer.resolveSymbol(id: id) {
                layer.draw(symbol, in: rect)
            } else {
                layer.fill(shape, with: .color(Theme.ink2))
                drawGlyph(id.kind.symbol, in: rect, layer: &layer, color: id.kind.tint)
            }
            layer.stroke(shape, with: .color(isSelected ? Theme.textPrimary : id.kind.tint.opacity(0.55)), lineWidth: isSelected ? 1.5 : 0.8)
            if showLabel { drawLabel(node.title, below: rect.maxY, x: c.x, scale: scale, strong: isSelected, layer: &layer) }
            return r

        case .studio, .theme:
            let isTheme = id.kind == .theme
            let size = max(8.5, (isTheme ? 10 : 11) * min(scale, 1.3))
            let label = isTheme ? "#" + node.title : node.title
            let text = layer.resolve(Text(label).font(.system(size: size, weight: isTheme ? .medium : .semibold))
                .foregroundStyle(isTheme ? Theme.textSecondary : Theme.textPrimary))
            let measured = text.measure(in: CGSize(width: 220, height: 40))
            let pill = CGRect(x: c.x - measured.width / 2 - 8, y: c.y - measured.height / 2 - 4, width: measured.width + 16, height: measured.height + 8)
            let shape = Path(roundedRect: pill, cornerRadius: isTheme ? pill.height / 2 : 4)
            if !isTheme { layer.fill(shape, with: .color(Theme.ink1.opacity(0.92))) }
            layer.stroke(shape, with: .color(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(isTheme ? 0.14 : 0.2)), lineWidth: isSelected ? 1.4 : 0.7)
            layer.draw(text, at: c)
            return max(pill.width, pill.height) / 2
        }
    }

    private func drawGlyph(_ name: String, in rect: CGRect, layer: inout GraphicsContext, color: Color = Theme.textTertiary) {
        var glyph = layer.resolve(Image(systemName: name))
        glyph.shading = .color(color)
        let side = min(rect.width, rect.height) * 0.42
        layer.draw(glyph, in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
    }

    private func drawLabel(_ title: String, below y: CGFloat, x: CGFloat, scale: CGFloat, strong: Bool, layer: inout GraphicsContext) {
        let short = title.count > 22 ? String(title.prefix(21)) + "…" : title
        let text = layer.resolve(Text(short)
            .font(.system(size: max(9.5, 10.5 * min(scale, 1.25)), weight: strong ? .semibold : .medium))
            .foregroundStyle(strong ? Theme.textPrimary : Theme.textSecondary))
        layer.draw(text, at: CGPoint(x: x, y: y + 4), anchor: .top)
    }

    // MARK: Geometry

    static func control(_ a: CGPoint, _ b: CGPoint, seed: Int, bend: Double) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let sign: CGFloat = seed % 2 == 0 ? 1 : -1
        let k = CGFloat(bend) * sign
        return CGPoint(x: mid.x - dy * k, y: mid.y + dx * k)
    }

    static func point(on a: CGPoint, _ c: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
        let t = CGFloat(t), u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
}

/// The small mark used for each kind in the filter row: a tile for titles, a dot for
/// people, a bar for studios and themes, matching how they're drawn on the map.
private struct KindMark: View {
    let kind: AtlasKind
    let filled: Bool

    var body: some View {
        Group {
            switch kind {
            case .anime, .manga:
                RoundedRectangle(cornerRadius: 1.5).frame(width: 7, height: 10)
            case .character, .creator:
                Circle().frame(width: 8, height: 8)
            case .studio, .theme:
                Capsule().frame(width: 11, height: 5)
            }
        }
        .foregroundStyle(filled ? kind.tint : Theme.textTertiary.opacity(0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Selection card

private struct AtlasNodeCard: View {
    let node: AtlasNode
    let atlas: AtlasModel

    @Environment(AppModel.self) private var model

    var body: some View {
        let bridges = atlas.graph.bridges(from: node.id, limit: 3)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.id.kind.label.dropLast(node.id.kind == .anime || node.id.kind == .manga ? 0 : 1))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(node.id.kind.tint)
                    Text(node.title)
                        .font(Typo.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let subtitle = node.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(Motion.standard) { atlas.select(nil) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Close")
            }

            if !bridges.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Also connected")
                    ForEach(Array(bridges.enumerated()), id: \.offset) { pair in
                        let bridge = pair.element
                        Button {
                            withAnimation(Motion.standard) { atlas.select(bridge.0.id) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(bridge.0.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("through " + bridge.1.prefix(2).map(\.title).joined(separator: " and "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                if !node.isSpoilerHidden {
                    NavigationLink(value: node.route) {
                        Text("Open").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if !atlas.isExpanded(node.id) && !node.isSpoilerHidden {
                    Button {
                        Task { await atlas.expand(node.id, using: model) }
                    } label: {
                        Group {
                            if atlas.expanding.contains(node.id) {
                                ProgressView()
                            } else {
                                Text("Show connections")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    atlas.recenter()
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Frame the map")
            }
        }
        .padding(16)
        .surface(tint: node.tint)
    }

    @ViewBuilder private var thumbnail: some View {
        let isTitle = node.id.kind.isTitle
        let shape = RoundedRectangle(cornerRadius: isTitle ? Theme.cornerCover : 26, style: .continuous)
        ZStack {
            shape.fill(Theme.ink2)
            if node.isSpoilerHidden {
                Image(systemName: "eye.slash").foregroundStyle(Theme.textTertiary)
            } else if let url = node.imageURL {
                RemoteImage(url, points: 72)
            } else {
                Image(systemName: node.id.kind.symbol).foregroundStyle(node.id.kind.tint)
            }
        }
        .frame(width: isTitle ? 44 : 52, height: isTitle ? 64 : 52)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
    }
}

/// Accessible list form of the atlas.
private struct AtlasList: View {
    let atlas: AtlasModel
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(AtlasKind.allCases, id: \.self) { kind in
                let nodes = atlas.graph.nodeList.filter { $0.id.kind == kind }.sorted { $0.weight > $1.weight }
                if !nodes.isEmpty {
                    Section(kind.label) {
                        ForEach(nodes) { node in
                            HStack {
                                if node.isSpoilerHidden {
                                    Label("Hidden entry", systemImage: "eye.slash")
                                        .foregroundStyle(Theme.textTertiary)
                                } else {
                                    NavigationLink(value: node.route) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(node.title).foregroundStyle(Theme.textPrimary)
                                            if let subtitle = node.subtitle {
                                                Text(subtitle).font(.caption).foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Theme.ink1)
                            .swipeActions(edge: .trailing) {
                                if !atlas.isExpanded(node.id) && !node.isSpoilerHidden {
                                    Button("Expand") { Task { await atlas.expand(node.id, using: model) } }
                                        .tint(Theme.accentCool)
                                }
                            }
                            .accessibilityAction(named: "Show connections") {
                                Task { await atlas.expand(node.id, using: model) }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 20, for: .scrollContent)
    }
}
