import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        #if canImport(Darwin)
        config.waitsForConnectivity = false
        #endif
        config.httpMaximumConnectionsPerHost = 4
        // Responses are cached by ResponseCache with explicit TTLs, not URLCache.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
        #else
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
        #endif
    }
}

public enum AniListError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case rateLimited(retryAfter: TimeInterval)
    case unauthorized
    case privateUser
    case notFound
    case server(status: Int, message: String)
    case graphQL([String])
    case decoding(String)
    case missingData
    case authRequired

    public var errorDescription: String? {
        switch self {
        case .offline: return "You're offline. Showing what's saved on this device."
        case .rateLimited(let wait): return "AniList is busy. Trying again in \(Int(wait.rounded(.up)))s."
        case .unauthorized: return "Your AniList session expired. Please sign in again."
        case .privateUser: return "This AniList profile is private."
        case .notFound: return "Couldn't find that on AniList."
        case .server(let status, let message): return "AniList error \(status): \(message)"
        case .graphQL(let messages): return messages.joined(separator: "\n")
        case .decoding: return "AniList sent something unexpected. Try again later."
        case .missingData: return "AniList returned no data."
        case .authRequired: return "Connect your AniList account to do this."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited: return true
        case .server(let status, _): return status >= 500
        default: return false
        }
    }

    static func from(urlError: URLError) -> AniListError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost, .timedOut, .internationalRoamingOff:
            return .offline
        default:
            return .server(status: urlError.errorCode, message: urlError.localizedDescription)
        }
    }
}
