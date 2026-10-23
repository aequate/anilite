import SwiftUI
import AniliteKit

/// Universe Atlas: an explorable 3D (or flat 2D) map of how titles, characters, creators,
/// studios and themes connect. Drag to orbit, pinch to zoom, tap to inspect, double-tap
/// to expand. VoiceOver users get an equivalent grouped list.
struct AtlasView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(EffectsBudget.self) private var budget
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var atlas = AtlasModel()
    @State private var searchText = ""
    @State private var showsSearch = false
    @State private var showsList = false
    @State private var dragStart: CGSize = .zero
    @State private var zoomStart: Double?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground(atmosphere: .night, intensity: 0.35)
            content
            header
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if atlas.isEmpty { await atlas.seedFromLibrary(using: model) }
        }
        .onAppear(perform: startSimulation)
        .onDisappear { atlas.stopSimulation() }
        .onChange(of: budget.level) { _, _ in startSimulation() }
    }

    private func startSimulation() {
        if budget.allowsPhysics && budget.level > .still {
            atlas.startSimulation(interval: budget.frameInterval, autoRotate: budget.level == .full)
        } else {
            atlas.stopSimulation()
        }
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
                    .padding(.top, 120)
            } else {
                canvas
                    .overlay(alignment: .bottom) { selectionCard }
            }
        default:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Charting connections…")
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
                        Text("The universe around \(seed) · \(atlas.graph.nodes.count) nodes")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    iconButton(showsSearch ? "xmark" : "magnifyingglass", label: showsSearch ? "Close search" : "Search a title") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showsSearch.toggle() }
                        searchFocused = showsSearch
                    }
                    if !voiceOver {
                        iconButton(atlas.isFlat ? "cube" : "square.grid.3x3", label: atlas.isFlat ? "Switch to 3D" : "Switch to 2D") {
                            Haptics.tap(.soft)
                            withAnimation(.easeInOut(duration: 0.4)) { atlas.setFlat(!atlas.isFlat) }
                        }
                        iconButton(showsList ? "circle.hexagongrid" : "list.bullet", label: showsList ? "Show map" : "Show as list") {
                            showsList.toggle()
                        }
                    }
                }
            }
            if showsSearch {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.brandCool)
                    TextField("Center the map on a title", text: $searchText)
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
                .glassSurface(cornerRadius: 18, interactive: true)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if atlas.state == .loaded { kindFilter }
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
                .glassCapsule(interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AtlasKind.allCases, id: \.self) { kind in
                    let count = atlas.count(of: kind)
                    if count > 0 {
                        Button {
                            Haptics.tick()
                            if atlas.hiddenKinds.contains(kind) { atlas.hiddenKinds.remove(kind) } else { atlas.hiddenKinds.insert(kind) }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(kind.tint).frame(width: 8, height: 8)
                                Text("\(kind.label) \(count)")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(atlas.hiddenKinds.contains(kind) ? Theme.textTertiary : Theme.textPrimary)
                            .glassCapsule()
                            .opacity(atlas.hiddenKinds.contains(kind) ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(kind.label), \(count)")
                        .accessibilityValue(atlas.hiddenKinds.contains(kind) ? "Hidden" : "Shown")
                    }
                }
            }
        }
        .padding(.horizontal, -Theme.gutter)
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let nodes = atlas.visibleNodes()
            let portraits = nodes.filter { $0.id.kind.hasPortrait && $0.imageURL != nil && !$0.isSpoilerHidden }
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size, nodes: nodes)
            } symbols: {
                ForEach(portraits) { node in
                    RemoteImage(node.imageURL, points: 64, placeholder: node.tint.opacity(0.4))
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .tag(node.id)
                }
            }
            .contentShape(Rectangle())
            .gesture(orbitGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                if let id = hit(location, size: size, nodes: nodes) {
                    atlas.selected = id
                    Task { await atlas.expand(id, using: model) }
                }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                let id = hit(location, size: size, nodes: nodes)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { atlas.selected = id }
                if id != nil { Haptics.tick() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Universe map with \(nodes.count) connected nodes")
            .accessibilityHint("Turn on VoiceOver list mode to browse them")
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func screenPoint(_ p: AtlasCamera.Projected, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + CGFloat(p.x), y: size.height / 2 + 30 + CGFloat(p.y))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, nodes: [AtlasNode]) {
        let camera = atlas.camera
        let positions = atlas.layout.positions
        var projected: [AtlasNodeID: AtlasCamera.Projected] = [:]
        for node in nodes {
            if let p = positions[node.id], let proj = camera.project(p) { projected[node.id] = proj }
        }
        let selected = atlas.selected
        let focus: Set<AtlasNodeID> = selected.map { Set(atlas.graph.neighbors(of: $0)).union([$0]) } ?? []

        // Edges first, faded by depth; the selection's edges glow.
        for edge in atlas.graph.edges {
            guard let a = projected[edge.a], let b = projected[edge.b] else { continue }
            let pa = screenPoint(a, size: size), pb = screenPoint(b, size: size)
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            let isFocus = selected != nil && (edge.a == selected || edge.b == selected)
            let depthFade = min(1, max(0.15, 1.6 - (a.depth + b.depth) / 2 / camera.distance))
            let alpha = isFocus ? 0.75 : (selected == nil ? 0.22 : 0.07) * depthFade
            let color = isFocus ? (atlas.node(selected)?.tint ?? Theme.brandCool) : Color.white
            context.stroke(path, with: .color(color.opacity(alpha)), lineWidth: isFocus ? 1.6 : CGFloat(0.6 + edge.strength * 0.4))
            if isFocus {
                let mid = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
                let label = context.resolve(Text(edge.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textSecondary))
                context.draw(label, at: mid)
            }
        }

        // Nodes back to front.
        let ordered = nodes.compactMap { node -> (AtlasNode, AtlasCamera.Projected)? in
            guard let p = projected[node.id] else { return nil }
            return (node, p)
        }.sorted { $0.1.depth > $1.1.depth }

        for (node, p) in ordered {
            let center = screenPoint(p, size: size)
            let scale = CGFloat(min(2.2, max(0.35, p.scale)))
            let radius = node.id.kind.radius * scale * CGFloat(0.75 + min(1.5, node.weight) * 0.25)
            let dimmed = selected != nil && !focus.contains(node.id)
            let fog = min(1, max(0.25, 1.5 - p.depth / camera.distance))
            var layer = context
            layer.opacity = (dimmed ? 0.28 : 1) * fog
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            if node.id == selected {
                let halo = rect.insetBy(dx: -radius * 0.9, dy: -radius * 0.9)
                layer.fill(Path(ellipseIn: halo), with: .radialGradient(Gradient(colors: [node.tint.opacity(0.55), .clear]),
                                                                       center: center, startRadius: radius * 0.6, endRadius: halo.width / 2))
            }

            if node.id.kind == .theme {
                layer.fill(Path(roundedRect: rect.insetBy(dx: -radius * 0.6, dy: 0), cornerRadius: radius), with: .color(node.tint.opacity(0.28)))
                let label = layer.resolve(Text("#" + node.title).font(.system(size: max(8, 10 * scale), weight: .semibold)).foregroundStyle(Theme.textPrimary))
                layer.draw(label, at: center)
                continue
            }

            layer.fill(Path(ellipseIn: rect), with: .color(node.tint.opacity(0.9)))
            if node.isSpoilerHidden {
                let glyph = layer.resolve(Image(systemName: "eye.slash.fill"))
                layer.draw(glyph, in: rect.insetBy(dx: radius * 0.45, dy: radius * 0.45))
            } else if let symbol = layer.resolveSymbol(id: node.id) {
                layer.draw(symbol, in: rect.insetBy(dx: 1.5, dy: 1.5))
            } else {
                var glyph = layer.resolve(Image(systemName: node.id.kind.symbol))
                glyph.shading = .color(.black.opacity(0.7))
                layer.draw(glyph, in: rect.insetBy(dx: radius * 0.5, dy: radius * 0.5))
            }
            layer.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(node.id == selected ? 0.95 : 0.35)), lineWidth: node.id == selected ? 2 : 0.8)
            if atlas.isExpanded(node.id) == false, node.id.kind == .anime || node.id.kind == .manga {
                // A small notch marks nodes that can still be expanded.
                let dot = CGRect(x: rect.maxX - radius * 0.45, y: rect.minY, width: radius * 0.45, height: radius * 0.45)
                layer.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.85)))
            }

            if scale > 0.8 || node.id == selected || (focus.contains(node.id) && selected != nil) {
                let title = node.title.count > 22 ? String(node.title.prefix(21)) + "…" : node.title
                let text = layer.resolve(Text(title)
                    .font(.system(size: max(9, 11 * min(scale, 1.3)), weight: node.id == selected ? .bold : .medium))
                    .foregroundStyle(Theme.textPrimary))
                layer.draw(text, at: CGPoint(x: center.x, y: rect.maxY + 9))
            }
        }
    }

    private func hit(_ location: CGPoint, size: CGSize, nodes: [AtlasNode]) -> AtlasNodeID? {
        var best: (AtlasNodeID, CGFloat, Double)?
        for node in nodes {
            guard let p = atlas.layout.positions[node.id], let proj = atlas.camera.project(p) else { continue }
            let center = screenPoint(proj, size: size)
            let scale = CGFloat(min(2.2, max(0.35, proj.scale)))
            let radius = max(22, node.id.kind.radius * scale + 8)
            let distance = hypot(center.x - location.x, center.y - location.y)
            guard distance <= radius else { continue }
            // Prefer the nearest-to-camera node when they overlap.
            if best == nil || proj.depth < best!.2 { best = (node.id, distance, proj.depth) }
        }
        return best?.0
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                atlas.isInteracting = true
                let dx = value.translation.width - dragStart.width
                let dy = value.translation.height - dragStart.height
                dragStart = value.translation
                if atlas.isFlat {
                    atlas.pan(dx: Double(dx), dy: Double(dy))
                } else {
                    atlas.camera.orbit(dx: Double(dx), dy: Double(dy))
                }
            }
            .onEnded { _ in
                dragStart = .zero
                atlas.isInteracting = false
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                atlas.isInteracting = true
                let previous = zoomStart ?? 1
                atlas.camera.zoom(by: Double(value.magnification) / previous)
                zoomStart = Double(value.magnification)
            }
            .onEnded { _ in
                zoomStart = nil
                atlas.isInteracting = false
                Haptics.tick()
            }
    }

    // MARK: Selection card

    @ViewBuilder private var selectionCard: some View {
        if let node = atlas.node(atlas.selected) {
            AtlasNodeCard(node: node, atlas: atlas)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Dock.height + 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(node.id)
        }
    }
}

