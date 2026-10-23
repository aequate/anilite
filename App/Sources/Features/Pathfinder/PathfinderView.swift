import SwiftUI
import AniliteKit

/// Walks a franchise's relations (a few batched requests, never one per title) and builds
/// watch/read routes from the resulting graph.
@MainActor
@Observable
final class PathfinderModel {
    let mediaId: Int
    private(set) var graph: FranchiseGraph?
    private(set) var routes: [FranchiseRoute] = []
    private(set) var state: LoadState = .idle
    private(set) var isExpanding = false
    private(set) var atmosphere: Atmosphere = .brand

    /// Each round is one request covering up to 50 titles; four rounds map even the
    /// largest franchises without straining AniList's rate limit.
    private let maxRounds = 4

    init(mediaId: Int) { self.mediaId = mediaId }

    func load(client: AniListClient) async {
        guard state != .loading else { return }
        state = .loading
        do {
            let seed = try await client.fetch(Queries.detail(id: mediaId), policy: .cacheFirst).Media
            var graph = FranchiseGraph(seed: seed)
            self.graph = graph
            routes = Pathfinder.routes(for: graph)
            state = .loaded
            let palette = await ImagePipeline.shared.palette(for: seed.coverImage?.thumbnail, hint: seed.coverImage?.color)
            atmosphere = Atmosphere.resolve(for: seed, palette: palette)

            isExpanding = true
            defer { isExpanding = false }
            for _ in 0..<maxRounds {
                let frontier = graph.frontier(limit: 50)
                guard !frontier.isEmpty, !Task.isCancelled else { break }
                let batch = try await client.fetch(Queries.relationsBatch(ids: frontier), policy: .cacheFirst).Page.media
                for media in batch { graph.merge(media) }
                // Titles AniList didn't return are marked expanded so we never loop on them.
                let returned = Set(batch.map(\.id))
                for id in frontier where !returned.contains(id) {
                    if var known = graph.nodes[id] {
                        known.relations = known.relations ?? RelationConnection(edges: [])
                        graph.merge(known)
                    }
                }
                self.graph = graph
                withAnimation(Motion.gentle) {
                    routes = Pathfinder.routes(for: graph)
                }
            }
        } catch is CancellationError {
            if graph == nil { state = .idle }
        } catch {
            if graph == nil {
                state = .failed(AppModel.message(for: error))
            }
        }
    }
}

struct PathfinderView: View {
    let mediaId: Int

    @Environment(AppModel.self) private var model
    @State private var pathfinder: PathfinderModel
    @State private var kind: RouteKind = .essentials

