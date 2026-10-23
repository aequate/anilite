import SwiftUI
import AniliteKit

/// Swipe deck: right saves to Planning, left skips, tap opens details.
/// Cards follow the finger with spring physics; haptics mark the decision threshold.
struct MoodMatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget

    @State private var moods: Set<Mood> = []
    @State private var deck: [Media] = []
    @State private var saved: [Media] = []
    @State private var skipped = 0
    @State private var drag: CGSize = .zero
    @State private var zone = 0
    @State private var loading = false
    @State private var flinging = false

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 14) {
            moodPicker
            ZStack {
                if deck.isEmpty {
                    finished
                } else {
                    ForEach(Array(deck.prefix(3).enumerated().reversed()), id: \.element.id) { pair in
                        card(pair.element, index: pair.offset)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.gutter)
            controls
        }
        .padding(.bottom, 10)
        .task { if deck.isEmpty { await rebuild() } }
        .onChange(of: moods) { _, _ in Task { await rebuild() } }
    }

    // MARK: Pieces

    private var moodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    Button {
                        Haptics.tick()
                        if moods.contains(mood) { moods.remove(mood) } else { moods.insert(mood) }
                    } label: {
                        Chip(label: mood.label, symbol: mood.symbol, isSelected: moods.contains(mood))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func card(_ media: Media, index: Int) -> some View {
        let isTop = index == 0
        let offset = isTop ? drag : .zero
        let rotation = budget.allowsPhysics && isTop ? Double(drag.width / 18) : 0
        return MoodCard(media: media, moods: Array(moods), likeAmount: isTop ? Double(drag.width / threshold) : 0)
            .scaleEffect(1 - CGFloat(index) * 0.05)
            .offset(x: offset.width, y: offset.height * 0.4 + CGFloat(index) * 14)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .opacity(index > 1 ? 0.6 : 1)
            .allowsHitTesting(isTop && !flinging)
            .gesture(dragGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: model.canEdit ? "Save to Planning" : "Like") { decide(.like) }
            .accessibilityAction(named: "Skip") { decide(.skip) }
            .zIndex(Double(3 - index))
            .transition(.identity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                drag = value.translation
                let newZone = value.translation.width > threshold ? 1 : (value.translation.width < -threshold ? -1 : 0)
                if newZone != zone {
                    zone = newZone
                    if newZone != 0 { Haptics.tap(.medium) } else { Haptics.tick() }
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if value.translation.width > threshold || projected > threshold * 2.2 {
                    decide(.like, velocity: projected)
                } else if value.translation.width < -threshold || projected < -threshold * 2.2 {
                    decide(.skip, velocity: projected)
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { drag = .zero }
                    zone = 0
                }
            }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            roundButton("xmark", tint: Theme.negative, label: "Skip") { decide(.skip) }
            if let top = deck.first {
                NavigationLink(value: Route.media(top.id)) {
                    Image(systemName: "info")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 52, height: 52)
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Details for \(model.title(top))")
            }
            roundButton(model.canEdit ? "bookmark.fill" : "heart.fill", tint: Theme.positive, label: model.canEdit ? "Save to Planning" : "Like") {
                decide(.like)
            }
        }
        .disabled(deck.isEmpty)
        .opacity(deck.isEmpty ? 0.4 : 1)
    }

    private func roundButton(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .glassCapsule(tint: tint, interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            if loading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 46))
                    .foregroundStyle(Theme.brandCool)
                Text(saved.isEmpty ? "That's the deck" : "\(saved.count) saved, \(skipped) skipped")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if !saved.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(saved) { media in
                                NavigationLink(value: Route.media(media.id)) {
                                    PosterImage(media: media, width: 64, cornerRadius: 8)
                                }
                            }
                        }
                    }
                    .frame(height: 100)
                }
                Text(model.canEdit ? "Saved titles are in your Planning list." : "Connect AniList or use a local library to save picks.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Deal a new deck") { Task { await rebuild(fresh: true) } }
                    .buttonStyle(GlowButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 28)
    }

    // MARK: Logic

    private enum Decision { case like, skip }

    private func decide(_ decision: Decision, velocity: CGFloat = 0) {
        guard let top = deck.first, !flinging else { return }
        flinging = true
        let direction: CGFloat = decision == .like ? 1 : -1
        let distance = max(520, abs(velocity))
        let animation: Animation = budget.allowsPhysics ? .spring(response: 0.38, dampingFraction: 0.9) : .easeOut(duration: 0.2)
        if decision == .like {
            Haptics.success()
            if model.canEdit, model.entry(top.id) == nil { model.add(top, status: .planning) }
            saved.append(top)
        } else {
            Haptics.tap(.soft)
            skipped += 1
        }
        withAnimation(animation) {
            drag = CGSize(width: direction * distance, height: drag.height + 40)
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if !deck.isEmpty { deck.removeFirst() }
                drag = .zero
            }
            zone = 0
            flinging = false
        }
    }

    private func rebuild(fresh: Bool = false) async {
        var pool: [Media] = []
        var seen = Set<Int>()
        let excluded = Set(model.library.entries.keys).union(saved.map(\.id))
        func take(_ list: [Media]) {
            for media in list where !excluded.contains(media.id) && !(media.isAdult ?? false) && seen.insert(media.id).inserted {
                pool.append(media)
            }
        }
        take(model.forYou.map(\.media))
        if let home = model.home {
            take(home.trending.media)
            take(home.season.media)
            take(home.top.media)
        }
        if pool.count < 12 || !moods.isEmpty || fresh {
            loading = true
            var q = DiscoveryQuery()
            q.moods = Array(moods)
            q.sort = fresh ? .trending : .score
            let page = fresh ? Int.random(in: 2...4) : 1
            if let more = try? await model.client.fetch(Queries.search(q.preparedForServer(), page: page), policy: .cacheFirst) {
                take(more.Page.media)
            }
            loading = false
        }
        let ranked: [Media]
        if moods.isEmpty {
            ranked = fresh ? pool.shuffled() : pool
        } else {
            let selected = Array(moods)
            ranked = pool
                .map { media -> (Media, Double) in
                    let vibe = VibeProfile.of(media)
                    let fit = selected.map { vibe.moodScore($0) }.reduce(0, +) / Double(selected.count)
                    return (media, fit + (model.dna.isMeaningful ? 0.3 * model.dna.affinity(for: media) : 0))
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            deck = Array(ranked.prefix(24))
        }
        ImagePipeline.shared.prefetch(deck.prefix(6).compactMap { $0.coverImage?.best }, points: 460)
    }
}

