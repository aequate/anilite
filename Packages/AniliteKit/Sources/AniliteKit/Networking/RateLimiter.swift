import Foundation

public struct AppClock: Sendable {
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let live = AppClock(
        now: { Date() },
        sleep: { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    )
}

/// Sliding-window limiter that adapts to AniList's advertised limit.
/// AniList allows 90 req/min normally and 30 when degraded; we stay a little under.
public actor RateLimiter {
    private var limit: Int
    private let window: TimeInterval
    private var sent: [Date] = []
    private var blockedUntil: Date?
    private let clock: AppClock

    public init(limit: Int = 28, window: TimeInterval = 60, clock: AppClock = .live) {
        self.limit = max(1, limit)
        self.window = window
        self.clock = clock
    }

    public var currentLimit: Int { limit }

    /// Waits until a request slot is free, then records it.
    public func acquire() async throws {
        while true {
            let now = clock.now()
            if let blockedUntil, blockedUntil > now {
                try await clock.sleep(blockedUntil.timeIntervalSince(now))
                continue
            }
            sent.removeAll { now.timeIntervalSince($0) >= window }
            if sent.count < limit {
                sent.append(now)
                return
            }
            let oldest = sent.min() ?? now
            let wait = max(0.05, window - now.timeIntervalSince(oldest))
            try await clock.sleep(wait)
        }
    }

    /// Feed back the headers of every response.
    public func record(limitHeader: Int?, remaining: Int?) {
        if let limitHeader, limitHeader > 0 {
            // Keep a small safety margin under the server's limit.
            limit = max(1, limitHeader - 2)
        }
        if let remaining, remaining <= 1 {
            blockedUntil = clock.now().addingTimeInterval(window / 4)
        }
    }

    public func backOff(for seconds: TimeInterval) {
        let until = clock.now().addingTimeInterval(max(1, seconds))
        if let blockedUntil, blockedUntil > until { return }
        blockedUntil = until
    }

    public var pendingCount: Int { sent.count }
}
