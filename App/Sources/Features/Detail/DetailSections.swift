import SwiftUI
import AniliteKit

// MARK: - Synopsis

/// Synopsis with AniList's inline spoiler markup honoured: hidden passages are blurred
/// and revealed one at a time with a tap.
struct SynopsisSection: View {
    let media: Media
    let context: SpoilerContext

    @Environment(AppModel.self) private var model
    @State private var revealed: Set<Int> = []
    @State private var expanded = false

    var body: some View {
        let parts = SpoilerShield.segments(media.description, context: context, policy: model.spoilerPolicy)
        if !parts.isEmpty {
            let length = parts.reduce(0) { $0 + $1.segment.text.count }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Story")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { pair in
                        segmentView(pair.element.segment.text, visibility: pair.element.visibility, index: pair.offset)
                    }
                }
                .frame(maxHeight: expanded || length < 420 ? nil : 150, alignment: .top)
                .clipped()
                .mask {
                    if expanded || length < 420 {
                        Rectangle()
                    } else {
                        LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                    }
                }
                if length >= 420 {
                    Button(expanded ? "Show less" : "Read more") {
                        withAnimation(Motion.standard) { expanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentCool)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ text: String, visibility: SpoilerVisibility, index: Int) -> some View {
        let label = Text(text)
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        switch visibility {
        case .visible:
            label
        case .hidden(let reason, _):
            if revealed.contains(index) {
                label.transition(.opacity)
            } else {
                Button {
                    Haptics.tap(.soft)
                    withAnimation(.easeOut(duration: 0.3)) { _ = revealed.insert(index) }
                } label: {
                    label
                        .blur(radius: 7)
                        .accessibilityHidden(true)
                        .overlay {
                            Label(reason, systemImage: "eye.slash.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .capsuleSurface()
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hidden spoiler. \(reason). Double-tap to reveal.")
            }
        }
    }
}

// MARK: - Vibe

/// A radar of the title's feel, plus the moods it fits best.
struct VibeSection: View {
    let media: Media
    let tint: Color
    let glow: Color

    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let vibe = VibeProfile.of(media)
        let dims = vibe.dimensions
        let moods = Mood.allCases.sorted { vibe.moodScore($0) > vibe.moodScore($1) }.prefix(3)
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Vibe")
            HStack(alignment: .center, spacing: 18) {
                VibeRadar(values: dims.map { $0.value }, tint: tint, glow: glow, scale: grown ? 1 : 0.2)
                    .frame(width: 150, height: 150)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(dims.enumerated()), id: \.offset) { pair in
                        let dim = pair.element
                        HStack(spacing: 8) {
                            Text(dim.label)
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 82, alignment: .leading)
                            ProgressBar(progress: dim.value, tint: tint, height: 4)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(dim.label) \(Int(dim.value * 100)) percent")
                    }
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(Array(moods)) { mood in
                    Button {
                        router.search(mood.label.lowercased() + " " + (media.mediaType == .manga ? "manga" : "anime"))
                    } label: {
                        Chip(label: mood.label, symbol: mood.symbol)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Finds more titles with this mood")
                }
            }
        }
        .padding(16)
        .surface(cornerRadius: 20)
        .onAppear {
            if reduceMotion { grown = true } else {
                withAnimation(Motion.reveal.delay(0.15)) { grown = true }
            }
        }
    }
}

struct VibeRadar: View {
    let values: [Double]
    let tint: Color
    let glow: Color
    var scale: Double = 1

    var body: some View {
        Canvas { context, size in
            let n = values.count
            guard n >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            func point(_ i: Int, _ r: Double) -> CGPoint {
                let angle = CGFloat(Double(i) / Double(n) * 2 * Double.pi - Double.pi / 2)
                let length = radius * CGFloat(r)
                return CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
            }
            for ring in [0.33, 0.66, 1.0] {
                var path = Path()
                for i in 0..<n {
                    i == 0 ? path.move(to: point(i, ring)) : path.addLine(to: point(i, ring))
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.7)
            }
            for i in 0..<n {
                var spoke = Path()
                spoke.move(to: center)
                spoke.addLine(to: point(i, 1))
                context.stroke(spoke, with: .color(.white.opacity(0.06)), lineWidth: 0.6)
            }
            var shape = Path()
            for i in 0..<n {
                let p = point(i, max(0.06, values[i]) * scale)
                i == 0 ? shape.move(to: p) : shape.addLine(to: p)
            }
            shape.closeSubpath()
            context.fill(shape, with: .radialGradient(Gradient(colors: [glow.opacity(0.65), tint.opacity(0.25)]),
                                                      center: center, startRadius: 0, endRadius: radius))
            context.stroke(shape, with: .color(glow), lineWidth: 1.6)
            for i in 0..<n {
                let p = point(i, max(0.06, values[i]) * scale)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
            }
        }
    }
}

// MARK: - Where to watch / read

/// Legitimate places to watch or read, from AniList's licensed external links. Region notes
/// only describe whether a service operates where the viewer is; per-title catalogues are
/// never guessed.
struct WhereSection: View {
    let media: Media
    @Environment(AppModel.self) private var model

    var body: some View {
        let options = StreamingResolver.options(for: media, region: model.region)
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: media.mediaType == .anime ? "Where to watch" : "Where to read")
            if options.isEmpty {
                Text("No licensed \(media.mediaType == .anime ? "streams" : "reading sites") are listed for this title yet. Check your local services or a physical release.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Link(destination: option.url) { WhereRow(option: option) }
                            .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var footnote: String {
        let region = model.region.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? "your region"
        return "Service notes are for \(region). Catalogues change often, so a title can still be missing from a service that operates there."
    }
}

private struct WhereRow: View {
    let option: WhereOption

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(anilistHex: option.colorHex) ?? Theme.accentCool)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.site)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(option.isLikelyAvailable ? Theme.textPrimary : Theme.textSecondary)
                    if option.isFree {
                        Text("FREE")
                            .font(Typo.micro)
                            .foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.positive, in: Capsule())
                    }
                    if let language = option.language, !language.isEmpty {
                        Text(language)
                            .font(Typo.micro)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(option.note)
                    .font(Typo.caption)
                    .foregroundStyle(noteColor)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(cornerRadius: 16, interactive: true)
        .opacity(option.availability == .discontinued ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(option.site)")
    }

    private var noteColor: Color {
        switch option.availability {
        case .serviceInRegion: return Theme.positive
        case .serviceNotInRegion, .discontinued: return Theme.caution
        case .regionalChannel, .unknown: return Theme.textTertiary
        }
    }
}

// MARK: - Pathfinder teaser

struct PathfinderTeaser: View {
    let media: Media
    let tint: Color

    var body: some View {
        let kinds: Set<MediaRelationType> = [.prequel, .sequel, .parent, .sideStory, .adaptation, .source, .spinOff, .alternative]
        let related = media.relationEdges.filter { edge in
            guard let type = edge.relationType else { return false }
            return kinds.contains(type)
        }
        let filler = FillerGuide.info(for: media.id)
        if !related.isEmpty || filler != nil {
            NavigationLink(value: Route.pathfinder(media.id)) {
                HStack(spacing: 14) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Watch & read order")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle(related: related.count, filler: filler))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(16)
                .surface(cornerRadius: 20, tint: tint, interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
    }

    private func subtitle(related: Int, filler: FillerInfo?) -> String {
        var parts: [String] = []
        if related > 0 { parts.append("Essentials, release and manga-first routes across the franchise") }
        if let filler, filler.fillerCount > 0 { parts.append("\(filler.fillerCount) filler episodes you can skip") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Episodes

/// Episode grid with progress, filler marks, and spoiler-safe episode titles.
/// Long-press an episode to set your progress to it.
struct EpisodesSection: View {
    let media: Media
    let tint: Color

    @Environment(AppModel.self) private var model
    @State private var selected: Int?
    @State private var confirming: Int?
    @State private var showsAll = false

    private let columns = [GridItem(.adaptive(minimum: 46, maximum: 60), spacing: 8)]

    var body: some View {
        if media.mediaType == .anime, let total = media.totalUnits ?? media.releasedUnits, total > 1 {
            let entry = model.entry(media.id)
            let progress = entry?.progress ?? 0
            let released = media.releasedUnits ?? total
            let filler = FillerGuide.info(for: media.id)
            let titles = episodeTitles
            let shown = showsAll ? total : min(total, 60)
            let context = SpoilerContext(media: media, entry: entry)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Episodes")
                    Spacer()
                    if let filler, filler.fillerCount > 0 {
                        Label("Filler", systemImage: "circle.dashed")
                            .font(Typo.micro)
                            .foregroundStyle(Theme.caution)
                    }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(1...shown, id: \.self) { number in
                        EpisodeCell(number: number,
                                    isWatched: number <= progress,
                                    isReleased: number <= released,
                                    isFiller: filler?.isFiller(number) ?? false,
                                    isSelected: selected == number,
                                    tint: tint)
                            .onTapGesture {
                                Haptics.tick()
                                withAnimation(Motion.standard) {
                                    selected = selected == number ? nil : number
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.4) {
                                guard model.canEdit, number <= released else { return }
                                Haptics.tap(.medium)
                                confirming = number
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "Set progress to episode \(number)") {
                                if model.canEdit { confirming = number }
                            }
                    }
                }
                if shown < total {
                    Button("Show all \(total) episodes") { withAnimation { showsAll = true } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentCool)
                }
                if let selected {
                    selectedDetail(selected, titles: titles, context: context, filler: filler, released: released)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.canEdit {
                    Text("Long-press an episode to mark everything up to it as watched.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .confirmationDialog("Set progress", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { number in
                Button("Watched up to episode \(number)") { setProgress(number, total: media.totalUnits) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var episodeTitles: [Int: StreamingEpisode] {
        var map: [Int: StreamingEpisode] = [:]
        for episode in media.streamingEpisodes ?? [] {
            if let n = episode.episodeNumber, map[n] == nil { map[n] = episode }
        }
        return map
    }

    @ViewBuilder
    private func selectedDetail(_ number: Int, titles: [Int: StreamingEpisode], context: SpoilerContext, filler: FillerInfo?, released: Int) -> some View {
        let visibility = SpoilerShield.episode(number, context: context, policy: model.spoilerPolicy)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Episode \(number)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if filler?.isFiller(number) == true {
                    StatPill(symbol: "circle.dashed", text: "Filler · safe to skip", tint: Theme.caution)
                }
                Spacer()
            }
            if number > released {
                Text("Not out yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            } else if let episode = titles[number], let title = episode.title {
                switch visibility {
                case .visible:
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                case .hidden(let reason, _):
                    Label("Title hidden: \(reason)", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                }
                if let site = episode.site, let link = episode.url.flatMap({ URL(string: $0) }) {
                    Link(destination: link) {
                        Label("Watch on \(site)", systemImage: "play.rectangle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(tint)
                }
            } else {
                Text(media.duration.map { "About \($0) minutes" } ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 16)
    }

    private func setProgress(_ number: Int, total: Int?) {
        let entry = model.entry(media.id)
        let status: MediaListStatus
        if let total, number >= total {
            status = .completed
        } else if let current = entry?.status, current.isActive {
            status = current
        } else {
            status = .current
        }
        model.save(EntryChange(mediaId: media.id, status: status, progress: number), media: media)
    }
}

private struct EpisodeCell: View {
    let number: Int
    let isWatched: Bool
    let isReleased: Bool
    let isFiller: Bool
    let isSelected: Bool
    let tint: Color

    var body: some View {
        Text("\(number)")
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(isWatched ? Color.black.opacity(0.8) : (isReleased ? Theme.textPrimary : Theme.textTertiary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isWatched ? tint : Color.white.opacity(isReleased ? 0.07 : 0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isFiller ? Theme.caution.opacity(0.85) : (isSelected ? Color.white.opacity(0.7) : Theme.hairline),
                                  style: StrokeStyle(lineWidth: isSelected ? 1.6 : 1, dash: isFiller ? [3, 3] : []))
            }
            .scaleEffect(isSelected ? 1.06 : 1)
            .contentShape(Rectangle())
            .accessibilityLabel("Episode \(number)\(isWatched ? ", watched" : "")\(isFiller ? ", filler" : "")\(isReleased ? "" : ", not out yet")")
    }
}

// MARK: - Characters

struct CharactersSection: View {
    let media: Media
    let context: SpoilerContext

    @Environment(AppModel.self) private var model

    var body: some View {
        let edges = Array((media.characters?.edges ?? []).prefix(18))
        if !edges.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Characters")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(edges.enumerated()), id: \.offset) { pair in
                            if let character = pair.element.node {
                                let gate = SpoilerShield.character(role: pair.element.role, description: character.description,
                                                                   index: pair.offset, context: context, policy: model.spoilerPolicy)
                                CharacterCard(character: character, role: pair.element.role,
                                              voiceActor: pair.element.voiceActors?.first,
                                              hidden: !gate.showCard.isVisible)
                            }
                        }
                    }
                }
                .padding(.horizontal, -Theme.gutter)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            }
        }
    }
}

private struct CharacterCard: View {
    let character: AniliteKit.Character
    let role: CharacterRole?
    let voiceActor: VoiceActor?
    let hidden: Bool

    @State private var revealed = false

    var body: some View {
        let masked = hidden && !revealed
        VStack(alignment: .leading, spacing: 6) {
            if masked {
                Button {
                    Haptics.tap(.soft)
                    withAnimation(.easeOut(duration: 0.3)) { revealed = true }
                } label: {
                    portrait
                        .blur(radius: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            Image(systemName: "eye.slash.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                }
                .buttonStyle(PressableStyle())
            } else {
                NavigationLink(value: Route.character(character.id)) { portrait }
                    .buttonStyle(PressableStyle())
            }
            Text(masked ? "Hidden character" : (character.name?.full ?? "Unknown"))
                .font(Typo.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2, reservesSpace: true)
            Text(roleLabel)
                .font(Typo.micro)
                .foregroundStyle(Theme.textTertiary)
            if let voiceActor, let name = voiceActor.name?.full, !masked {
                NavigationLink(value: Route.staff(voiceActor.id)) {
                    Label(name, systemImage: "mic.fill")
                        .font(Typo.micro)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 92, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(masked ? "Hidden character, may be a spoiler. Double-tap to reveal." : (character.name?.full ?? "Character"))
    }

    private var portrait: some View {
        RemoteImage(character.image?.best, points: 140)
            .frame(width: 92, height: 122)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var roleLabel: String {
        switch role {
        case .main: return "MAIN"
        case .supporting: return "SUPPORTING"
        default: return "BACKGROUND"
        }
    }
}

// MARK: - Tags

struct TagsSection: View {
    let media: Media
    let context: SpoilerContext
    let tint: Color

    @Environment(AppModel.self) private var model

    var body: some View {
        let result = SpoilerShield.tags(media.tags ?? [], context: context, policy: model.spoilerPolicy)
        let genres = media.genres ?? []
        if !genres.isEmpty || !result.visible.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Genres & themes")
                FlowLayout(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        NavigationLink(value: Route.genre(genre, media.mediaType)) {
                            Chip(label: genre, isSelected: true, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(result.visible.prefix(16)) { tag in
                        NavigationLink(value: Route.tag(tag.name, media.mediaType)) {
                            HStack(spacing: 5) {
                                Text(tag.name)
                                if let rank = tag.rank {
                                    Text("\(rank)%").foregroundStyle(Theme.textTertiary)
                                }
                                if tag.isSpoiler {
                                    Image(systemName: "eye.trianglebadge.exclamationmark").foregroundStyle(Theme.caution)
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if result.hiddenCount > 0 {
                    Button {
                        model.unlockSpoilers(for: media.id)
                        Haptics.tap(.soft)
                    } label: {
                        Label("\(result.hiddenCount) spoiler \(result.hiddenCount == 1 ? "tag" : "tags") hidden · show", systemImage: "eye.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else if model.unlockedSpoilers.contains(media.id) {
                    Button {
                        model.relockSpoilers(for: media.id)
                    } label: {
                        Label("Hide spoilers again", systemImage: "eye")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Relations

struct RelationsSection: View {
    let media: Media
    let context: SpoilerContext

    @Environment(AppModel.self) private var model
    @State private var revealed: Set<Int> = []

    private let order: [MediaRelationType] = [.prequel, .sequel, .parent, .source, .adaptation, .sideStory, .spinOff,
                                              .alternative, .summary, .compilation, .contains, .character, .other]

    var body: some View {
        let edges = media.relationEdges.filter { $0.node != nil }
        if !edges.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Connected")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(sorted(edges), id: \.node!.id) { edge in
                            relationCard(edge)
                        }
                    }
                }
                .padding(.horizontal, -Theme.gutter)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            }
        }
    }

    private func sorted(_ edges: [MediaRelationEdge]) -> [MediaRelationEdge] {
        edges.sorted { a, b in
            let ia = order.firstIndex(of: a.relationType ?? .other) ?? order.count
            let ib = order.firstIndex(of: b.relationType ?? .other) ?? order.count
            if ia != ib { return ia < ib }
            return (a.node?.startDate ?? FuzzyDate()) < (b.node?.startDate ?? FuzzyDate())
        }
    }

    @ViewBuilder
    private func relationCard(_ edge: MediaRelationEdge) -> some View {
        if let node = edge.node {
            let visibility = SpoilerShield.relation(edge.relationType, base: context, policy: model.spoilerPolicy)
            let masked = !visibility.isVisible && !revealed.contains(node.id)
            VStack(alignment: .leading, spacing: 6) {
                Text((edge.relationType ?? .other).label)
                    .font(Typo.micro)
                    .foregroundStyle(Theme.accentCool)
                if masked {
                    Button {
                        Haptics.tap(.soft)
                        withAnimation(.easeOut(duration: 0.3)) { _ = revealed.insert(node.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterImage(media: node, width: 110)
                                .blur(radius: 14)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                .overlay { Image(systemName: "eye.slash.fill").font(.title3).foregroundStyle(.white.opacity(0.85)) }
                            Text("Later in the story · tap to reveal")
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(2, reservesSpace: true)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Hidden \((edge.relationType ?? .other).label). Double-tap to reveal.")
                } else {
                    PosterCard(media: node, width: 110, caption: [node.formatLabel, node.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                }
            }
            .frame(width: 110, alignment: .leading)
        }
    }
}

// MARK: - Staff & studio

struct StaffSection: View {
    let media: Media

    var body: some View {
        let key = keyStaff
        let studios = media.studios?.nodes ?? []
        if !key.isEmpty || !studios.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Made by")
                if !studios.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(studios) { studio in
                            NavigationLink(value: Route.studio(studio.id)) {
                                Chip(label: studio.name, symbol: "building.2.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(key) { pair in
                    NavigationLink(value: Route.staff(pair.staff.id)) {
                        HStack(spacing: 12) {
                            RemoteImage(pair.staff.image?.best, points: 44)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pair.staff.name?.full ?? "Unknown")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(pair.role)
                                    .font(Typo.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }

    private struct Credit: Identifiable {
        let role: String
        let staff: Staff
        var id: Int { staff.id }
    }

    /// The roles people actually look up, one row per person.
    private var keyStaff: [Credit] {
        let important = ["original creator", "story", "art", "director", "series composition", "music", "character design", "original story"]
        var seen = Set<Int>()
        var result: [Credit] = []
        for edge in media.staff?.edges ?? [] {
            guard let node = edge.node, let role = edge.role else { continue }
            let lower = role.lowercased()
            guard important.contains(where: { lower.hasPrefix($0) }) else { continue }
            if seen.insert(node.id).inserted { result.append(Credit(role: role, staff: node)) }
            if result.count == 6 { break }
        }
        return result
    }
}

// MARK: - Stats

struct StatsSection: View {
    let media: Media
    let tint: Color

    var body: some View {
        let scores = (media.stats?.scoreDistribution ?? []).sorted { $0.score < $1.score }
        let rankings = (media.rankings ?? []).prefix(3)
        if !scores.isEmpty || !rankings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Community")
                if !rankings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rankings.enumerated()), id: \.offset) { pair in
                            let r = pair.element
                            Label(rankingText(r), systemImage: r.type == "RATED" ? "star.circle.fill" : "heart.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                if !scores.isEmpty {
                    let peak = max(1, scores.map(\.amount).max() ?? 1)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(scores, id: \.score) { bucket in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(tint.opacity(0.35 + 0.65 * Double(bucket.score) / 100))
                                    .frame(height: max(3, 70 * CGFloat(bucket.amount) / CGFloat(peak)))
                                Text("\(bucket.score)")
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 90, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(scoreSummary(scores))
                }
            }
            .padding(16)
            .surface(cornerRadius: 20)
        }
    }

    private func rankingText(_ r: Ranking) -> String {
        let context = r.context?.capitalized ?? (r.type == "RATED" ? "Highest rated" : "Most popular")
        var text = "#\(r.rank) \(context)"
        if r.allTime != true {
            if let season = r.season { text += " · \(season.label)" }
            if let year = r.year { text += " \(year)" }
        }
        return text
    }

    private func scoreSummary(_ scores: [ScoreDistribution]) -> String {
        let total = scores.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return "No ratings yet" }
        let high = scores.filter { $0.score >= 80 }.reduce(0) { $0 + $1.amount }
        return "\(Int(Double(high) / Double(total) * 100)) percent of \(Formatting.compact(total)) ratings are 80 or higher"
    }
}

// MARK: - Journal

struct JournalSection: View {
    let media: Media
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        let notes = model.journal.filter { $0.mediaId == media.id }.sorted { $0.createdAt > $1.createdAt }
        if !notes.isEmpty || model.entry(media.id) != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Your journal")
                    Spacer()
                    Button {
                        router.sheet = .journalCompose(media)
                    } label: {
                        Label("Write", systemImage: "square.and.pencil")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accentCool)
                }
                if notes.isEmpty {
                    Text("Jot down a moment, a theory, or how an episode made you feel. Notes stay on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(notes.prefix(5)) { note in
                        JournalNoteRow(entry: note, showsTitle: false)
                    }
                }
            }
        }
    }
}

/// One journal note, shared by the detail screen and the journal timeline.
struct JournalNoteRow: View {
    let entry: JournalEntry
    var showsTitle = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.feeling?.emoji ?? "📝")
                .font(.title2)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if showsTitle {
                    Text(entry.mediaTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(entry.text)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts: [String] = [entry.createdAt.formatted(.dateTime.month(.abbreviated).day().year())]
        if let unit = entry.unit { parts.append("at #\(unit)") }
        if let feeling = entry.feeling { parts.append(feeling.label) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recommendations

struct RecommendationsRail: View {
    let media: Media
    @Environment(AppModel.self) private var model

    var body: some View {
        let picks = (media.recommendations?.nodes ?? [])
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .compactMap(\.mediaRecommendation)
            .filter { SpoilerShield.isSafeRecommendation($0, library: model.library, policy: model.spoilerPolicy) }
        MediaRail(title: "If you like this", subtitle: "Recommended by AniList readers and viewers", items: Array(picks.prefix(15)),
                  caption: { pick in
                      guard model.dna.isMeaningful else { return nil }
                      let affinity = model.dna.affinity(for: pick)
                      return affinity > 0.35 ? "Strong taste match" : nil
                  })
    }
}
