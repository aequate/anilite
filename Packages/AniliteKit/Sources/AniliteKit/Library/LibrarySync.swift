import Foundation

/// A change to one AniList list entry. Nil fields are left untouched on the server.
public struct EntryChange: Codable, Hashable, Sendable {
    public var mediaId: Int
    public var status: MediaListStatus?
    public var progress: Int?
    public var progressVolumes: Int?
    /// 0–100.
    public var score: Double?
    public var notes: String?
    public var repeatCount: Int?
    public var startedAt: FuzzyDate?
    public var completedAt: FuzzyDate?

    public init(mediaId: Int, status: MediaListStatus? = nil, progress: Int? = nil, progressVolumes: Int? = nil, score: Double? = nil,
                notes: String? = nil, repeatCount: Int? = nil, startedAt: FuzzyDate? = nil, completedAt: FuzzyDate? = nil) {
        self.mediaId = mediaId
        self.status = status
        self.progress = progress
        self.progressVolumes = progressVolumes
        self.score = score
        self.notes = notes
        self.repeatCount = repeatCount
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Later changes win field by field.
    public func merged(with later: EntryChange) -> EntryChange {
        var c = self
        c.status = later.status ?? status
        c.progress = later.progress ?? progress
        c.progressVolumes = later.progressVolumes ?? progressVolumes
        c.score = later.score ?? score
        c.notes = later.notes ?? notes
        c.repeatCount = later.repeatCount ?? repeatCount
        c.startedAt = later.startedAt ?? startedAt
        c.completedAt = later.completedAt ?? completedAt
        return c
    }
}

public enum PendingMutation: Codable, Hashable, Sendable {
    case save(EntryChange)
    case delete(mediaId: Int, remoteId: Int)

    public var mediaId: Int {
        switch self {
        case .save(let c): return c.mediaId
        case .delete(let id, _): return id
        }
    }
}

/// Mutations made offline (or while rate limited), replayed in order once AniList is reachable.
public struct MutationQueue: Codable, Hashable, Sendable {
    public private(set) var items: [PendingMutation] = []

    public init(items: [PendingMutation] = []) { self.items = items }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// Coalesces with any queued save for the same title so we send one request per title.
    public mutating func enqueue(_ mutation: PendingMutation) {
        switch mutation {
        case .save(let change):
            if let index = items.lastIndex(where: { $0.mediaId == change.mediaId }), case .save(let existing) = items[index] {
                items[index] = .save(existing.merged(with: change))
            } else {
                items.append(mutation)
            }
        case .delete(let mediaId, _):
            items.removeAll { $0.mediaId == mediaId }
            items.append(mutation)
        }
    }

    /// Queued saves for an entry that hasn't reached AniList yet can be dropped entirely.
    public mutating func cancelLocalOnly(mediaId: Int) {
        items.removeAll { $0.mediaId == mediaId }
    }

    public var first: PendingMutation? { items.first }

    public mutating func removeFirst() {
        if !items.isEmpty { items.removeFirst() }
    }
}

/// Applies changes to a local library — the same logic for optimistic UI updates and
/// re-applying queued changes over a fresh server snapshot.
public enum LibraryReducer {
    public static func apply(_ change: EntryChange, media: Media?, to library: inout Library, now: Date = Date(), calendar: Calendar = .current) {
        var entry: LibraryEntry
        if let existing = library.entries[change.mediaId] {
            entry = existing
        } else if let media {
            // Start as planning so the status transition below stamps start/finish dates.
            entry = LibraryEntry(media: media, status: .planning, updatedAt: now)
        } else {
            return
        }
        let today = FuzzyDate(date: now, calendar: calendar)
        if let status = change.status {
            if status == .current && entry.status != .current && entry.startedAt == nil { entry.startedAt = change.startedAt ?? today }
            if status == .completed && entry.status != .completed {
                if entry.completedAt == nil { entry.completedAt = change.completedAt ?? today }
                if let total = entry.media.totalUnits, total > 0 { entry.progress = total }
            }
            entry.status = status
        }
        if let progress = change.progress { entry.progress = max(0, progress) }
        if let volumes = change.progressVolumes { entry.progressVolumes = max(0, volumes) }
        if let score = change.score { entry.score = min(100, max(0, score)) }
        if let notes = change.notes { entry.notes = notes }
        if let rc = change.repeatCount { entry.repeatCount = max(0, rc) }
        if let s = change.startedAt { entry.startedAt = s }
        if let c = change.completedAt { entry.completedAt = c }
        entry.updatedAt = now
        library.entries[change.mediaId] = entry
    }

    public static func remove(mediaId: Int, from library: inout Library) {
        library.entries[mediaId] = nil
    }

    /// The server snapshot plus every change still waiting in the queue.
    public static func rebase(server: Library, pending: MutationQueue, now: Date = Date()) -> Library {
        var library = server
        for mutation in pending.items {
            switch mutation {
            case .save(let change):
                apply(change, media: server.entries[change.mediaId]?.media, to: &library, now: now)
            case .delete(let mediaId, _):
                remove(mediaId: mediaId, from: &library)
            }
        }
        return library
    }

    /// The change produced by "+1 episode/chapter", including auto-completion and auto-start.
    public static func increment(_ entry: LibraryEntry, by amount: Int = 1) -> EntryChange {
        let next = max(0, entry.progress + amount)
        var change = EntryChange(mediaId: entry.mediaId, progress: next)
        if let total = entry.media.totalUnits, total > 0, next >= total, entry.media.status == .finished {
            change.progress = total
            change.status = .completed
            if entry.status == .repeating { change.repeatCount = entry.repeatCount + 1 }
        } else if entry.status == .planning || entry.status == .paused || entry.status == .dropped {
            change.status = .current
        }
        return change
    }
}

public extension ScoreFormat {
    /// Converts a 0–100 score into the user's AniList display format.
    func display(_ score: Double) -> String {
        guard score > 0 else { return "–" }
        switch self {
        case .point100: return String(Int(score.rounded()))
        case .point10Decimal: return String(format: "%.1f", score / 10)
        case .point10: return String(Int((score / 10).rounded()))
        case .point5: return String(repeating: "★", count: max(1, Int((score / 20).rounded())))
        case .point3:
            switch score {
            case ..<40: return "🙁"
            case ..<70: return "😐"
            default: return "🙂"
            }
        }
    }

    /// Step the score slider snaps to, in 0–100 units.
    var step: Double {
        switch self {
        case .point100: return 1
        case .point10Decimal: return 1
        case .point10: return 10
        case .point5: return 20
        case .point3: return 35
        }
    }
}
