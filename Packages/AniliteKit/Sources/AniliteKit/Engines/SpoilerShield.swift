import Foundation

public enum SpoilerLevel: String, Codable, CaseIterable, Sendable {
    case off, relaxed, balanced, strict

    public var label: String {
        switch self {
        case .off: return "Off"
        case .relaxed: return "Relaxed"
        case .balanced: return "Balanced"
        case .strict: return "Strict"
        }
    }

    public var summary: String {
        switch self {
        case .off: return "Show everything."
        case .relaxed: return "Hide marked spoilers and spoiler tags only."
        case .balanced: return "Also hide future episode titles, late-story characters and sequel details."
        case .strict: return "Also blur sequel art and hold back anything beyond your progress."
        }
    }
}

public struct SpoilerPolicy: Codable, Hashable, Sendable {
    public var level: SpoilerLevel
    /// Titles the user explicitly unlocked ("I don't care about spoilers for this one").
    public var unlockedMediaIds: Set<Int>

    public init(level: SpoilerLevel = .balanced, unlockedMediaIds: Set<Int> = []) {
        self.level = level
        self.unlockedMediaIds = unlockedMediaIds
    }

    public var isEnabled: Bool { level != .off }
}

/// What we know about the viewer's relationship with a title.
public struct SpoilerContext: Hashable, Sendable {
    public var mediaId: Int
    public var status: MediaListStatus?
    public var progress: Int
    public var total: Int?

    public init(mediaId: Int, status: MediaListStatus?, progress: Int, total: Int?) {
        self.mediaId = mediaId
        self.status = status
        self.progress = progress
        self.total = total
    }

    public init(media: Media, entry: LibraryEntry?) {
        self.init(mediaId: media.id, status: entry?.status, progress: entry?.progress ?? 0, total: media.totalUnits)
    }

    public var hasFinished: Bool {
        status == .completed || status == .repeating || (total.map { $0 > 0 && progress >= $0 } ?? false)
    }

    public var fraction: Double {
        if hasFinished { return 1 }
        guard let total, total > 0 else { return 0 }
        return min(1, Double(progress) / Double(total))
    }
}

public enum SpoilerVisibility: Hashable, Sendable {
    case visible
    /// Hidden; `revealAt` is the progress at which it would unlock, if known.
    case hidden(reason: String, revealAt: Int?)

    public var isVisible: Bool { if case .visible = self { return true } else { return false } }
}

/// Progress-aware spoiler decisions. Pure functions so every surface (descriptions, tags,
/// characters, episodes, relations, recommendations, shared notes) behaves identically.
public enum SpoilerShield {
    static func isOpen(_ ctx: SpoilerContext, _ policy: SpoilerPolicy) -> Bool {
        !policy.isEnabled || ctx.hasFinished || policy.unlockedMediaIds.contains(ctx.mediaId)
    }

    // MARK: Descriptions

    public static func segments(_ raw: String?, context: SpoilerContext, policy: SpoilerPolicy) -> [(segment: TextSegment, visibility: SpoilerVisibility)] {
        let open = isOpen(context, policy)
        return RichText.segments(from: raw).map { seg in
            if seg.isSpoiler && !open {
                return (seg, .hidden(reason: "Marked as a spoiler", revealAt: context.total))
            }
            return (seg, .visible)
        }
    }

    // MARK: Tags

    public static func tags(_ tags: [MediaTag], context: SpoilerContext, policy: SpoilerPolicy) -> (visible: [MediaTag], hiddenCount: Int) {
        let sorted = tags.sorted { ($0.rank ?? 0) > ($1.rank ?? 0) }
        if isOpen(context, policy) { return (sorted, 0) }
        let visible = sorted.filter { !$0.isSpoiler }
        return (visible, sorted.count - visible.count)
    }

    // MARK: Episodes

    /// Episode titles/thumbnails beyond the next one to watch can spoil (e.g. "X's Death").
    public static func episode(_ number: Int, context: SpoilerContext, policy: SpoilerPolicy) -> SpoilerVisibility {
        if isOpen(context, policy) || policy.level == .relaxed { return .visible }
        if number <= context.progress + 1 { return .visible }
        return .hidden(reason: "Beyond your progress", revealAt: number - 1)
    }

    // MARK: Characters

