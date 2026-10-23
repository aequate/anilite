import Foundation
import Security
import AuthenticationServices
import UIKit
import AniliteKit

/// Minimal Keychain wrapper for the AniList access token.
enum Keychain {
    private static let service = "app.anilite.ios"

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case cancelled
    case denied(String)
    case invalidCallback
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This build has no AniList client ID, so account sign-in is off. You can still follow a public AniList profile or keep a local library."
        case .cancelled: return nil
        case .denied(let reason): return "AniList didn't grant access (\(reason))."
        case .invalidCallback: return "AniList sent back an unexpected response. Please try again."
        case .couldNotStart: return "Couldn't open the AniList sign-in page."
        }
    }
}

/// AniList OAuth using the implicit grant, as AniList recommends for mobile apps: the token
/// comes back in the redirect fragment (`anilite://auth-callback#access_token=…`), so no
/// client secret ships in the app.
@MainActor
final class AuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let tokenAccount = "anilist-token"
    private var session: ASWebAuthenticationSession?

    /// The client ID registered at anilist.co/settings/developer, injected at build time.
    static var clientID: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AniListClientID") as? String
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    static var isConfigured: Bool { clientID != nil }

    func authorize() async throws -> String {
        guard let clientID = Self.clientID else { throw AuthError.notConfigured }
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        guard let url = components.url else { throw AuthError.couldNotStart }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let completion: ASWebAuthenticationSession.CompletionHandler = { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL, case .auth(let token, _, let failure)? = DeepLink.parse(callbackURL) else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }
                if let token, !token.isEmpty {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AuthError.denied(failure ?? "no token"))
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(ShareCodec.scheme), completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: ShareCodec.scheme, completionHandler: completion)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.couldNotStart)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }
}