/// One card in the deck.
private struct MoodCard: View {
    let media: Media
    let moods: [Mood]
    /// -1 … 1+ as the card is dragged; drives the stamps.
    let likeAmount: Double

    @Environment(AppModel.self) private var model

    var body: some View {
        let vibe = VibeProfile.of(media)
        let tint = Color(anilistHex: media.coverImage?.color) ?? Theme.brand
        ZStack(alignment: .bottomLeading) {
            RemoteImage(media.coverImage?.best, points: 460, placeholder: tint.opacity(0.35))
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text(model.title(media))
                    .font(Typo.display(26))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                MetaLine(items: meta)
                HStack(spacing: 6) {
                    ForEach(topDimensions(vibe), id: \.label) { dim in
                        Text(dim.label)
                            .font(Typo.micro)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.25 + dim.value * 0.5), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                if !moods.isEmpty {
                    let fit = moods.map { vibe.moodScore($0) }.reduce(0, +) / Double(moods.count)
                    HStack(spacing: 8) {
                        ProgressBar(progress: fit, tint: tint, height: 5).frame(width: 120)
                        Text("\(Int(fit * 100))% mood fit").font(Typo.micro).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .overlay(alignment: .topLeading) { stamp(model.canEdit ? "SAVE" : "LIKE", color: Theme.positive, amount: likeAmount, angle: -14) }
        .overlay(alignment: .topTrailing) { stamp("SKIP", color: Theme.negative, amount: -likeAmount, angle: 14) }
        .shadow(color: tint.opacity(0.35), radius: 26, y: 14)
        .accessibilityLabel("\(model.title(media)). \(meta.joined(separator: ", "))")
    }

    private var meta: [String] {
        var items: [String] = [media.formatLabel]
        if let year = media.year { items.append(String(year)) }
        if let total = media.totalUnits { items.append("\(total) \(media.unitShort.lowercased())") }
        if let score = media.averageScore { items.append("\(score)%") }
        if let genres = media.genres { items.append(genres.prefix(2).joined(separator: ", ")) }
        return items
    }

    private func topDimensions(_ vibe: VibeProfile) -> [(label: String, value: Double)] {
        Array(vibe.dimensions.sorted { $0.value > $1.value }.prefix(3))
    }

    private func stamp(_ text: String, color: Color, amount: Double, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .padding(26)
            .opacity(clamp01(amount))
            .accessibilityHidden(true)
    }
}
