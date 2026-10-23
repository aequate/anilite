import SwiftUI
import AniliteKit

/// One turn in the concierge conversation.
struct ConciergeTurn: Identifiable, Equatable {
    enum Role: Equatable { case user, guide }

    enum Content: Equatable {
        case text(String)
        case term(GlossaryTerm)
        case picks([GatewayPick], [Int: Media])
        case media(intro: String, items: [Media])
        case franchise(advice: String, steps: [String], mediaId: Int, title: String)
        case searchSuggestion(String)
    }

    let id = UUID()
    let role: Role
    let content: Content

    static func == (a: ConciergeTurn, b: ConciergeTurn) -> Bool { a.id == b.id }
}

/// A beginner-friendly guide that answers in plain language. It understands questions
/// on-device and answers from AniList data and Anilite's own engines, so nothing you
/// ask leaves the phone except the title lookups it needs.
@MainActor
@Observable
final class ConciergeModel {
    private(set) var turns: [ConciergeTurn] = []
    private(set) var isThinking = false

    static let suggestions = [
        "I'm new to anime, where do I start?",
        "Where do I start with Monogatari?",
        "Watch order for Fate",
        "Does Naruto have filler?",
        "Something like Frieren",
        "What's an OVA?",
        "What should I watch next?",
        "Something short and funny"
    ]

    func greet() {
        guard turns.isEmpty else { return }
        turns.append(ConciergeTurn(role: .guide, content: .text(
            "Hi! Ask me anything — where to start a series, what order to watch it in, which episodes are filler, or what a word means. No question is too basic.")))
    }

    func ask(_ question: String, model: AppModel) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        turns.append(ConciergeTurn(role: .user, content: .text(trimmed)))
        isThinking = true
        defer { isThinking = false }
        let reply = await answer(Concierge.interpret(trimmed), raw: trimmed, model: model)
        withAnimation(Motion.standard) {
            turns.append(contentsOf: reply.map { ConciergeTurn(role: .guide, content: $0) })
        }
        Haptics.tick()
    }

    private func answer(_ intent: ConciergeIntent, raw: String, model: AppModel) async -> [ConciergeTurn.Content] {
        do {
            switch intent {
            case .greeting:
                return [.text("Try one of the suggestions below, or ask in your own words.")]

            case .define(let term):
                return [.term(term)]

            case .beginnerPicks(let topics):
                let picks = Gateway.picks(matching: topics, limit: 4)
                let chosen = picks.isEmpty ? Array(Gateway.picks.prefix(4)) : picks
                let covers = (try? await model.client.fetch(Queries.cards(ids: chosen.map(\.id)), policy: .cacheFirst).Page.media) ?? []
                let lookup = Dictionary(covers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let intro = topics.isEmpty
                    ? "Here are great first picks — each is easy to get into and doesn't need any background."
                    : "Here's where I'd start for \(topics.sorted().joined(separator: ", ")):"
                return [.text(intro), .picks(chosen, lookup)]

            case .whereToStart(let franchise), .watchOrder(let franchise), .fillerQuestion(let franchise):
                guard let seed = try await findTitle(franchise, model: model) else {
                    return [.text("I couldn't find “\(franchise)” on AniList. Check the spelling, or try its Japanese title."), .searchSuggestion(franchise)]
                }
                let pathfinder = PathfinderModel(mediaId: seed.id)
                await pathfinder.load(client: model.client)
                guard let graph = pathfinder.graph else {
                    return [.text(pathfinder.state.errorMessage ?? "I couldn't map that franchise right now.")]
                }
                let title = model.title(seed)
                let route = pathfinder.routes.first
                let steps = (route?.steps ?? []).filter { !$0.isOptional }.prefix(8).map { step in
                    "\(model.title(step.media)) · \(step.role.label)"
                }
                switch intent {
                case .fillerQuestion:
                    let infos = graph.mainline.compactMap { media in FillerGuide.info(for: media.id).map { (media, $0) } }
                    if infos.isEmpty {
                        return [.text("I don't have a filler list for \(title). Most modern series have little or no filler; anything adapted closely from the manga is safe to watch straight through."),
                                .franchise(advice: Concierge.startAdvice(graph: graph), steps: Array(steps), mediaId: seed.id, title: title)]
                    }
                    let lines = infos.map { pair -> String in
                        let (media, info) = pair
                        let shown: [String] = info.ranges.prefix(4).map { range in
                            range.count == 1 ? String(range.lowerBound) : "\(range.lowerBound)–\(range.upperBound)"
                        }
                        let more = info.ranges.count > 4 ? ", …" : ""
                        let rangeText = shown.joined(separator: ", ") + more
                        return "\(model.title(media)): \(info.fillerCount) filler episodes (\(rangeText))."
                    }
                    return [.text(lines.joined(separator: "\n") + "\nFiller is optional. Pathfinder can build a route that skips it."),
                            .franchise(advice: Concierge.startAdvice(graph: graph), steps: Array(steps), mediaId: seed.id, title: title)]
                default:
                    return [.franchise(advice: Concierge.startAdvice(graph: graph), steps: Array(steps), mediaId: seed.id, title: title)]
                }

            case .findSimilar(let title):
                guard let seed = try await findTitle(title, model: model) else {
                    return [.text("I couldn't find “\(title)”."), .searchSuggestion(title)]
                }
                let detail = try await model.client.fetch(Queries.detail(id: seed.id), policy: .cacheFirst).Media
                let similar = (detail.recommendations?.nodes ?? [])
                    .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
                    .compactMap(\.mediaRecommendation)
                    .filter { SpoilerShield.isSafeRecommendation($0, library: model.library, policy: model.spoilerPolicy) && !($0.isAdult ?? false) }
                guard !similar.isEmpty else {
                    return [.text("AniList doesn't have recommendations for \(model.title(detail)) yet.")]
                }
                return [.media(intro: "Fans of \(model.title(detail)) also loved:", items: Array(similar.prefix(6)))]

            case .whatNext:
                if !model.forYou.isEmpty {
                    return [.media(intro: "Based on your Taste DNA, these are your strongest matches:", items: model.forYou.prefix(6).map(\.media))]
                }
                let current = model.library.all.filter { $0.status.isActive }.sorted { $0.updatedAt > $1.updatedAt }
                if !current.isEmpty {
                    return [.media(intro: "You're in the middle of these — finishing one is the most satisfying next step:", items: current.prefix(6).map(\.media))]
                }
                return [.text("Add a few titles you've enjoyed to your library and I'll tailor picks to you. Until then, here are easy starting points:"),
                        .picks(Array(Gateway.picks.prefix(4)), [:])]

            case .search(let text):
                if let term = Glossary.mentioned(in: text).first {
                    return [.term(term), .searchSuggestion(text)]
                }
                return [.text("I'm not sure what you mean, so let's search for it."), .searchSuggestion(text)]
            }
        } catch {
            return [.text(AppModel.message(for: error))]
        }
    }

    private func findTitle(_ text: String, model: AppModel) async throws -> Media? {
        for type in [MediaType.anime, .manga] {
            var query = DiscoveryQuery(text: text, type: type)
            query.sort = .relevance
            if let first = try await model.client.fetch(Queries.search(query), policy: .cacheFirst).Page.media.first(where: { !($0.isAdult ?? false) }) {
                return first
            }
        }
        return nil
    }
}

