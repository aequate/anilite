import SwiftUI
import AniliteKit

/// Tab root: who you are as a fan, and the doors to everything personal.
struct YouView: View {
    @Environment(AppModel.self) private var model

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                NavigationLink(value: Route.tasteDNA) {
                    ArchetypeCard(dna: model.dna, name: model.account.displayName ?? "You")
                }
                .buttonStyle(PressableStyle(scale: 0.98))

                lifetimeStats

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Your story")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        YouTile(route: .recap(currentYear), symbol: "calendar", title: "\(String(currentYear)) Recap",
                                detail: "Your year so far", tint: Theme.accent)
                        YouTile(route: .achievements, symbol: "rosette", title: "Achievements",
                                detail: "\(model.achievements.filter(\.isUnlocked).count) of \(model.achievements.count) unlocked", tint: Theme.caution)
                        YouTile(route: .social, symbol: "person.2.wave.2", title: "Friends & Clubs",
                                detail: socialDetail, tint: Theme.accentCool)
                        YouTile(route: .recap(currentYear - 1), symbol: "clock.arrow.circlepath", title: "\(String(currentYear - 1)) Recap",
                                detail: "Look back", tint: Theme.positive)
                    }
                }

                VStack(spacing: 0) {
                    RowLink(route: .glossary, symbol: "character.book.closed", title: "Anime glossary")
                    Divider().overlay(Theme.hairline)
                    RowLink(route: .settings, symbol: "gearshape", title: "Settings")
                }
                .surface(cornerRadius: 18)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .screenChrome("You", large: true)
    }

    private var socialDetail: String {
        let friends = model.friends.count
        let clubs = model.clubs.count
        if friends == 0 && clubs == 0 { return "Compare tastes, watch together" }
        return "\(friends) friend\(friends == 1 ? "" : "s") · \(clubs) club\(clubs == 1 ? "" : "s")"
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.ink3)
                if let avatar = model.library.user?.avatar?.large {
                    RemoteImage(avatar, points: 64).clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 58, height: 58)
            .overlay(Circle().strokeBorder(Theme.hairline))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.account.displayName ?? "Your library")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.account.summary)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var lifetimeStats: some View {
        let all = model.library.all
        let minutes = all.reduce(0) { total, entry in
            let units = entry.status == .completed ? (entry.media.totalUnits ?? entry.progress) : entry.progress
            return total + (entry.type == .anime ? units * entry.media.minutesPerUnit * (1 + entry.repeatCount) : 0)
        }
        let chapters = all.filter { $0.type == .manga }.reduce(0) { $0 + $1.progress }
        let completed = all.filter { $0.status == .completed }.count
        return HStack(spacing: 10) {
            StatBlock(value: Formatting.duration(minutes: minutes), label: "watched")
            StatBlock(value: Formatting.compact(chapters), label: "chapters")
            StatBlock(value: Formatting.compact(completed), label: "completed")
        }
    }
}

private struct StatBlock: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Typo.metric)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .surface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct YouTile: View {
    let route: Route
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(14)
            .surface(cornerRadius: 18, tint: tint.opacity(0.25))
        }
        .buttonStyle(PressableStyle())
    }
}

struct RowLink: View {
    let route: Route
    let symbol: String
    let title: String

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 24)
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Archetype card

/// The Taste DNA identity card, set like the title page of a volume.
struct ArchetypeCard: View {
    let dna: TasteDNA
    let name: String
    var compact = true

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Taste DNA of \(name)", color: Theme.textSecondary)
                    Spacer()
                    Image(systemName: dna.archetype.symbol)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(dna.isMeaningful ? dna.archetype.name : "Still forming")
                    .font(Typo.display(compact ? 28 : 34))
                    .foregroundStyle(Theme.textPrimary)
                Text(dna.isMeaningful ? dna.archetype.summary : "Rate or finish a few titles and your fan archetype will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if dna.isMeaningful {
                    StrandBar(strands: Array(dna.strands.prefix(8)))
                        .frame(height: 30)
                    Text(dna.topGenres.prefix(4).joined(separator: ", "))
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your Taste DNA")
    }
}

/// A double-helix of the strongest taste strands, drawn once with Canvas.
private struct StrandBar: View {
    let strands: [TasteStrand]

    var body: some View {
        Canvas { context, size in
            guard !strands.isEmpty else { return }
            let maxWeight = strands.map { abs($0.weight) }.max() ?? 1
            let step = size.width / CGFloat(strands.count)
            for (index, strand) in strands.enumerated() {
                let x = step * (CGFloat(index) + 0.5)
                let strength = CGFloat(abs(strand.weight) / max(maxWeight, 0.0001))
                let height = max(4, size.height * strength)
                let rect = CGRect(x: x - step * 0.3, y: (size.height - height) / 2, width: step * 0.6, height: height)
                let color = strand.kind == .genre ? Theme.accent : Theme.accentCool
                context.fill(Path(roundedRect: rect, cornerRadius: step * 0.3), with: .color(color.opacity(0.4 + 0.6 * Double(strength))))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A printed card: solid stock, a hairline edge and a thin rule of the title's colour
/// along the top, like the band on a volume's obi.
struct CardSurface<Content: View>: View {
    var cornerRadius: CGFloat = Theme.corner
    var band: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(cornerRadius, Theme.corner), style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink1, in: shape)
            .overlay(alignment: .top) {
                Rectangle().fill(band).frame(height: 3)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.75))
    }
}
