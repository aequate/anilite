import SwiftUI
import AniliteKit

struct MediaDetailView: View {
    let mediaId: Int

    @Environment(AppModel.self) private var model
    @State private var detail: DetailModel

    init(mediaId: Int) {
        self.mediaId = mediaId
        _detail = State(initialValue: DetailModel(mediaId: mediaId))
    }

    var body: some View {
        Group {
            if let media = detail.media {
                DetailContent(media: media, detail: detail)
            } else if let error = detail.error {
                VStack {
                    ErrorBanner(message: error) { Task { await detail.load(client: model.client, force: true) } }
                        .padding(Theme.gutter)
                    Spacer()
                }
                .background { ScreenBackground() }
            } else {
                LoadingPlaceholder().background { ScreenBackground() }
            }
        }
        .heroDestination(mediaId)
        .task { await detail.load(client: model.client) }
    }
}

private struct DetailContent: View {
    let media: Media
    let detail: DetailModel

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    private var palette: ArtworkPalette { detail.palette }
    private var context: SpoilerContext { SpoilerContext(media: media, entry: model.entry(media.id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHero(media: media, atmosphere: detail.atmosphere)
                VStack(alignment: .leading, spacing: 26) {
                    EntryActionBar(media: media, tint: palette.accentColor)
                    if let next = media.nextAiringEpisode { AiringCountdown(media: media, next: next, tint: palette.glowColor) }
                    if let health = detail.health, health.verdict != .unknown {
                        HealthCard(health: health, tint: palette.accentColor)
                    }
                    if let point = detail.continuePoint {
                        ContinuePointCard(point: point, tint: palette.glowColor)
                    }
                    SynopsisSection(media: media, context: context)
                    VibeSection(media: media, tint: palette.accentColor, glow: palette.glowColor)
                    WhereSection(media: media)
                    PathfinderTeaser(media: media, tint: palette.accentColor)
                    EpisodesSection(media: media, tint: palette.accentColor)
                    CharactersSection(media: media, context: context)
                    TagsSection(media: media, context: context, tint: palette.accentColor)
                    RelationsSection(media: media, context: context)
                    StaffSection(media: media)
                    StatsSection(media: media, tint: palette.accentColor)
                    JournalSection(media: media)
                    attribution
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            RecommendationsRail(media: media)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await detail.load(client: model.client, force: true) }
        .background {
            ZStack {
                palette.deepColor.opacity(0.5)
                Theme.ink0.opacity(0.75)
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbar }
        .sensoryFeedback(trigger: model.entry(media.id)?.status == .completed) { old, new in new && !old ? .success : nil }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let url = URL(string: "anilite://media/\(media.id)") {
                    ShareLink(item: url, subject: Text(model.title(media))) { Label("Share in Anilite", systemImage: "square.and.arrow.up") }
                }
                if let site = media.siteUrl.flatMap { URL(string: $0) } {
                    Link(destination: site) { Label("Open on AniList", systemImage: "safari") }
                }
                Divider()
                if model.unlockedSpoilers.contains(media.id) {
                    Button { model.relockSpoilers(for: media.id) } label: { Label("Hide spoilers again", systemImage: "eye.slash") }
                } else {
                    Button { model.unlockSpoilers(for: media.id) } label: { Label("Show all spoilers for this title", systemImage: "eye") }
                }
                Button { router.sheet = .journalCompose(media) } label: { Label("Write a journal note", systemImage: "square.and.pencil") }
                Button { router.sheet = .newClub(media) } label: { Label("Start a watch club", systemImage: "person.3") }
                Button { router.push(.pathfinder(media.id)) } label: { Label("Watch order", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("More actions")
        }
    }

    private var attribution: some View {
        Text("Information from AniList and its community. Synopses may be credited to their original sources.")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Hero

private struct DetailHero: View {
    let media: Media
    let atmosphere: Atmosphere

    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget
    private let height: CGFloat = 430

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            let parallax = budget.allowsParallax ? min(0, minY) * -0.45 : 0
            ZStack(alignment: .bottomLeading) {
                AtmosphereView(atmosphere: atmosphere)
                if let banner = media.bannerImage {
                    RemoteImage(banner, points: 430, placeholder: .clear)
                        .opacity(0.55)
                        .blendMode(.screen)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                }
                LinearGradient(colors: [.clear, Theme.ink0.opacity(0.35), Theme.ink0.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                titleBlock
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 8)
                    .offset(y: -parallax * 0.3)
            }
            .frame(width: geo.size.width, height: height + stretch)
            .offset(y: -stretch + parallax)
            .clipped()
        }
        .frame(height: height)
    }

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PosterImage(media: media, width: 116, cornerRadius: 16)
                .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: [media.formatLabel, media.status?.label ?? "", media.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                        color: Theme.textSecondary)
                Text(model.title(media))
                    .font(Typo.display(26))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let native = media.title?.native, native != model.title(media) {
                    Text(native)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if let score = media.averageScore {
                        Label("\(score)%", systemImage: "star.fill").foregroundStyle(Theme.caution)
                    }
                    if let popularity = media.popularity {
                        Label(Formatting.compact(popularity), systemImage: "person.2.fill").foregroundStyle(Theme.textSecondary)
                    }
                    if let studio = media.mainStudio {
                        Text(studio.name).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                .font(Typo.caption)
            }
        }
    }
}

// MARK: - Library actions

private struct EntryActionBar: View {
    let media: Media
    let tint: Color

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        if let entry = model.entry(media.id) {
            existing(entry)
        } else if model.canEdit {
            HStack(spacing: 10) {
                Button {
                    model.add(media, status: .current)
                } label: {
                    Label(media.mediaType == .anime ? "Start watching" : "Start reading", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
                Button {
                    model.add(media, status: .planning)
                } label: {
                    Label("Plan", systemImage: "bookmark")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Text(model.account == .undecided ? "Set up a library to track this." : "Viewing a read-only profile.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func existing(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: StatusDot.symbol(entry.status))
                    .font(.title2)
                    .foregroundStyle(StatusDot.color(entry.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.status.label(for: entry.type))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(progressText(entry))
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if model.canEdit {
                    if entry.status.isActive, (media.totalUnits ?? Int.max) > entry.progress {
                        Button {
                            withAnimation(Motion.standard) { model.increment(entry) }
                        } label: {
                            Text("+1 \(media.unitShort)")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(tint, in: Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.88))
                        .accessibilityLabel("Mark \(media.unitName) \(entry.progress + 1) as done")
                    }
                    Button {
                        router.sheet = .editor(media)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .capsuleSurface(interactive: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityLabel("Edit entry")
                }
            }
            if let completion = entry.completion {
                ProgressBar(progress: completion, tint: tint, height: 5)
            }
            if entry.status.isActive, let minutes = entry.remainingMinutes, minutes > 0 {
                let forecast = Forecast.make(for: entry, pace: model.pace)
                if let finish = forecast.finishDate {
                    Text("At your pace you'll finish around \(finish.formatted(.dateTime.month().day())) · \(Formatting.duration(minutes: minutes)) to go")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .surface(cornerRadius: 20, tint: tint)
    }

    private func progressText(_ entry: LibraryEntry) -> String {
        var text = "\(media.unitShort) \(entry.progress)"
        if let total = media.totalUnits { text += " of \(total)" }
        if entry.type == .manga, entry.progressVolumes > 0 { text += " · Vol \(entry.progressVolumes)" }
        if entry.isScored { text += " · ★ \(model.scoreFormat.display(entry.score))" }
        if entry.repeatCount > 0 { text += " · rewatched \(entry.repeatCount)×" }
        return text
    }
}

private struct AiringCountdown: View {
    let media: Media
    let next: NextAiringEpisode
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let seconds = Int(next.date.timeIntervalSince(context.date))
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Episode \(next.episode) \(seconds > 0 ? "airs " + Formatting.countdown(seconds: seconds) : "is out")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(next.date.formatted(.dateTime.weekday(.wide).hour().minute()))
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(14)
            .surface(cornerRadius: 16)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct HealthCard: View {
    let health: FranchiseHealth
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: health.symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Will it have an ending?")
                Text(health.headline)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(health.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch health.verdict {
        case .complete: return Theme.positive
        case .ongoing, .sequelAnnounced: return Theme.accentCool
        case .sourceAhead: return tint
        case .sourceFinishedAnimeStopped, .cancelled: return Theme.caution
        case .unknown: return Theme.textTertiary
        }
    }
}

private struct ContinuePointCard: View {
    let point: ContinuePoint
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "After the anime", color: tint)
                Spacer()
                Text(confidence)
                    .font(Typo.micro)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(point.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(point.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let sourceId = point.sourceId {
                NavigationLink(value: Route.media(sourceId)) {
                    Label("Open \(point.sourceTitle ?? "the source")", systemImage: "book.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .surface(cornerRadius: 20, tint: tint)
    }

    private var confidence: String {
        switch point.confidence {
        case .curated: return "Checked"
        case .estimated: return "Estimate"
        case .complete: return "Fully adapted"
        }
    }
}