    init(mediaId: Int) {
        self.mediaId = mediaId
        _pathfinder = State(initialValue: PathfinderModel(mediaId: mediaId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch pathfinder.state {
                case .failed(let message):
                    ErrorBanner(message: message) { Task { await pathfinder.load(client: model.client) } }
                case .loaded:
                    content
                default:
                    LoadingPlaceholder()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenChrome("Watch Order", atmosphere: pathfinder.atmosphere)
        .task { await pathfinder.load(client: model.client) }
    }

    @ViewBuilder private var content: some View {
        let available = pathfinder.routes
        if available.isEmpty {
            EmptyStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "A single journey",
                           message: "This title has no sequels, prequels or adaptations to order.")
        } else {
            let route = available.first { $0.kind == kind } ?? available[0]
            routePicker(available)
            RouteSummary(route: route, isExpanding: pathfinder.isExpanding)
            RouteTimeline(route: route)
            if let point = route.continuePoint {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Then keep going in the manga")
                    Text(point.headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(point.detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let id = point.sourceId {
                        NavigationLink(value: Route.media(id)) {
                            Label("Open \(point.sourceTitle ?? "the source")", systemImage: "book.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(16)
                .surface(tint: Theme.accentCool)
            }
            PlanRouteButton(route: route)
            Text("Routes are built from AniList's relation data. Filler lists come from a hand-checked guide and cover the long-running shows that need one.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func routePicker(_ routes: [FranchiseRoute]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(routes) { route in
                    Button {
                        Haptics.tick()
                        withAnimation(Motion.standard) { kind = route.kind }
                    } label: {
                        Chip(label: route.kind.title, symbol: route.kind.symbol, isSelected: route.kind == kind)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, -Theme.gutter)
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
        .padding(.top, 8)
    }
}

private struct RouteSummary: View {
    let route: FranchiseRoute
    let isExpanding: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let done = route.completedSteps(in: model.library)
        let required = route.steps.filter { !$0.isOptional }.count
        let remaining = route.remainingMinutes(in: model.library)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.kind.title)
                        .font(Typo.display(24))
                        .foregroundStyle(Theme.textPrimary)
                    Text(route.kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if isExpanding {
                    ProgressView()
                        .accessibilityLabel("Still mapping the franchise")
                }
            }
            HStack(spacing: 10) {
                StatPill(symbol: "list.number", text: "\(route.steps.count) entries")
                StatPill(symbol: "clock", text: Formatting.duration(minutes: route.totalMinutes))
                if done > 0 {
                    StatPill(symbol: "checkmark.circle.fill", text: "\(done) of \(required) done", tint: Theme.positive)
                }
            }
            if done > 0, remaining > 0 {
                let forecastDays = model.pace.minutesPerDay > 0 ? Int((Double(remaining) / model.pace.minutesPerDay).rounded(.up)) : nil
                Text("\(Formatting.duration(minutes: remaining)) left\(forecastDays.map { " · about \($0) days at your pace" } ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            if let next = route.nextStep(in: model.library) {
                NavigationLink(value: Route.media(next.media.id)) {
                    HStack(spacing: 12) {
                        PosterImage(media: next.media, width: 40, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: done == 0 ? "Start here" : "Up next", color: Theme.accentCool)
                            Text(model.title(next.media))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .surface(interactive: true)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
    }
}

private struct RouteTimeline: View {
    let route: FranchiseRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(route.steps.enumerated()), id: \.element.id) { pair in
                StepRow(step: pair.element, index: pair.offset + 1, isLast: pair.offset == route.steps.count - 1)
            }
        }
    }
}

private struct StepRow: View {
    let step: RouteStep
    let index: Int
    let isLast: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.entry(step.media.id)
        let isDone = entry?.status == .completed
        let tint = Color(anilistHex: step.media.coverImage?.color) ?? Theme.accent
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isDone ? Theme.positive : (step.isOptional ? Theme.ink2 : tint.opacity(0.9)))
                        .frame(width: 28, height: 28)
                    if isDone {
                        Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.black.opacity(0.8))
                    } else {
                        Text("\(index)").font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(step.isOptional ? Theme.textSecondary : .black.opacity(0.8))
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(tint.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            NavigationLink(value: Route.media(step.media.id)) {
                HStack(alignment: .top, spacing: 12) {
                    PosterImage(media: step.media, width: 54, cornerRadius: 8)
                        .opacity(step.isOptional ? 0.75 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title(step.media))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(step.isOptional ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(meta)
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 6) {
                            Text(step.role.label)
                                .font(Typo.micro)
                                .foregroundStyle(step.isOptional ? Theme.caution : Theme.accentCool)
                            if step.isOptional {
                                Text("OPTIONAL")
                                    .font(Typo.micro)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        if let note = step.note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let filler = FillerGuide.info(for: step.media.id), filler.fillerCount > 0 {
                            Label("Skip \(filler.fillerCount) filler: \(fillerRanges(filler))", systemImage: "circle.dashed")
                                .font(.footnote)
                                .foregroundStyle(Theme.caution)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let entry, entry.status.isActive {
                            ProgressBar(progress: entry.completion ?? 0, tint: tint, height: 3)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .padding(.bottom, 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index). \(model.title(step.media)). \(step.role.label). \(meta)\(isDone ? ". Completed" : "")")
    }

    private var meta: String {
        var parts: [String] = [step.media.formatLabel]
        if let year = step.media.year { parts.append(String(year)) }
        if let units = step.media.totalUnits, step.media.format != .movie { parts.append("\(units) \(step.media.unitShort.lowercased())") }
        if step.minutes > 0 { parts.append(Formatting.duration(minutes: step.minutes)) }
        return parts.joined(separator: " · ")
    }

    private func fillerRanges(_ info: FillerInfo) -> String {
        let shown = info.ranges.prefix(4).map { $0.lowerBound == $0.upperBound ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }
        return shown.joined(separator: ", ") + (info.ranges.count > 4 ? "…" : "")
    }
}

/// Adds every required step not yet in the library to Planning.
private struct PlanRouteButton: View {
    let route: FranchiseRoute
    @Environment(AppModel.self) private var model
    @State private var added = false

    var body: some View {
        let missing = route.steps.filter { !$0.isOptional && model.entry($0.media.id) == nil }
        if model.canEdit, !missing.isEmpty {
            Button {
                for step in missing.prefix(25) { model.add(step.media, status: .planning) }
                added = true
                Haptics.success()
            } label: {
                Label(added ? "Added to your plan" : "Add \(missing.count) to Planning", systemImage: added ? "checkmark" : "text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.accent))
            .disabled(added)
        }
    }
}
