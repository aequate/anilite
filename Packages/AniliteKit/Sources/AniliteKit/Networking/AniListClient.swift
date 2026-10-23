import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CachePolicy: Sendable {
    /// Fresh cache wins; otherwise network, falling back to stale cache on failure.
    case cacheFirst
    /// Always try the network; fall back to any cache on failure.
    case networkFirst
    /// Network only (mutations, pull-to-refresh of personal data).
    case networkOnly
    /// Never touch the network.
    case cacheOnly
}

public struct Fetched<T: Sendable>: Sendable {
    public enum Source: Sendable, Equatable { case cache(stale: Bool), network }
    public let value: T
    public let source: Source
    public let fetchedAt: Date

    public var isStale: Bool { source == .cache(stale: true) }
}

public actor AniListClient {
    public static let endpoint = URL(string: "https://graphql.anilist.co")!
    public static let userAgent = "Anilite/1.0 (iOS; unofficial AniList client)"

    private let transport: HTTPTransport
    private let cache: ResponseCache
    private let limiter: RateLimiter
    private let clock: AppClock
    private var token: String?
    private var inFlight: [String: Task<Data, Error>] = [:]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public private(set) var lastNetworkFailure: Date?
    public private(set) var requestCount = 0

    public init(transport: HTTPTransport = URLSessionTransport(), cache: ResponseCache, limiter: RateLimiter = RateLimiter(), clock: AppClock = .live) {
        self.transport = transport
        self.cache = cache
        self.limiter = limiter
        self.clock = clock
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    public var hasToken: Bool { token != nil }

    // MARK: - Fetching

    public func fetch<T>(_ op: GraphQLOperation<T>, policy: CachePolicy = .cacheFirst) async throws -> T {
        try await fetchDetailed(op, policy: policy).value
    }

    public func fetchDetailed<T>(_ op: GraphQLOperation<T>, policy: CachePolicy = .cacheFirst) async throws -> Fetched<T> {
        let key = cacheKey(for: op)
        let now = clock.now()
        let cached = op.isMutation ? nil : await cache.entry(for: key)

        switch policy {
        case .cacheOnly:
            guard let cached else { throw AniListError.offline }
            return Fetched(value: try decode(T.self, from: cached.data), source: .cache(stale: cached.age(at: now) > op.ttl), fetchedAt: cached.storedAt)
        case .cacheFirst:
            if let cached, cached.age(at: now) <= op.ttl, let value = try? decode(T.self, from: cached.data) {
                return Fetched(value: value, source: .cache(stale: false), fetchedAt: cached.storedAt)
            }
        case .networkFirst, .networkOnly:
            break
        }

        do {
            let data = try await networkData(for: op, key: key)
            return Fetched(value: try decode(T.self, from: data), source: .network, fetchedAt: clock.now())
        } catch let error as AniListError where error.isRetryable && policy != .networkOnly {
            if let cached, let value = try? decode(T.self, from: cached.data) {
                return Fetched(value: value, source: .cache(stale: true), fetchedAt: cached.storedAt)
            }
            throw error
        }
    }

    /// Stale-while-revalidate: yields cached data immediately (if any), then fresh data.
    /// A network failure after a cached value was delivered ends the stream quietly.
    public nonisolated func stream<T>(_ op: GraphQLOperation<T>) -> AsyncThrowingStream<Fetched<T>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var deliveredCache = false
                if let cached = try? await self.fetchDetailed(op, policy: .cacheOnly) {
                    continuation.yield(cached)
                    deliveredCache = true
                    if !cached.isStale && cached.source == .cache(stale: false) {
                        continuation.finish()
                        return
                    }
                }
                do {
                    let fresh = try await self.fetchDetailed(op, policy: .networkOnly)
                    continuation.yield(fresh)
                    continuation.finish()
                } catch {
                    if deliveredCache { continuation.finish() } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func clearCache() async {
        await cache.removeAll()
    }

    public func invalidate<T>(_ op: GraphQLOperation<T>) async {
        await cache.remove(cacheKey(for: op))
    }

    // MARK: - Internals

    private func cacheKey<T>(for op: GraphQLOperation<T>) -> String {
        op.requiresAuth ? "auth-" + op.cacheKey : op.cacheKey
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope: GraphQLEnvelope<T>
        do {
            envelope = try decoder.decode(GraphQLEnvelope<T>.self, from: data)
        } catch {
            throw AniListError.decoding(String(describing: error))
        }
        guard let value = envelope.data else {
            throw Self.map(errors: envelope.errors ?? [], status: 200)
        }
        return value
    }

    /// Coalesces identical concurrent requests into one network call.
    private func networkData<T>(for op: GraphQLOperation<T>, key: String) async throws -> Data {
        if !op.isMutation, let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task<Data, Error> { try await self.perform(op, key: key) }
        if !op.isMutation { inFlight[key] = task }
        defer { if !op.isMutation { inFlight[key] = nil } }
        return try await task.value
    }

    private func perform<T>(_ op: GraphQLOperation<T>, key: String) async throws -> Data {
        if op.requiresAuth && token == nil { throw AniListError.authRequired }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if op.requiresAuth || op.attachesToken, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(GraphQLRequestBody(query: op.query, variables: op.variables))

        var attempt = 0
        while true {
            attempt += 1
            try await limiter.acquire()
            let data: Data
            let response: HTTPURLResponse
            do {
                requestCount += 1
                (data, response) = try await transport.send(request)
            } catch let error as URLError {
                lastNetworkFailure = clock.now()
                throw AniListError.from(urlError: error)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastNetworkFailure = clock.now()
                throw AniListError.offline
            }

            let limitHeader = (response.value(forHTTPHeaderField: "X-RateLimit-Limit")).flatMap(Int.init)
            let remaining = (response.value(forHTTPHeaderField: "X-RateLimit-Remaining")).flatMap(Int.init)
            await limiter.record(limitHeader: limitHeader, remaining: remaining)

            if response.statusCode == 429 {
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 30
                await limiter.backOff(for: retryAfter)
                if attempt < 3 { continue }
                throw AniListError.rateLimited(retryAfter: retryAfter)
            }

            if (200..<300).contains(response.statusCode) {
                if let probe = try? decoder.decode(GraphQLEnvelope<IgnoredData>.self, from: data),
                   probe.data == nil, let errors = probe.errors, !errors.isEmpty {
                    throw Self.map(errors: errors, status: response.statusCode)
                }
                if !op.isMutation { await cache.store(data, for: key) }
                return data
            }

            let errors = (try? decoder.decode(GraphQLEnvelope<IgnoredData>.self, from: data))?.errors ?? []
            let mapped = Self.map(errors: errors, status: response.statusCode)
            if mapped.isRetryable, attempt < 2, response.statusCode >= 500 {
                try await clock.sleep(1.5)
                continue
            }
            throw mapped
        }
    }

    static func map(errors: [GraphQLErrorItem], status: Int) -> AniListError {
        let messages = errors.map(\.message)
        let joined = messages.joined(separator: " ").lowercased()
        if joined.contains("private user") { return .privateUser }
        if status == 401 || joined.contains("invalid token") || joined.contains("unauthorized") { return .unauthorized }
        if status == 404 || joined.contains("not found") { return .notFound }
        if status == 429 { return .rateLimited(retryAfter: 30) }
        if status >= 500 { return .server(status: status, message: messages.first ?? "Server error") }
        if !messages.isEmpty { return .graphQL(messages) }
        return .server(status: status, message: "Unexpected response")
    }
}

/// Decodes any `data` payload without caring about its shape.
struct IgnoredData: Decodable {
    init(from decoder: Decoder) throws {}
}
