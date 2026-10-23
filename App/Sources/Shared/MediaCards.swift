import SwiftUI
import AniliteKit

/// Cover art with the title's own colour as a placeholder while it loads.
struct PosterImage: View {
    let media: Media
    var width: CGFloat
    var cornerRadius: CGFloat = Theme.cornerSmall

    var body: some View {
        RemoteImage(media.coverImage?.thumbnail, points: width * 1.5,
                    placeholder: Color(anilistHex: media.coverImage?.color)?.opacity(0.35) ?? Theme.ink2)
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            )
    }
}

/// Standard poster tile used in every horizontal rail.
struct PosterCard: View {
    let media: Media
    var width: CGFloat = 124
    var badge: String?
    var caption: String?

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: Route.media(media.id)) {
            VStack(alignment: .leading, spacing: 8) {
                PosterImage(media: media, width: width)
                    .overlay(alignment: .topLeading) {
                        if let badge {
                            Text(badge)
                                .font(Typo.micro)
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color(anilistHex: media.coverImage?.color) ?? Theme.brand, in: Capsule())
                                .padding(7)
                        }
                    }
                    .overlay(alignment: .bottom) { progressOverlay }
                    .heroSource(media.id)
                Text(model.title(media))
                    .font(Typo.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(caption ?? subtitle)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .contextMenu { MediaQuickActions(media: media) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    private var subtitle: String {
        var parts: [String] = [media.formatLabel]
        if let year = media.year { parts.append(String(year)) }
        if let score = media.averageScore { parts.append("\(score)%") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var progressOverlay: some View {
        if let entry = model.entry(media.id), entry.status.isActive, let completion = entry.completion {
            ProgressBar(progress: completion, tint: Color(anilistHex: media.coverImage?.color) ?? Theme.brand, height: 3)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}

/// Horizontal rail with a header.
struct MediaRail: View {
    let title: String
    var subtitle: String?
    let items: [Media]
    var cardWidth: CGFloat = 124
    var badge: ((Media) -> String?)?
    var caption: ((Media) -> String?)?

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, subtitle: subtitle)
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { media in
                            PosterCard(media: media, width: cardWidth, badge: badge?(media), caption: caption?(media))
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

/// Compact list row for library and search lists.
struct MediaRow: View {
    let media: Media
    var detail: String?
    var showsLibraryState = true

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: Route.media(media.id)) {
            HStack(spacing: 14) {
                PosterImage(media: media, width: 58, cornerRadius: 10)
                    .heroSource(media.id)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title(media))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail ?? defaultDetail)
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    if showsLibraryState, let entry = model.entry(media.id) {
                        HStack(spacing: 8) {
                            StatusDot(status: entry.status)
                            Text(entryLine(entry))
                                .font(Typo.micro)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        if entry.status.isActive, let completion = entry.completion {
                            ProgressBar(progress: completion, tint: Color(anilistHex: media.coverImage?.color) ?? Theme.brand, height: 3)
                                .frame(maxWidth: 160)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .contextMenu { MediaQuickActions(media: media) }
        .accessibilityElement(children: .combine)
    }

    private var defaultDetail: String {
        var parts: [String] = [media.formatLabel]
        if let year = media.year { parts.append(String(year)) }
        if let total = media.totalUnits { parts.append("\(total) \(media.unitShort.lowercased())") }
        if let genres = media.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func entryLine(_ entry: LibraryEntry) -> String {
        var line = entry.status.label(for: entry.type)
        if entry.progress > 0 {
            line += " · \(entry.media.unitShort) \(entry.progress)"
            if let total = entry.media.totalUnits { line += "/\(total)" }
        }
        if entry.isScored { line += " · ★ \(model.scoreFormat.display(entry.score))" }
        return line
    }
}

struct StatusDot: View {
    let status: MediaListStatus

    var body: some View {
        Circle()
            .fill(Self.color(status))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    static func color(_ status: MediaListStatus) -> Color {
        switch status {
        case .current, .repeating: return Theme.positive
        case .planning: return Theme.brandCool
        case .completed: return Color(hex: 0xA48BFF)
        case .paused: return Theme.caution
        case .dropped: return Theme.negative
        }
    }

    static func symbol(_ status: MediaListStatus) -> String {
        switch status {
        case .current: return "play.circle.fill"
        case .repeating: return "arrow.counterclockwise.circle.fill"
        case .planning: return "bookmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }
}

/// Long-press actions available on every card.
struct MediaQuickActions: View {
    let media: Media
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        if let entry = model.entry(media.id) {
            if entry.status.isActive, (media.totalUnits ?? Int.max) > entry.progress {
                Button {
                    model.increment(entry)
                } label: {
                    Label("Mark \(media.unitShort) \(entry.progress + 1) done", systemImage: "plus.circle")
                }
            }
            Button {
                router.sheet = .editor(media)
            } label: {
                Label("Edit entry", systemImage: "slider.horizontal.3")
            }
        } else if model.canEdit {
            Button {
                model.add(media, status: .planning)
            } label: {
                Label("Add to Planning", systemImage: "bookmark")
            }
            Button {
                model.add(media, status: .current)
            } label: {
                Label(media.mediaType == .anime ? "Start watching" : "Start reading", systemImage: "play")
            }
        }
        Button {
            router.push(.pathfinder(media.id))
        } label: {
            Label("Watch order", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
        if let url = URL(string: "anilite://media/\(media.id)") {
            ShareLink(item: url, subject: Text(model.title(media))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// Small score/genre/format metadata line.
struct MetaLine: View {
    let items: [String]

    var body: some View {
        Text(items.filter { !$0.isEmpty }.joined(separator: "  ·  "))
            .font(Typo.caption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
    }
}
