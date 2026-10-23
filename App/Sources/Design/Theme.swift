import SwiftUI
import AniliteKit

/// Design tokens. Anilite is a dark, artwork-led app: chrome stays neutral ink so each
/// title's own palette can carry the colour.
enum Theme {
    // Ink scale (background → raised surfaces).
    static let ink0 = Color(hex: 0x07070C)
    static let ink1 = Color(hex: 0x0E0E16)
    static let ink2 = Color(hex: 0x161622)
    static let ink3 = Color(hex: 0x22222F)
    static let hairline = Color.white.opacity(0.09)

    // Text.
    static let textPrimary = Color(hex: 0xF4F2F8)
    static let textSecondary = Color(hex: 0xB4B1C2)
    static let textTertiary = Color(hex: 0x7C798C)

    // Brand: a warm sakura vermilion with a cold cyan counterpoint.
    static let brand = Color(hex: 0xFF5A78)
    static let brandCool = Color(hex: 0x6FE3FF)

    // Semantic.
    static let positive = Color(hex: 0x5BE49B)
    static let caution = Color(hex: 0xFFC65C)
    static let negative = Color(hex: 0xFF6B6B)

    static let corner: CGFloat = 22
    static let cornerSmall: CGFloat = 14
    static let gutter: CGFloat = 20

    static let defaultPalette = ArtworkPalette(
        accent: RGB(r: 1.0, g: 0.353, b: 0.47),
        deep: RGB(r: 0.03, g: 0.03, b: 0.06),
        glow: RGB(r: 0.44, g: 0.89, b: 1.0),
        secondary: RGB(r: 0.55, g: 0.42, b: 0.95)
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(_ rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    /// AniList cover colours arrive as "#rrggbb".
    init?(anilistHex: String?) {
        guard let rgb = RGB(hex: anilistHex) else { return nil }
        self.init(rgb)
    }
}

extension ArtworkPalette {
    var accentColor: Color { Color(accent) }
    var deepColor: Color { Color(deep) }
    var glowColor: Color { Color(glow) }
    var secondaryColor: Color { Color(secondary) }
}

// MARK: - Typography

enum Typo {
    /// Expanded-width display face for screen titles.
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.expanded)
    }

    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .heavy).width(.expanded)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .bold).width(.expanded)
    static let cardTitle = Font.system(.subheadline, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let caption = Font.system(.caption, design: .default, weight: .medium)
    static let micro = Font.system(.caption2, design: .default, weight: .semibold)
    static let metric = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let bigMetric = Font.system(size: 44, weight: .black, design: .rounded).monospacedDigit()
}

/// Uppercase tracked label used above sections and inside chips.
struct Eyebrow: View {
    var text: String
    var color: Color = Theme.textTertiary

    var body: some View {
        Text(text.uppercased())
            .font(Typo.micro)
            .tracking(1.4)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small math helper kept out of AniliteKit's internal API.
func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