    public static func character(role: CharacterRole?, description: String?, index: Int, context: SpoilerContext, policy: SpoilerPolicy) -> (showCard: SpoilerVisibility, showDescription: SpoilerVisibility) {
        if isOpen(context, policy) { return (.visible, .visible) }
        let hasMarkedSpoiler = description?.contains("~!") == true || description?.contains("markdown_spoiler") == true
        let descriptionVisibility: SpoilerVisibility = hasMarkedSpoiler && policy.level != .relaxed
            ? .hidden(reason: "Contains story details", revealAt: context.total)
            : .visible

        // Background characters often only appear late; reveal them gradually with progress.
        if policy.level != .relaxed, role == .background || (role == .supporting && index > 8) {
            let threshold = policy.level == .strict ? 0.5 : 0.25
            if context.fraction < threshold {
                let revealAt = context.total.map { Int((Double($0) * threshold).rounded(.up)) }
                return (.hidden(reason: "Appears later", revealAt: revealAt), .hidden(reason: "Appears later", revealAt: revealAt))
            }
        }
        return (.visible, descriptionVisibility)
    }

    // MARK: Relations

    /// Sequels to a show you haven't finished: their synopsis and art can reveal outcomes.
    public static func relation(_ type: MediaRelationType?, base: SpoilerContext, policy: SpoilerPolicy) -> SpoilerVisibility {
        guard policy.isEnabled, !isOpen(base, policy) else { return .visible }
        switch type {
        case .sequel?:
            return policy.level == .relaxed ? .visible : .hidden(reason: "Sequel — finish this first", revealAt: base.total)
        case .sideStory?, .spinOff?, .summary?:
            return policy.level == .strict ? .hidden(reason: "Set later in the story", revealAt: base.total) : .visible
        default:
            return .visible
        }
    }

    // MARK: Recommendations

    /// Hide recommendations that are later entries of something the viewer hasn't finished.
    /// Uses title heuristics because recommendation cards don't include relations.
    public static func isSafeRecommendation(_ media: Media, library: Library, policy: SpoilerPolicy) -> Bool {
        guard policy.isEnabled else { return true }
        let ordinal = FranchiseNaming.seasonOrdinal(of: media)
        guard ordinal > 1 else { return true }
        let root = FranchiseNaming.rootTitle(media)
        let started = library.all.contains { entry in
            FranchiseNaming.rootTitle(entry.media) == root
        }
        // A "Season 3" is only a safe suggestion if you've already touched the franchise.
        return started
    }

    // MARK: Shared notes (clubs, shared lists)

    public static func sharedNote(_ note: SharedNote, readerProgress: Int, readerFinished: Bool, policy: SpoilerPolicy) -> SpoilerVisibility {
        guard policy.isEnabled, !readerFinished else { return .visible }
        if note.atProgress <= readerProgress { return .visible }
        return .hidden(reason: "Written at \(note.unitLabel) \(note.atProgress)", revealAt: note.atProgress)
    }
}

/// A note written at a specific point in a title.
public struct SharedNote: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var author: String
    public var mediaId: Int
    public var atProgress: Int
    public var unitLabel: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), author: String, mediaId: Int, atProgress: Int, unitLabel: String = "episode", text: String, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.mediaId = mediaId
        self.atProgress = atProgress
        self.unitLabel = unitLabel
        self.text = text
        self.createdAt = createdAt
    }
}

/// Heuristics over titles, for when relation data isn't loaded.
public enum FranchiseNaming {
    /// "Attack on Titan Season 3 Part 2" → 3; "Mob Psycho 100 II" → 2; plain titles → 1.
    public static func seasonOrdinal(of media: Media) -> Int {
        let titles = [media.title?.english, media.title?.romaji].compactMap { $0 }
        var best = 1
        for t in titles {
            let lower = t.lowercased()
            if let n = firstMatch(#"season\s+(\d+)"#, in: lower) { best = max(best, n) }
            if let n = firstMatch(#"(\d+)(?:st|nd|rd|th)\s+season"#, in: lower) { best = max(best, n) }
            if lower.contains("final season") { best = max(best, 4) }
            if let range = lower.range(of: #"\s(ii|iii|iv|v)$"#, options: .regularExpression) {
                let roman = lower[range].trimmingCharacters(in: .whitespaces)
                let map = ["ii": 2, "iii": 3, "iv": 4, "v": 5]
                best = max(best, map[roman] ?? 1)
            }
        }
        return best
    }

    /// Lowercased stem used to group franchise entries ("jujutsu kaisen").
    public static func rootTitle(_ media: Media) -> String {
        let base = (media.title?.romaji ?? media.title?.english ?? "").lowercased()
        var s = base
        for sep in [":", " season", " part", " 2nd", " 3rd", " the movie", " movie", " final", " -", " ("] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        s = s.replacingOccurrences(of: #"\s+(ii|iii|iv|v|\d+)$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }
}
