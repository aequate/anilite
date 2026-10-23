import SwiftUI
import AniliteKit

// MARK: - Taste DNA

struct TasteDNAView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let dna = model.dna
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ArchetypeCard(dna: dna, name: model.account.displayName ?? "You", compact: false)

                if dna.isMeaningful {
                    vibe(dna)
                    genres(dna)
                    habits(dna)
                    if !dna.evolution.isEmpty { evolution(dna) }
                    bridges
                    share
                } else {
                    EmptyStateView(symbol: "dna", title: "Your DNA is still forming",
                                   message: "Taste DNA reads what you finish, drop and score. Add at least three titles to see it.")
                }
                Text("Taste DNA is computed on this device from your library. Nothing is uploaded.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .screenChrome("Taste DNA")
    }

    private func vibe(_ dna: TasteDNA) -> some View {
        let dims = dna.vibe.dimensions
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your vibe", subtitle: "The feel of what you love")
            HStack(alignment: .center, spacing: 18) {
                VibeRadar(values: dims.map(\.value), tint: Theme.accent, glow: Theme.accentCool)
                    .frame(width: 150, height: 150)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dims.indices, id: \.self) { index in
                        HStack {
                            Text(dims[index].label)
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int((dims[index].value * 100).rounded()))")
                                .font(Typo.caption.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(16)
            .surface()
        }
    }

    private func genres(_ dna: TasteDNA) -> some View {
        let top = dna.genreWeights.sorted { $0.value > $1.value }.prefix(8)
        let maxWeight = top.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Strands", subtitle: "Genres and themes that pull you in")
            VStack(spacing: 8) {
                ForEach(Array(top), id: \.key) { item in
                    NavigationLink(value: Route.genre(item.key, .anime)) {
                        HStack(spacing: 10) {
                            Text(item.key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 110, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(width: max(6, proxy.size.width * CGFloat(max(0, item.value) / max(maxWeight, 0.0001))))
                            }
                            .frame(height: 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !dna.topThemes.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(dna.topThemes.prefix(10), id: \.self) { theme in
                        NavigationLink(value: Route.tag(theme, .anime)) {
                            Chip(label: theme, symbol: nil, tint: Theme.accentCool)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !dna.dislikedGenres.isEmpty {
                Text("Rarely for you: \(dna.dislikedGenres.prefix(3).joined(separator: ", "))")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func habits(_ dna: TasteDNA) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Habits")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                HabitTile(value: percent(dna.completionRate), label: "finish what they start")
                HabitTile(value: percent(dna.dropRate), label: "dropped")
                HabitTile(value: percent(dna.mainstreamIndex), label: "mainstream", detail: dna.mainstreamIndex < 0.4 ? "You dig for hidden gems" : nil)
                HabitTile(value: percent(dna.mangaShare), label: "of it is manga")
                if let mean = dna.meanScore {
                    HabitTile(value: model.scoreFormat.display(mean), label: "average score")
                }
                if let decade = dna.decadeShare.max(by: { $0.value < $1.value })?.key {
                    HabitTile(value: "\(decade)s", label: "favourite era")
                }
            }
        }
    }

    private func evolution(_ dna: TasteDNA) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How your taste evolved")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(dna.evolution) { era in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle().fill(Theme.accent).frame(width: 9, height: 9)
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                            Text(String(era.year))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                            Text(era.topGenres.prefix(2).joined(separator: "\n"))
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(era.count) titles")
                                .font(Typo.micro)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(width: 104, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var bridges: some View {
        let pairs = TasteDNA.bridges(in: model.library.all, limit: 3)
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Unexpected bridges", subtitle: "Titles you love that share hidden threads")
                ForEach(pairs) { bridge in
                    HStack(spacing: 10) {
                        PosterImage(media: bridge.first, width: 44, cornerRadius: 6)
                        Image(systemName: "link")
                            .foregroundStyle(Theme.accentCool)
                        PosterImage(media: bridge.second, width: 44, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(model.title(bridge.first)) & \(model.title(bridge.second))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Text(bridge.sharedThemes.prefix(3).joined(separator: " · "))
                                .font(Typo.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(12)
                    .surface()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var share: some View {
        let fingerprint = model.myFingerprint
        if let link = ShareCodec.link(kind: "dna", code: fingerprint.code) {
            ShareLink(item: link, subject: Text("My anime Taste DNA"),
                      message: Text("I'm \(model.dna.archetype.name). Open this in Anilite to see how compatible we are.")) {
                Label("Share my Taste DNA", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

private struct HabitTile: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Typo.metric)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
            if let detail {
                Text(detail)
                    .font(Typo.micro)
                    .foregroundStyle(Theme.accentCool)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Achievements

struct AchievementsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unlocked = model.achievements.filter(\.isUnlocked)
        let locked = model.achievements.filter { !$0.isUnlocked }.sorted { $0.progress > $1.progress }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("\(unlocked.count) of \(model.achievements.count) unlocked")
                    .font(Typo.display(24))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 8)
                if !unlocked.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(unlocked) { achievement in
                            AchievementBody(achievement: achievement)
                                .surface()
                        }
                    }
                }
                if !locked.isEmpty {
                    SectionHeader(title: "In progress")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(locked) { achievement in
                            AchievementBody(achievement: achievement)
                                .surface()
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .screenChrome("Achievements")
    }
}

private struct AchievementBody: View {
    let achievement: Achievement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if achievement.isUnlocked {
                    Circle().strokeBorder(Theme.seal, lineWidth: 2)
                    Circle().strokeBorder(Theme.seal.opacity(0.55), lineWidth: 0.75).padding(4)
                } else {
                    ProgressRing(progress: achievement.progress, tint: Theme.textSecondary, lineWidth: 2)
                }
                Image(systemName: achievement.symbol)
                    .font(.title3)
                    .foregroundStyle(achievement.isUnlocked ? Theme.seal : Theme.textTertiary)
            }
            .frame(width: 46, height: 46)
            .rotationEffect(.degrees(achievement.isUnlocked ? -8 : 0))
            Text(achievement.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(achievement.isUnlocked ? Theme.textPrimary : Theme.textSecondary)
            Text(achievement.detail)
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !achievement.isUnlocked {
                Text("\(Int((achievement.progress * 100).rounded()))%")
                    .font(Typo.micro.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title). \(achievement.detail). \(achievement.isUnlocked ? "Unlocked" : "\(Int(achievement.progress * 100)) percent")")
    }
}

// MARK: - Year recap

/// An animated, story-style recap of a year, built on-device from the library, AniList
/// activity (when available) and the journal.
struct RecapView: View {
    let year: Int
    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget
    @State private var page = 0

    var body: some View {
        let recap = YearRecap.build(year: year, library: model.library, activities: model.activities, journal: model.journal)
        Group {
            if recap.isEmpty {
                EmptyStateView(symbol: "calendar", title: "Nothing to recap for \(String(year))",
                               message: "Finish something this year and your recap will start writing itself.")
                    .frame(maxHeight: .infinity)
            } else {
                TabView(selection: $page) {
                    RecapPage(index: 0, page: page, eyebrow: "\(String(year)) in anime & manga", tint: Theme.accent) {
                        BigNumber(value: recap.minutes / 60, suffix: " hours")
                        Text("of watching")
                            .font(.title3)
                            .foregroundStyle(Theme.textSecondary)
                        Text("\(recap.episodes) episodes · \(recap.chapters) chapters")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tag(0)

                    RecapPage(index: 1, page: page, eyebrow: "You finished", tint: Theme.accentCool) {
                        BigNumber(value: recap.completedAnime.count + recap.completedManga.count, suffix: " titles")
                        PosterStack(entries: Array((recap.completedAnime + recap.completedManga).prefix(7)))
                        if let first = recap.firstFinish {
                            Text("First finish of the year: \(model.title(first.media))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tag(1)

                    RecapPage(index: 2, page: page, eyebrow: "Your genres", tint: Theme.caution) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(recap.topGenres.prefix(5).enumerated()), id: \.offset) { pair in
                                HStack {
                                    Text("\(pair.offset + 1)")
                                        .font(Typo.metric)
                                        .foregroundStyle(Theme.caution)
                                        .frame(width: 34, alignment: .leading)
                                    Text(pair.element.0)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(pair.element.1)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        if let studio = recap.favoriteStudio {
                            Text("Studio of the year: \(studio)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tag(2)

                    RecapPage(index: 3, page: page, eyebrow: "Month by month", tint: Theme.positive) {
                        MonthBars(minutes: recap.monthlyMinutes, highlight: recap.busiestMonth, animate: page == 3 && budget.allowsPhysics)
                            .frame(height: 180)
                        if let busiest = recap.busiestMonth, (1...12).contains(busiest) {
                            Text("\(Calendar.current.monthSymbols[busiest - 1]) was your biggest month.")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .tag(3)

                    RecapPage(index: 4, page: page, eyebrow: "Your favourites", tint: Theme.accent) {
                        VStack(spacing: 10) {
                            ForEach(recap.topRated.prefix(3)) { entry in
                                NavigationLink(value: Route.media(entry.mediaId)) {
                                    HStack(spacing: 12) {
                                        PosterImage(media: entry.media, width: 46, cornerRadius: 7)
                                        Text(model.title(entry.media))
                                            .font(.headline)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(2)
                                        Spacer()
                                        if entry.isScored {
                                            Text(model.scoreFormat.display(entry.score))
                                                .font(.headline.monospacedDigit())
                                                .foregroundStyle(Theme.caution)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("You were \(recap.archetype)\(recap.journalCount > 0 ? " · \(recap.journalCount) journal notes" : "")")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        ShareLink(item: shareText(recap)) {
                            Label("Share my recap", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                .onChange(of: page) { Haptics.tick() }
            }
        }
        .screenChrome("\(String(year)) Recap", atmosphere: .night)
        .task {
            if model.activities.isEmpty { await model.refreshActivities() }
        }
    }

    private func shareText(_ recap: YearRecap) -> String {
        var lines = ["My \(String(recap.year)) in anime & manga (via Anilite):"]
        lines.append("• \(recap.minutes / 60) hours watched, \(recap.chapters) chapters read")
        lines.append("• \(recap.completedAnime.count + recap.completedManga.count) titles finished")
        if let top = recap.topGenres.first { lines.append("• Top genre: \(top.0)") }
        if let best = recap.topRated.first { lines.append("• Favourite: \(model.title(best.media))") }
        lines.append("• Archetype: \(recap.archetype)")
        return lines.joined(separator: "\n")
    }
}

private struct RecapPage<Content: View>: View {
    let index: Int
    let page: Int
    let eyebrow: String
    let tint: Color
    @ViewBuilder var content: Content
    @Environment(EffectsBudget.self) private var budget

    var body: some View {
        let isCurrent = index == page
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: eyebrow, color: tint)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
        .background {
            CardSurface(band: tint) { Color.clear }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 50)
        .opacity(isCurrent || !budget.allowsPhysics ? 1 : 0.5)
        .animation(Motion.gentle, value: isCurrent)
    }
}

/// A headline number. It doesn't count up: the figure is the point, so it's there at once.
private struct BigNumber: View {
    let value: Int
    var suffix: String = ""

    var body: some View {
        Text("\(value)\(suffix)")
            .font(Typo.bigMetric)
            .foregroundStyle(Theme.textPrimary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

private struct PosterStack: View {
    let entries: [LibraryEntry]

    var body: some View {
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.offset) { pair in
                let offset = CGFloat(pair.offset) - CGFloat(entries.count - 1) / 2
                PosterImage(media: pair.element.media, width: 88, cornerRadius: Theme.cornerCover)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerCover).strokeBorder(Theme.ink0, lineWidth: 1.5))
                    .offset(x: offset * 38)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .accessibilityHidden(true)
    }
}

private struct MonthBars: View {
    let minutes: [Int]
    let highlight: Int?
    let animate: Bool
    @State private var grown = false

    var body: some View {
        let maxValue = max(1, minutes.max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(minutes.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(highlight == index + 1 ? Theme.positive : Theme.positive.opacity(0.35))
                                .frame(height: (grown || !animate) ? max(3, proxy.size.height * CGFloat(minutes[index]) / CGFloat(maxValue)) : 3)
                        }
                    }
                    Text(String(Calendar.current.veryShortMonthSymbols[index % 12]))
                        .font(Typo.micro)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .onAppear {
            guard animate else { return }
            withAnimation(Motion.reveal.delay(0.1)) { grown = true }
        }
        .onChange(of: animate) {
            if animate { withAnimation(Motion.reveal) { grown = true } }
        }
        .accessibilityElement()
        .accessibilityLabel("Minutes watched per month")
        .accessibilityValue(minutes.enumerated().map { "\(Calendar.current.shortMonthSymbols[$0.offset % 12]) \($0.element / 60) hours" }.joined(separator: ", "))
    }
}