private struct AtlasNodeCard: View {
    let node: AtlasNode
    let atlas: AtlasModel

    @Environment(AppModel.self) private var model

    var body: some View {
        let bridges = atlas.graph.bridges(from: node.id, limit: 3)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(node.tint.opacity(0.85))
                    if node.isSpoilerHidden {
                        Image(systemName: "eye.slash.fill").foregroundStyle(.black.opacity(0.7))
                    } else if let url = node.imageURL {
                        RemoteImage(url, points: 52).clipShape(Circle())
                    } else {
                        Image(systemName: node.id.kind.symbol).foregroundStyle(.black.opacity(0.7))
                    }
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: node.id.kind.label, color: node.id.kind.tint)
                    Text(node.title)
                        .font(.headline)
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { atlas.selected = nil }
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
                    Eyebrow(text: "Unexpected connections")
                    ForEach(Array(bridges.enumerated()), id: \.offset) { pair in
                        let bridge = pair.element
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { atlas.selected = bridge.0.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(bridge.0.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("via " + bridge.1.prefix(2).map(\.title).joined(separator: ", "))
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
                        Label("Open", systemImage: "arrow.up.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlowButtonStyle(tint: node.tint))
                }
                if !atlas.isExpanded(node.id) && !node.isSpoilerHidden {
                    Button {
                        Task { await atlas.expand(node.id, using: model) }
                    } label: {
                        if atlas.expanding.contains(node.id) {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Expand", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) { atlas.center(on: node.id) }
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("Center map here")
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 24, tint: node.tint)
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
                            .listRowBackground(Color.white.opacity(0.04))
                            .swipeActions(edge: .trailing) {
                                if !atlas.isExpanded(node.id) && !node.isSpoilerHidden {
                                    Button("Expand") { Task { await atlas.expand(node.id, using: model) } }
                                        .tint(Theme.brand)
                                }
                            }
                            .accessibilityAction(named: "Expand connections") {
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
