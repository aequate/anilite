import Foundation

public enum Mood: String, Codable, CaseIterable, Sendable, Identifiable {
    case uplifting, cozy, intense, dark, funny, heartbreaking, mindBending, romantic, epic, chill

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .uplifting: return "Uplifting"
        case .cozy: return "Cozy"
        case .intense: return "Intense"
        case .dark: return "Dark"
        case .funny: return "Funny"
        case .heartbreaking: return "Tearjerker"
        case .mindBending: return "Mind-bending"
        case .romantic: return "Romantic"
        case .epic: return "Epic"
        case .chill: return "Chill"
        }
    }

    /// SF Symbol name used across the app.
    public var symbol: String {
        switch self {
        case .uplifting: return "sun.max.fill"
        case .cozy: return "cup.and.saucer.fill"
        case .intense: return "flame.fill"
        case .dark: return "moon.stars.fill"
        case .funny: return "face.smiling.inverse"
        case .heartbreaking: return "drop.fill"
        case .mindBending: return "brain.head.profile"
        case .romantic: return "heart.fill"
        case .epic: return "mountain.2.fill"
        case .chill: return "leaf.fill"
        }
    }

    public var blurb: String {
        switch self {
        case .uplifting: return "Leaves you lighter than you started."
        case .cozy: return "Warm, gentle, low stakes."
        case .intense: return "Edge-of-your-seat momentum."
        case .dark: return "Heavy themes, morally grey."
        case .funny: return "Here for the laughs."
        case .heartbreaking: return "Bring tissues."
        case .mindBending: return "Twists, puzzles, big ideas."
        case .romantic: return "Feelings front and centre."
        case .epic: return "Huge worlds, huge stakes."
        case .chill: return "Easy to put on and unwind."
        }
    }

    /// Genre and tag signals for this mood. Tag names match AniList's MediaTagCollection.
    public var signals: (genres: [String: Double], tags: [String: Double]) {
        switch self {
        case .uplifting:
            return (["Comedy": 0.6, "Sports": 0.6, "Slice of Life": 0.5, "Music": 0.5, "Adventure": 0.4],
                    ["Coming of Age": 0.8, "Found Family": 0.8, "Iyashikei": 0.5, "Band": 0.4, "Travel": 0.4])
        case .cozy:
            return (["Slice of Life": 1.0, "Comedy": 0.4],
                    ["Iyashikei": 1.0, "Cute Girls Doing Cute Things": 0.6, "Food": 0.6, "Rural": 0.5, "Camping": 0.6, "Family Life": 0.5, "Episodic": 0.5])
        case .intense:
            return (["Action": 0.9, "Thriller": 0.9, "Sports": 0.4],
                    ["Survival": 0.8, "Death Game": 0.9, "War": 0.6, "Battle Royale": 0.8, "Super Power": 0.4, "Martial Arts": 0.4])
        case .dark:
            return (["Psychological": 0.8, "Horror": 0.9, "Thriller": 0.5, "Drama": 0.3],
                    ["Tragedy": 0.9, "Gore": 0.6, "Dystopian": 0.7, "Revenge": 0.6, "Anti-Hero": 0.5, "Body Horror": 0.6, "Cosmic Horror": 0.6])
        case .funny:
            return (["Comedy": 1.0],
                    ["Parody": 0.8, "Slapstick": 0.8, "Surreal Comedy": 0.8, "Satire": 0.6, "Manzai": 0.6])
        case .heartbreaking:
            return (["Drama": 1.0, "Romance": 0.3],
                    ["Tragedy": 1.0, "Disability": 0.4, "Coming of Age": 0.4, "Afterlife": 0.5, "Unrequited Love": 0.5])
        case .mindBending:
            return (["Mystery": 0.9, "Psychological": 0.9, "Sci-Fi": 0.6],
                    ["Time Loop": 1.0, "Time Manipulation": 0.8, "Conspiracy": 0.7, "Philosophy": 0.7, "Achronological Order": 0.8, "Memory Manipulation": 0.6, "Detective": 0.5])
        case .romantic:
            return (["Romance": 1.0, "Drama": 0.2],
                    ["Love Triangle": 0.5, "Fake Relationship": 0.5, "Heterosexual": 0.3, "Marriage": 0.4, "Yuri": 0.4, "Boys' Love": 0.4])
        case .epic:
            return (["Adventure": 0.9, "Fantasy": 0.8, "Action": 0.5, "Sci-Fi": 0.4],
                    ["War": 0.6, "Space Opera": 0.8, "Mythology": 0.6, "Politics": 0.5, "Ensemble Cast": 0.5, "Lost Civilization": 0.5, "Kingdom Management": 0.4])
        case .chill:
            return (["Slice of Life": 0.8, "Comedy": 0.4],
                    ["Episodic": 0.8, "Iyashikei": 0.7, "Outdoor Activities": 0.5, "Food": 0.4, "School Club": 0.4])
        }
    }
}

