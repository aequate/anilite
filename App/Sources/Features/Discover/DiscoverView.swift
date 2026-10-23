import SwiftUI
import AniliteKit

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var heroAtmosphere: Atmosphere = .brand

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                DiscoverHeader()
                    .padding(.horizontal, Theme.gutter)

                if let home = model.home {
                    HeroCarousel(items: Array(home.trending.media.prefix(6)), atmosphere: $heroAtmosphere)
                    TonightSection()
                    ContinueSection()
                    MoodSection()
                    ForYouSection()
                    MediaRail(title: "This season", subtitle: seasonSubtitle, items: home.season.media,
                              caption: { media in media.nextAiringEpisode.map { "Ep \($0.episode) in " + Formatting.countdown(seconds: Int($0.date.timeIntervalSinceNow)) } })
                    HiddenGemsSection()
                    MediaRail(title: "Trending now", items: Array(home.trending.media.dropFirst(6)))
                    ReviveSection()
                    MediaRail(title: "Manga everyone's reading", items: home.manga.media)
                    MediaRail(title: "Coming next season", items: home.upcoming.media,
                              caption: { media in media.startDate?.date().map { $0.formatted(.dateTime.month().day()) } ?? media.formatLabel })
                    MediaRail(title: "All-time greats", items: home.top.media,
                              badge: { media in media.averageScore.map { "\($0)%" } })
                    footer
                } else if let error = model.homeState.errorMessage {
                    ErrorBanner(message: error) { Task { await model.refreshHome(force: true) } }
                        .padding(.horizontal, Theme.gutter)
                    ContinueSection()
                } else {
                    DiscoverSkeleton()
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refreshAll() }
        .background {
            ZStack {
                Theme.ink0
                AtmosphereView(atmosphere: heroAtmosphere, intensity: 0.85)
                    .frame(height: 560)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var seasonSubtitle: String {
        let now = MediaSeason.of(Date())
        return "\(now.season.label) \(now.year) · airing now"
    }

    private var footer: some View {
        Text("Data from AniList. Anilite is unofficial and non-commercial.")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

// MARK: - Header

private struct DiscoverHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: greeting, color: Theme.textSecondary)
                Text("Discover")
                    .font(Typo.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                router.push(.calendar, on: .discover)
            } label: {
                Image(systemName: "calendar")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Airing calendar")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = model.account.displayName.map { ", \($0)" } ?? ""
        switch hour {
        case 5..<12: return "Good morning\(name)"
        case 12..<18: return "Good afternoon\(name)"
        case 18..<23: return "Good evening\(name)"
        default: return "Late-night session\(name)"
        }
    }
}

// MARK: - Hero

private struct HeroCarousel: View {
    let items: [Media]
    @Binding var atmosphere: Atmosphere

    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget
    @State private var focused: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - Theme.gutter * 2
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { media in
                        HeroCard(media: media, width: width)
                            .id(media.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.gutter)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused)
        }
        .frame(height: 400)
        .task(id: focused ?? items.first?.id) {
            guard let media = items.first(where: { $0.id == (focused ?? items.first?.id) }) else { return }
            let palette = await ImagePipeline.shared.palette(for: media.coverImage?.thumbnail, hint: media.coverImage?.color)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                atmosphere = Atmosphere.resolve(for: media, palette: palette)
            }
            ImagePipeline.shared.prefetch(items.compactMap { $0.bannerImage ?? $0.coverImage?.best }, points: 420)
        }
        .onChange(of: focused) { _, _ in Haptics.tick() }
    }
}

private struct HeroCard: View {
    let media: Media
    let width: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget

    var body: some View {
        NavigationLink(value: Route.media(media.id)) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(media.bannerImage ?? media.coverImage?.best, points: 420,
                            placeholder: Color(anilistHex: media.coverImage?.color)?.opacity(0.4) ?? Theme.ink2)
                    .frame(width: width + 60, height: 400)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content.offset(x: budget.allowsParallax ? phase.value * -50 : 0)
                    }
                    .frame(width: width, height: 400)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)

                HStack(alignment: .bottom, spacing: 14) {
                    PosterImage(media: media, width: 86, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                        .heroSource(media.id)
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: media.status == .releasing ? "Trending · airing" : "Trending now",
                                color: Color(anilistHex: media.coverImage?.color) ?? Theme.brand)
                        Text(model.title(media))
                            .font(Typo.display(24))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                        MetaLine(items: meta)
                    }
                }
                .padding(18)
            }
            .frame(width: width, height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content
                    .scaleEffect(budget.allowsParallax ? 1 - abs(phase.value) * 0.06 : 1)
                    .opacity(1 - abs(phase.value) * 0.3)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .contextMenu { MediaQuickActions(media: media) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title(media)), \(meta.joined(separator: ", "))")
    }

    private var meta: [String] {
        var items: [String] = [media.formatLabel]
        if let genres = media.genres { items.append(genres.prefix(2).joined(separator: " / ")) }
        if let score = media.averageScore { items.append("\(score)%") }
        return items
    }
}

// MARK: - Tonight

private struct TonightSection: View {
    @Environment(AppModel.self) private var model
    private let options = [30, 60, 90, 150, 240]

