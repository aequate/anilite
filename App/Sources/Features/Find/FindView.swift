import SwiftUI
import AniliteKit

struct FindView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ask = "Ask"
        case moodMatch = "Mood Match"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var find = FindModel()
    @State private var mode: Mode = .ask
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            switch mode {
            case .ask: askContent
            case .moodMatch: MoodMatchView()
            }
        }
        .background {
            // Once there are results, the page takes on the best match.
            let lead = mode == .ask ? (find.seed ?? find.titleMatches.first ?? find.results.first) : nil
            ScreenBackground(atmosphere: .night, intensity: 0.5, artwork: lead?.backdropArtwork, artworkHint: lead?.coverImage?.color)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: consumePending)
        .onChange(of: router.pendingSearch) { _, _ in consumePending() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Find")
                    .font(Typo.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Mode", selection: $mode.animation(Motion.standard)) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)
            }
            if mode == .ask { searchField }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            TextField("Describe what you're in the mood for", text: $find.text, axis: .vertical)
                .lineLimit(1...3)
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { search() }
                .onChange(of: find.text) { _, newValue in
                    // Vertical text fields insert a newline on return; treat it as submit.
                    if newValue.hasSuffix("\n") {
                        find.text = String(newValue.dropLast())
                        search()
                    }
                }
            if !find.text.isEmpty {
                Button {
                    find.clear()
                    Haptics.tick()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .surface(interactive: true)
    }

    @ViewBuilder private var askContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if focused, !find.preview.isEmpty, find.preview != find.chips {
                    InterpretationRow(title: "I'll look for", chips: find.preview, removable: false) { _ in }
                }
                if find.hasSearched {
                    resultsContent
                } else {
                    SuggestionsView(onPick: { text in
                        find.text = text
                        search()
                    })
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
            .animation(Motion.standard, value: find.chips)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var resultsContent: some View {
        if !find.chips.isEmpty {
            InterpretationRow(title: "Understood as", chips: find.chips, removable: true) { chip in
                find.remove(chip, using: model)
            }
        }
        if let seed = find.seed {
            HStack(spacing: 10) {
                PosterImage(media: seed, width: 36, cornerRadius: 6)
                Text("Ranked by how closely each title's themes match **\(model.title(seed))**")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        switch find.state {
        case .loading where find.results.isEmpty:
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 14) {
                    Skeleton(cornerRadius: 10).frame(width: 58, height: 87)
                    VStack(alignment: .leading, spacing: 8) {
                        Skeleton().frame(height: 16)
                        Skeleton().frame(width: 140, height: 12)
                    }
                }
            }
        case .failed(let message):
            ErrorBanner(message: message) { search() }
        default:
            if find.results.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Nothing matched all of that",
                               message: "Try removing one of the chips above. Each one narrows the search.")
            } else {
                resultsList
            }
        }
        if !find.titleMatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Did you mean a title?")
                ForEach(find.titleMatches) { media in
                    MediaRow(media: media)
                }
            }
            .padding(.top, 8)
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "\(find.results.count)\(find.hasMore ? "+" : "") results")
            ForEach(find.results) { media in
                MediaRow(media: media, detail: detail(for: media))
                    .onAppear {
                        if media.id == find.results.last?.id { find.loadMore(using: model) }
                    }
                Divider().overlay(Theme.hairline)
            }
            if find.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func detail(for media: Media) -> String {
        var parts: [String] = [media.formatLabel]
        if let year = media.year { parts.append(String(year)) }
        if let minutes = media.totalMinutes, media.format != .movie, media.mediaType == .anime {
            parts.append(Formatting.duration(minutes: minutes))
        } else if let total = media.totalUnits {
            parts.append("\(total) \(media.unitShort.lowercased())")
        }
        if let score = media.averageScore { parts.append("\(score)%") }
        if model.dna.isMeaningful {
            let affinity = model.dna.affinity(for: media)
            if affinity > 0.35 { parts.append("fits your taste") }
        }
        return parts.joined(separator: " · ")
    }

    private func search() {
        focused = false
        find.submit(using: model)
    }

    private func consumePending() {
        guard let pending = router.pendingSearch else { return }
        router.pendingSearch = nil
        mode = .ask
        find.text = pending
        find.submit(using: model)
    }
}

/// Shows what the parser understood; tapping a removable chip drops that constraint.
private struct InterpretationRow: View {
    let title: String
    let chips: [InterpretationChip]
    let removable: Bool
    let onRemove: (InterpretationChip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            FlowLayout(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        if removable { onRemove(chip) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.symbol).font(.caption.weight(.bold))
                            Text(chip.label).font(.subheadline.weight(.semibold))
                            if removable {
                                Image(systemName: "xmark").font(.caption2.weight(.heavy)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(chip.kind == .exclude ? Theme.negative : Theme.textPrimary)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(chip.kind == .exclude ? Theme.negative.opacity(0.4) : Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .disabled(!removable)
                    .accessibilityLabel(removable ? "\(chip.label). Double-tap to remove" : chip.label)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

private struct SuggestionsView: View {
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    private let examples: [(String, String)] = [
        ("cup.and.saucer.fill", "short cozy fantasy, no romance"),
        ("moon.fill", "something like Frieren but darker"),
        ("brain.head.profile", "mind-bending sci-fi movie"),
        ("clock.fill", "I have 3 hours tonight"),
        ("diamond.fill", "hidden gem sports anime"),
        ("book.fill", "completed manhwa with a female lead"),
        ("gearshape.2.fill", "classic mecha from the 90s"),
        ("tram.fill", "bite-sized episodes for my commute")
    ]

    private let genres = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mecha", "Music", "Mystery",
                          "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Eyebrow(text: "Recent")
                        Spacer()
                        Button("Clear") { model.clearRecentSearches() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(model.recentSearches, id: \.self) { recent in
                            Button { onPick(recent) } label: { Chip(label: recent, symbol: "clock.arrow.circlepath") }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Ask in your own words")
                ForEach(examples, id: \.1) { example in
                    let text = example.1
                    Button { onPick(text) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: example.0)
                                .foregroundStyle(Theme.accentCool)
                                .frame(width: 24)
                            Text("“\(text)”")
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .surface()
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Browse by genre")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(genres, id: \.self) { genre in
                        NavigationLink(value: Route.genre(genre, .anime)) {
                            Text(genre)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .surface()
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }

            Button {
                router.sheet = .concierge
            } label: {
                Label("New to anime? Ask the Concierge", systemImage: "questionmark.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, 4)
    }
}
