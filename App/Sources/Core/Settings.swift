import Foundation
import Network
import Observation
import AniliteKit

/// How the library is backed.
enum AccountMode: Codable, Equatable, Sendable {
    /// Onboarding hasn't finished.
    case undecided
    /// Library lives only on this device.
    case local
    /// Read-only view of a public AniList profile.
    case publicProfile(name: String)
    /// Signed in with AniList; edits sync both ways.
    case connected(userId: Int, name: String)

    var displayName: String? {
        switch self {
        case .publicProfile(let name), .connected(_, let name): return name
        default: return nil
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .undecided: return "Not set up"
        case .local: return "On this device"
        case .publicProfile(let name): return "Following \(name)'s public AniList (read-only)"
        case .connected(_, let name): return "Synced with AniList as \(name)"
        }
    }
}

enum EffectsPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case cinematic, balanced, minimal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .cinematic: return "Full-rate shaders, particles and parallax."
        case .balanced: return "Gentler frame rate and fewer particles."
        case .minimal: return "Still, artwork-tinted backgrounds."
        }
    }
}

/// User preferences, persisted as JSON. Decoding tolerates missing keys so new settings
/// never wipe old ones.
struct AppSettings: Codable, Equatable, Sendable {
    var titleLanguage: TitleLanguage = .english
    var spoilerLevel: SpoilerLevel = .balanced
    /// ISO region for "where to watch"; nil means use the device region.
    var regionOverride: String?
    var weeklyBudget: WeeklyBudget = .standard
    var planStrategy: PlanStrategy = .sequential
    var haptics = true
    var effects: EffectsPreference = .cinematic
    var airingReminders = false
    var reminderLeadMinutes = 0
    var tonightMinutes = 90
    var hasOnboarded = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        titleLanguage = (try? c.decodeIfPresent(TitleLanguage.self, forKey: .titleLanguage)) ?? d.titleLanguage
        spoilerLevel = (try? c.decodeIfPresent(SpoilerLevel.self, forKey: .spoilerLevel)) ?? d.spoilerLevel
        regionOverride = (try? c.decodeIfPresent(String.self, forKey: .regionOverride)) ?? nil
        weeklyBudget = (try? c.decodeIfPresent(WeeklyBudget.self, forKey: .weeklyBudget)) ?? d.weeklyBudget
        planStrategy = (try? c.decodeIfPresent(PlanStrategy.self, forKey: .planStrategy)) ?? d.planStrategy
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
        effects = (try? c.decodeIfPresent(EffectsPreference.self, forKey: .effects)) ?? d.effects
        airingReminders = (try? c.decodeIfPresent(Bool.self, forKey: .airingReminders)) ?? d.airingReminders
        reminderLeadMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)) ?? d.reminderLeadMinutes
        tonightMinutes = (try? c.decodeIfPresent(Int.self, forKey: .tonightMinutes)) ?? d.tonightMinutes
        hasOnboarded = (try? c.decodeIfPresent(Bool.self, forKey: .hasOnboarded)) ?? d.hasOnboarded
    }

    var region: String? { regionOverride ?? StreamingResolver.currentRegion }
}

/// Tracks connectivity so the mutation queue flushes the moment the device is back online.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private(set) var isConstrained = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    func start(onReconnect: @escaping @MainActor () -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained
            Task { @MainActor in
                guard let self else { return }
                let cameBack = online && !self.isOnline
                self.isOnline = online
                self.isConstrained = constrained
                if cameBack { onReconnect() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.anilite.network", qos: .utility))
    }
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
