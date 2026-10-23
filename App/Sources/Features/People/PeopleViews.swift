import SwiftUI
import AniliteKit

// MARK: - Character

struct CharacterView: View {
    let characterId: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncContent(id: "character-\(characterId)") {
            try await model.client.fetch(Queries.character(id: characterId), policy: .cacheFirst).Character
        } content: { character in
            CharacterContent(character: character)
        }
        .screenChrome("Character")
    }
}

private struct CharacterContent: View {
    let character: AniliteKit.Character
    @Environment(AppModel.self) private var model
    @State private var revealSpoilers = false

    var body: some View {
        let works = (character.media?.edges ?? []).compactMap { edge -> (Media, CharacterRole?)? in
            guard let node = edge.node, !(node.isAdult ?? false) else { return nil }
            return (node, edge.characterRole)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PersonHeader(imageURL: character.image?.best, name: character.name?.full ?? "Unknown",
                             native: character.name?.native,
                             facts: [character.gender, character.age.map { "Age \($0)" }, character.favourites.map { "♥ \(Formatting.compact($0))" }].compactMap { $0 })

                if let description = character.description, !description.isEmpty {
                    BioText(raw: description, revealSpoilers: $revealSpoilers)
                }

                if !works.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Appears in")
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(works, id: \.0.id) { pair in
                                    PosterCard(media: pair.0, width: 112, caption: pair.1.map(roleLabel))
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.hidden)
                    }
                    .padding(.horizontal, -Theme.gutter)
                }
                AttributionNote(path: "character/\(character.id)")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private func roleLabel(_ role: CharacterRole) -> String {
        switch role {
        case .main: return "Main role"
        case .supporting: return "Supporting"
        case .background: return "Background"
        }
    }
}

// MARK: - Staff

struct StaffView: View {
    let staffId: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncContent(id: "staff-\(staffId)") {
            try await model.client.fetch(Queries.staff(id: staffId), policy: .cacheFirst).Staff
        } content: { staff in
            StaffContent(staff: staff)
        }
        .screenChrome("Creator")
    }
}

private struct StaffContent: View {
    let staff: Staff
    @Environment(AppModel.self) private var model
    @State private var revealSpoilers = false

    var body: some View {
        let works = (staff.staffMedia?.nodes ?? []).filter { !($0.isAdult ?? false) }
        let seen = works.filter { model.entry($0.id) != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PersonHeader(imageURL: staff.image?.best, name: staff.name?.full ?? "Unknown", native: staff.name?.native,
                             facts: staff.primaryOccupations ?? [])
                if !seen.isEmpty {
                    Label("You've seen or read \(seen.count) of their works", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brandCool)
                }
                if let description = staff.description, !description.isEmpty {
                    BioText(raw: description, revealSpoilers: $revealSpoilers)
                }
                if !works.isEmpty {
                    WorksGrid(title: "Works", works: works)
                }
                AttributionNote(path: "staff/\(staff.id)")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Studio

struct StudioView: View {
    let studioId: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncContent(id: "studio-\(studioId)") {
            try await model.client.fetch(Queries.studio(id: studioId), policy: .cacheFirst).Studio
        } content: { studio in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: studio.isAnimationStudio == true ? "Animation studio" : "Studio")
                        Text(studio.name)
                            .font(Typo.display(30))
                            .foregroundStyle(Theme.textPrimary)
                        StudioSummary(works: studio.media?.nodes ?? [])
                    }
                    .padding(.top, 8)
                    WorksGrid(title: "Popular works", works: (studio.media?.nodes ?? []).filter { !($0.isAdult ?? false) })
                    AttributionNote(path: "studio/\(studio.id)")
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .screenChrome("Studio")
    }
}

private struct StudioSummary: View {
    let works: [Media]
    @Environment(AppModel.self) private var model

