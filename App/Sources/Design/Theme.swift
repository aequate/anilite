import SwiftUI
import AniliteKit

/// Design tokens.
///
/// Direction: a painted backdrop under an inked foreground. The ground is warm sumi ink,
/// text and primary actions are washi paper, and colour comes from two places only: the
/// artwork of the title on screen and the marbled-ink backdrop (suminagashi) beneath it.
/// Chrome stays solid and quiet. Glass is reserved for the few controls that really float
/// over moving content (the dock and over-artwork buttons).
enum Theme {
    // Sumi ground and solid surfaces, warm rather than blue-black.
    static let ink0 = Color(hex: 0x11100F)
    static let ink1 = Color(hex: 0x1A1917)
    static let ink2 = Color(hex: 0x23211E)
    static let ink3 = Color(hex: 0x2F2C28)
    static let hairline = Color(hex: 0xEFEAE0, opacity: 0.10)
    static let rule = Color(hex: 0xEFEAE0, opacity: 0.16)

    // Washi text. Tertiary still clears 4.5:1 on ink0.
    static let textPrimary = Color(hex: 0xEFEAE0)
    static let textSecondary = Color(hex: 0xB5AEA2)
    static let textTertiary = Color(hex: 0x958E83)

    /// Yamabuki: the highlighter colour for selection, progress and links. Used sparingly.
    static let accent = Color(hex: 0xE4B44C)
    /// Asagi: anything live or airing, and secondary information.
    static let accentCool = Color(hex: 0x4FAFBC)

    // Semantic.
    static let positive = Color(hex: 0x8DBF7E)
    static let caution = Color(hex: 0xE39A55)
    static let negative = Color(hex: 0xD8664F)
    /// Shu-niku seal red, only for achievement stamps.
    static let seal = Color(hex: 0xC6473A)

    /// Radius scale by role: covers are printed objects (tight), cards are panels.
    static let corner: CGFloat = 14
    static let cornerSmall: CGFloat = 9
    static let cornerCover: CGFloat = 5
    static let gutter: CGFloat = 20

    /// Marbling pigments for screens without a single title: ai indigo, asagi teal and
    /// kincha ochre floating on sumi.
    static let defaultPalette = ArtworkPalette(
        accent: RGB(r: 0.20, g: 0.36, b: 0.56),
        deep: RGB(r: 0.067, g: 0.063, b: 0.059),
        glow: RGB(r: 0.17, g: 0.50, b: 0.54),
        secondary: RGB(r: 0.58, g: 0.45, b: 0.22)
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

/// Two voices, as in a printed volume: a serif (New York, standing in for Mincho) for
/// titles, and the system sans for everything you read or tap.
enum Typo {
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    static let screenTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .serif, weight: .semibold)
    static let cardTitle = Font.system(.subheadline, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let caption = Font.system(.caption, design: .default, weight: .medium)
    static let micro = Font.system(.caption2, design: .default, weight: .semibold)
    static let metric = Font.system(.title2, design: .default, weight: .semibold).monospacedDigit()
    static let bigMetric = Font.system(size: 46, weight: .bold, design: .serif).monospacedDigit()
}

/// Quiet label above a section or a value. Sentence case, no tracking: it names the
/// content and gets out of the way.
struct Eyebrow: View {
    var text: String
    var color: Color = Theme.textTertiary

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Motion

/// Motion tokens. Everything settles without overshoot; nothing bounces.
enum Motion {
    /// Presses and toggles.
    static let quick = Animation.easeOut(duration: 0.16)
    /// Selection changes, small layout moves.
    static let standard = Animation.smooth(duration: 0.34)
    /// Panels, progress, cards entering.
    static let gentle = Animation.smooth(duration: 0.55)
    /// Large reveals and camera moves.
    static let reveal = Animation.smooth(duration: 0.85)
}

/// Small math helper kept out of AniliteKit's internal API.
func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