    var body: some View {
        @Bindable var model = model
        let picks = TonightPicker.picks(minutes: model.settings.tonightMinutes, library: model.library, fresh: model.forYou, limit: 6)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tonight", subtitle: "What fits the time you've got")
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { minutes in
                        Button {
                            Haptics.tick()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.settings.tonightMinutes = minutes }
                        } label: {
                            Chip(label: Formatting.duration(minutes: minutes), symbol: minutes >= 150 ? "moon.stars.fill" : "clock",
                                 isSelected: model.settings.tonightMinutes == minutes)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            if picks.isEmpty {
                Text("Add a few titles to your library and Tonight will plan around your time.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(picks) { pick in
                            TonightCard(pick: pick)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

private struct TonightCard: View {
    let pick: TonightPick
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: Route.media(pick.media.id)) {
            HStack(spacing: 12) {
                PosterImage(media: pick.media, width: 64, cornerRadius: 10)
                    .heroSource(pick.media.id)
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: kindLabel, color: Color(anilistHex: pick.media.coverImage?.color) ?? Theme.brandCool)
                    Text(model.title(pick.media))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(pick.reason)
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(pick.units) \(pick.media.unitShort.lowercased()) · \(Formatting.duration(minutes: pick.minutes))")
                        .font(Typo.micro)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 290, height: 120)
            .glassSurface(cornerRadius: 20, tint: Color(anilistHex: pick.media.coverImage?.color))
        }
        .buttonStyle(PressableStyle())
        .contextMenu { MediaQuickActions(media: pick.media) }
    }

    private var kindLabel: String {
        switch pick.kind {
        case .continueWatching: return "Continue"
        case .finishIt: return "Finish it tonight"
        case .startFresh: return "Start something new"
        case .film: return "Film night"
        }
    }
}

// MARK: - Continue

private struct ContinueSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.library.all
            .filter { $0.status.isActive }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Pick up where you left off")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(active)) { entry in
                            ContinueCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

struct ContinueCard: View {
    let entry: LibraryEntry
    @Environment(AppModel.self) private var model
    @State private var bump = 0

    var body: some View {
        let media = entry.media
        let tint = Color(anilistHex: media.coverImage?.color) ?? Theme.brand
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Route.media(media.id)) {
                HStack(spacing: 12) {
                    PosterImage(media: media, width: 52, cornerRadius: 9)
                        .heroSource(media.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title(media))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(progressText)
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                ProgressBar(progress: entry.completion ?? 0, tint: tint, height: 4)
                if model.canEdit, (media.totalUnits ?? Int.max) > entry.progress {
                    Button {
                        bump += 1
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.increment(entry) }
                    } label: {
                        Text("+1")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(width: 44, height: 30)
                            .background(tint, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.85))
                    .symbolEffect(.bounce, value: bump)
                    .accessibilityLabel("Mark \(media.unitName) \(entry.progress + 1) as done")
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .glassSurface(cornerRadius: 20, tint: tint)
        .contextMenu { MediaQuickActions(media: media) }
    }

    private var progressText: String {
        var text = "\(entry.media.unitShort) \(entry.progress)"
        if let total = entry.media.totalUnits { text += " of \(total)" }
        if let next = entry.media.nextAiringEpisode, entry.progress >= next.episode - 1 {
            text += " · caught up"
        } else if let minutes = entry.remainingMinutes, minutes > 0 {
            text += " · \(Formatting.duration(minutes: minutes)) left"
        }
        return text
    }
}

// MARK: - Moods

private struct MoodSection: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "In the mood for…")
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            Haptics.tap()
                            router.search(mood.label.lowercased())
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: mood.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Theme.brandCool)
                                Text(mood.label)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(mood.blurb)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .frame(width: 150, height: 118, alignment: .topLeading)
                            .glassSurface(cornerRadius: 18)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(mood.label): \(mood.blurb)")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

// MARK: - Recommendations

private struct ForYouSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let picks = model.forYou.filter { !$0.isHiddenGem }.prefix(14)
        if model.dna.isMeaningful, !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "For you", subtitle: "Matched to your \(model.dna.archetype.name) taste")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(picks)) { scored in
                            RecommendationCard(scored: scored)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

struct RecommendationCard: View {
    let scored: ScoredMedia
    var width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterCard(media: scored.media, width: width, badge: "\(scored.matchPercent)% match",
                       caption: scored.reasons.first?.text)
            if scored.reasons.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: scored.reasons[1].symbol)
                    Text(scored.reasons[1].text).lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: width, alignment: .leading)
            }
        }
    }
}

private struct HiddenGemsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let gems = model.forYou.filter(\.isHiddenGem).prefix(10)
        if !gems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Hidden gems", subtitle: "Loved by the few who found them")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(gems)) { scored in
                            RecommendationCard(scored: scored, width: 124)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

private struct ReviveSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.revivals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Worth another shot", subtitle: "Dropped or paused titles that match how your taste has grown")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(model.revivals) { scored in
                            PosterCard(media: scored.media, width: 124, badge: "\(scored.matchPercent)%",
                                       caption: scored.reasons.first?.text)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

private struct DiscoverSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Skeleton(cornerRadius: 28).frame(height: 400)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Skeleton().frame(width: 180, height: 22)
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            Skeleton(cornerRadius: Theme.cornerSmall).frame(width: 124, height: 186)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .accessibilityLabel("Loading Discover")
    }
}