    var body: some View {
        let mine = works.compactMap { model.entry($0.id) }
        let scored = mine.filter(\.isScored)
        let average = scored.isEmpty ? nil : scored.map(\.score).reduce(0, +) / Double(scored.count)
        if !mine.isEmpty {
            HStack(spacing: 8) {
                StatPill(symbol: "checkmark.circle", text: "\(mine.count) in your library", tint: Theme.positive)
                if let average {
                    StatPill(symbol: "star.fill", text: "You average \(model.scoreFormat.display(average))", tint: Theme.caution)
                }
            }
        }
    }
}

// MARK: - Browse by genre or tag

struct BrowseView: View {
    enum Kind: Hashable {
        case genre(String)
        case tag(String)

        var name: String {
            switch self {
            case .genre(let name), .tag(let name): return name
            }
        }
    }

    let kind: Kind
    @State var type: MediaType
    @Environment(AppModel.self) private var model

    init(kind: Kind, type: MediaType) {
        self.kind = kind
        _type = State(initialValue: type)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $type) {
                Text("Anime").tag(MediaType.anime)
                Text("Manga").tag(MediaType.manga)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)

            AsyncContent(id: "browse-\(kind.name)-\(type.rawValue)") { [kind, type] () async throws -> [Media] in
                let op: GraphQLOperation<PageResponse>
                switch kind {
                case .genre(let name): op = Queries.byGenre(name, type: type)
                case .tag(let name): op = Queries.byTag(name, type: type)
                }
                return try await model.client.fetch(op, policy: .cacheFirst).Page.media
            } content: { media in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        let safe = media.filter { !($0.isAdult ?? false) }
                        if safe.isEmpty {
                            EmptyStateView(symbol: "square.stack.3d.up.slash", title: "Nothing here yet",
                                           message: "AniList has no \(type == .anime ? "anime" : "manga") under “\(kind.name)”.")
                        } else {
                            let ranked = rankForMe(safe)
                            if model.dna.isMeaningful, let top = ranked.first {
                                Label("Best match for you: \(model.title(top))", systemImage: "dna")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.brandCool)
                            }
                            WorksGrid(title: "Most popular", works: safe)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .screenChrome(kind.name)
    }

    private func rankForMe(_ media: [Media]) -> [Media] {
        media.filter { model.entry($0.id) == nil }
            .sorted { model.dna.affinity(for: $0) > model.dna.affinity(for: $1) }
    }
}

// MARK: - Shared pieces

private struct PersonHeader: View {
    let imageURL: String?
    let name: String
    let native: String?
    let facts: [String]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            RemoteImage(imageURL, points: 130)
                .frame(width: 112, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(Typo.display(26))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let native, !native.isEmpty {
                    Text(native)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Biography text; AniList marks spoilers inline, which stay hidden until asked for.
private struct BioText: View {
    let raw: String
    @Binding var revealSpoilers: Bool
    @State private var expanded = false

    var body: some View {
        let hasSpoilers = RichText.segments(from: raw).contains(where: \.isSpoiler)
        let text = RichText.plain(raw, includeSpoilers: revealSpoilers)
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(expanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if text.count > 280 {
                    Button(expanded ? "Show less" : "Read more") {
                        withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                    }
                }
                if hasSpoilers {
                    Button(revealSpoilers ? "Hide spoilers" : "Show hidden spoilers") {
                        withAnimation { revealSpoilers.toggle() }
                    }
                    .foregroundStyle(Theme.caution)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.brandCool)
        }
    }
}

private struct WorksGrid: View {
    let title: String
    let works: [Media]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], spacing: 16) {
                ForEach(works) { media in
                    PosterCard(media: media, width: 104)
                }
            }
        }
    }
}

struct AttributionNote: View {
    let path: String

    var body: some View {
        if let url = URL(string: "https://anilist.co/\(path)") {
            Link(destination: url) {
                Label("Data from AniList", systemImage: "arrow.up.right.square")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 8)
        }
    }
}