/// A title's "vibe print": continuous emotional dimensions estimated from genres and tags.
public struct VibeProfile: Codable, Hashable, Sendable {
    public var intensity: Double
    public var darkness: Double
    public var humor: Double
    public var warmth: Double
    public var complexity: Double
    public var romance: Double
    /// 0 = slow and episodic, 1 = fast and serialized.
    public var pace: Double

    public static let neutral = VibeProfile(intensity: 0.4, darkness: 0.3, humor: 0.3, warmth: 0.4, complexity: 0.4, romance: 0.2, pace: 0.5)

    public var dimensions: [(label: String, value: Double)] {
        [("Intensity", intensity), ("Darkness", darkness), ("Humor", humor), ("Warmth", warmth), ("Complexity", complexity), ("Romance", romance), ("Pace", pace)]
    }

    public init(intensity: Double, darkness: Double, humor: Double, warmth: Double, complexity: Double, romance: Double, pace: Double) {
        self.intensity = intensity
        self.darkness = darkness
        self.humor = humor
        self.warmth = warmth
        self.complexity = complexity
        self.romance = romance
        self.pace = pace
    }

    public static func of(_ media: Media) -> VibeProfile {
        let genres = Set(media.genres ?? [])
        var tagWeight: [String: Double] = [:]
        for tag in media.tags ?? [] where !(tag.isSpoiler && (tag.rank ?? 0) < 60) {
            tagWeight[tag.name] = Double(tag.rank ?? 50) / 100
        }
        func g(_ name: String) -> Double { genres.contains(name) ? 1 : 0 }
        func t(_ names: String...) -> Double { names.map { tagWeight[$0] ?? 0 }.max() ?? 0 }

        var p = VibeProfile.neutral
        p.intensity = clamp(0.15 + 0.35 * g("Action") + 0.3 * g("Thriller") + 0.15 * g("Sports") + 0.2 * g("Horror") + 0.3 * t("Survival", "Death Game", "War", "Battle Royale"))
        p.darkness = clamp(0.1 + 0.3 * g("Horror") + 0.25 * g("Psychological") + 0.15 * g("Thriller") + 0.35 * t("Tragedy", "Gore", "Dystopian", "Body Horror", "Torture") - 0.15 * g("Comedy"))
        p.humor = clamp(0.1 + 0.55 * g("Comedy") + 0.3 * t("Parody", "Slapstick", "Surreal Comedy", "Satire") - 0.1 * g("Horror"))
        p.warmth = clamp(0.2 + 0.3 * g("Slice of Life") + 0.35 * t("Iyashikei", "Found Family", "Family Life", "Cute Girls Doing Cute Things") + 0.1 * g("Comedy") - 0.2 * g("Horror"))
        p.complexity = clamp(0.2 + 0.3 * g("Mystery") + 0.25 * g("Psychological") + 0.15 * g("Sci-Fi") + 0.3 * t("Time Loop", "Conspiracy", "Philosophy", "Politics", "Achronological Order", "Time Manipulation"))
        p.romance = clamp(0.05 + 0.65 * g("Romance") + 0.3 * t("Love Triangle", "Heterosexual", "Yuri", "Boys' Love", "Marriage"))
        let episodic = t("Episodic", "Iyashikei")
        p.pace = clamp(0.45 + 0.25 * g("Action") + 0.15 * g("Thriller") - 0.35 * episodic - 0.15 * g("Slice of Life"))
        return p
    }

    public func moodScore(_ mood: Mood) -> Double {
        switch mood {
        case .uplifting: return clamp(0.5 * warmth + 0.3 * humor + 0.3 * (1 - darkness) - 0.1)
        case .cozy: return clamp(0.7 * warmth + 0.3 * (1 - intensity) + 0.2 * (1 - darkness) - 0.2)
        case .intense: return clamp(0.8 * intensity + 0.3 * pace - 0.1)
        case .dark: return clamp(0.9 * darkness + 0.1 * complexity)
        case .funny: return clamp(1.0 * humor)
        case .heartbreaking: return clamp(0.6 * darkness + 0.3 * romance + 0.2 * warmth - 0.2 * humor)
        case .mindBending: return clamp(0.9 * complexity + 0.1 * darkness)
        case .romantic: return clamp(1.0 * romance)
        case .epic: return clamp(0.5 * intensity + 0.4 * complexity + 0.2 * pace - 0.1)
        case .chill: return clamp(0.5 * (1 - intensity) + 0.4 * (1 - pace) + 0.2 * warmth - 0.1)
        }
    }

    public func distance(to other: VibeProfile) -> Double {
        let a = dimensions.map(\.value), b = other.dimensions.map(\.value)
        return sqrt(zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) })
    }
}

func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