struct ConciergeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var concierge = ConciergeModel()
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(concierge.turns) { turn in
                            TurnView(turn: turn, open: open, search: search)
                                .id(turn.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if concierge.isThinking {
                            ThinkingDots()
                                .id("thinking")
                        }
                        if concierge.turns.count <= 1 {
                            suggestionGrid
                        }
                    }
                    .padding(Theme.gutter)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: concierge.turns.count) {
                    if let last = concierge.turns.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .background(ScreenBackground(atmosphere: .night, intensity: 0.4))
            .navigationTitle("Concierge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { concierge.greet() }
        .presentationDragIndicator(.visible)
    }

    private var suggestionGrid: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(ConciergeModel.suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    Chip(label: suggestion, symbol: nil)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.top, 4)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask anything about anime or manga", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .surface()
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.ink3 : Theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || concierge.isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func send(_ text: String) {
        let question = text
        draft = ""
        Task { await concierge.ask(question, model: model) }
    }

    private func open(_ route: Route) {
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.push(route)
        }
    }

    private func search(_ text: String) {
        dismiss()
        router.search(text)
    }
}

private struct TurnView: View {
    let turn: ConciergeTurn
    let open: (Route) -> Void
    let search: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 50) }
            content
                .frame(maxWidth: turn.role == .user ? nil : .infinity, alignment: .leading)
            if turn.role == .guide { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder private var content: some View {
        switch turn.content {
        case .text(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(turn.role == .user ? Theme.accent.opacity(0.85) : Color.white.opacity(0.07))
                }
                .fixedSize(horizontal: false, vertical: true)

        case .term(let term):
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: term.category.rawValue)
                Text(term.term)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(term.definition)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !term.aliases.isEmpty {
                    Text("Also: \(term.aliases.joined(separator: ", "))")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(16)
            .surface()

        case .picks(let picks, let covers):
            VStack(spacing: 10) {
                ForEach(picks) { pick in
                    Button { open(.media(pick.id)) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            if let media = covers[pick.id] {
                                PosterImage(media: media, width: 52, cornerRadius: 8)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.ink3).frame(width: 52, height: 74)
                                    .overlay(Image(systemName: pick.type == .anime ? "play.tv" : "book").foregroundStyle(Theme.textTertiary))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(covers[pick.id].map { model.title($0) } ?? pick.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(pick.why)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(pick.commitment)
                                    .font(Typo.caption)
                                    .foregroundStyle(Theme.accentCool)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .surface()
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }

        case .media(let intro, let items):
            VStack(alignment: .leading, spacing: 10) {
                Text(intro)
                    .foregroundStyle(Theme.textPrimary)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(items) { media in
                            Button { open(.media(media.id)) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    PosterImage(media: media, width: 96, cornerRadius: 10)
                                    Text(model.title(media))
                                        .font(Typo.caption)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(2)
                                        .frame(width: 96, alignment: .leading)
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

        case .franchise(let advice, let steps, let mediaId, let title):
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: title)
                Text(advice)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(pair.offset + 1)")
                                    .font(Typo.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 18, alignment: .trailing)
                                Text(pair.element)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                HStack {
                    Button("Open Pathfinder") { open(.pathfinder(mediaId)) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("View title") { open(.media(mediaId)) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .surface()

        case .searchSuggestion(let text):
            Button { search(text) } label: {
                Label("Search for “\(text)”", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct ThinkingDots: View {
    @Environment(EffectsBudget.self) private var budget

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !budget.allowsPhysics)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(budget.allowsPhysics ? 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 5 - Double(i) * 0.8)) : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
        }
        .accessibilityLabel("Thinking")
    }
}
