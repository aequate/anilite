import Foundation

/// A colour in linear-ish sRGB components 0…1, independent of UIKit/SwiftUI.
public struct RGB: Hashable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = clamp(r)
        self.g = clamp(g)
        self.b = clamp(b)
    }

    public init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public var hsl: HSL {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return HSL(h: 0, s: 0, l: l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return HSL(h: h, s: s, l: l)
    }

    public func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)
}

public struct HSL: Hashable, Sendable {
    public var h: Double
    public var s: Double
    public var l: Double

    public init(h: Double, s: Double, l: Double) {
        self.h = h - floor(h)
        self.s = clamp(s)
        self.l = clamp(l)
    }

    public var rgb: RGB {
        guard s > 0 else { return RGB(r: l, g: l, b: l) }
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return RGB(r: hue(p, q, h + 1.0 / 3), g: hue(p, q, h), b: hue(p, q, h - 1.0 / 3))
    }
}

/// The colours a title's screen is painted with.
public struct ArtworkPalette: Hashable, Sendable, Codable {
    /// Dominant hue, tuned for use as an accent on dark backgrounds.
    public var accent: RGB
    /// Deep background tone.
    public var deep: RGB
    /// Mid tone for gradients/particles.
    public var glow: RGB
    /// Secondary hue for variety.
    public var secondary: RGB

    public init(accent: RGB, deep: RGB, glow: RGB, secondary: RGB) {
        self.accent = accent
        self.deep = deep
        self.glow = glow
        self.secondary = secondary
    }

    public static let fallback = ArtworkPalette(accent: RGB(r: 0.55, g: 0.48, b: 1), deep: RGB(r: 0.05, g: 0.04, b: 0.12),
                                                glow: RGB(r: 0.35, g: 0.25, b: 0.75), secondary: RGB(r: 0.2, g: 0.65, b: 0.95))

    /// Builds a palette from AniList's cover colour alone (instant, before artwork loads).
    public static func from(hex: String?) -> ArtworkPalette {
        guard let base = RGB(hex: hex) else { return .fallback }
        return derive(primary: base, secondary: nil)
    }

    /// Builds a palette from sampled artwork pixels.
    public static func from(pixels: [RGB], hint: String? = nil) -> ArtworkPalette {
        let swatches = PaletteExtractor.swatches(pixels)
        guard let primary = swatches.first?.color ?? RGB(hex: hint) else { return .fallback }
        let secondary = swatches.dropFirst().first { abs($0.color.hsl.h - primary.hsl.h) > 0.08 }?.color
        return derive(primary: primary, secondary: secondary)
    }

    static func derive(primary: RGB, secondary: RGB?) -> ArtworkPalette {
        var hsl = primary.hsl
        let isGrey = hsl.s < 0.12
        // Accent: readable on near-black; keep greys grey but lift them.
        var accentHSL = HSL(h: hsl.h, s: isGrey ? hsl.s : max(0.55, hsl.s), l: min(0.72, max(0.58, hsl.l)))
        var accent = accentHSL.rgb
        var guardCount = 0
        while accent.contrast(with: RGB(r: 0.04, g: 0.04, b: 0.06)) < 4.5 && guardCount < 10 {
            accentHSL.l = min(0.95, accentHSL.l + 0.04)
            accent = accentHSL.rgb
            guardCount += 1
        }
        hsl.s = isGrey ? hsl.s : min(0.65, max(0.35, hsl.s))
        let deep = HSL(h: hsl.h, s: hsl.s * 0.8, l: 0.07).rgb
        let glow = HSL(h: hsl.h, s: hsl.s, l: 0.32).rgb
        let sec: RGB
        if let secondary {
            let s2 = secondary.hsl
            sec = HSL(h: s2.h, s: max(0.45, s2.s), l: 0.6).rgb
        } else {
            sec = HSL(h: hsl.h + 0.08, s: max(0.45, hsl.s), l: 0.6).rgb
        }
        return ArtworkPalette(accent: accent, deep: deep, glow: glow, secondary: sec)
    }
}

public struct Swatch: Hashable, Sendable {
    public var color: RGB
    public var population: Int
}

public enum PaletteExtractor {
    /// Coarse histogram quantisation (4 bits/channel) weighted towards vivid colours.
    public static func swatches(_ pixels: [RGB], maxCount: Int = 5) -> [Swatch] {
        guard !pixels.isEmpty else { return [] }
        var buckets: [Int: (r: Double, g: Double, b: Double, n: Int)] = [:]
        for p in pixels {
            let key = (Int(p.r * 15) << 8) | (Int(p.g * 15) << 4) | Int(p.b * 15)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.r += p.r; bucket.g += p.g; bucket.b += p.b; bucket.n += 1
            buckets[key] = bucket
        }
        let raw = buckets.values.map { b -> Swatch in
            let n = Double(b.n)
            return Swatch(color: RGB(r: b.r / n, g: b.g / n, b: b.b / n), population: b.n)
        }
        func weight(_ s: Swatch) -> Double {
            let hsl = s.color.hsl
            let vivid = 0.35 + hsl.s
            let midtone = 1 - abs(hsl.l - 0.5) * 1.4
            return Double(s.population) * vivid * max(0.1, midtone)
        }
        var result: [Swatch] = []
        for s in raw.sorted(by: { weight($0) > weight($1) }) {
            // Merge near-duplicates.
            if result.contains(where: { distance($0.color, s.color) < 0.12 }) { continue }
            result.append(s)
            if result.count == maxCount { break }
        }
        return result
    }

    static func distance(_ a: RGB, _ b: RGB) -> Double {
        sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
    }
}

/// The animated backdrop each title gets. Rendered by Metal shaders in the app.
public enum AtmosphereMode: Int, CaseIterable, Codable, Sendable {
    case aurora = 0, petals, embers, rain, motes, speed, stars, abyss

    public var label: String {
        switch self {
        case .aurora: return "Aurora"
        case .petals: return "Drifting petals"
        case .embers: return "Embers"
        case .rain: return "Rain"
        case .motes: return "Dust motes"
        case .speed: return "Speed lines"
        case .stars: return "Starfield"
        case .abyss: return "Abyss"
        }
    }
}

public struct Atmosphere: Hashable, Sendable {
    public var mode: AtmosphereMode
    public var palette: ArtworkPalette
    /// 0…1: how energetic the motion is.
    public var energy: Double
    /// 0…1: particle density before the effects budget scales it.
    public var density: Double

    public init(mode: AtmosphereMode, palette: ArtworkPalette, energy: Double, density: Double) {
        self.mode = mode
        self.palette = palette
        self.energy = energy
        self.density = density
    }

    public static func resolve(for media: Media, palette: ArtworkPalette? = nil) -> Atmosphere {
        let pal = palette ?? .from(hex: media.coverImage?.color)
        let genres = Set(media.genres ?? [])
        let tags = Set(media.safeTags.prefix(12).map(\.name))
        let vibe = VibeProfile.of(media)

        let mode: AtmosphereMode
        if !tags.isDisjoint(with: ["Space", "Space Opera", "Aliens", "Astronomy"]) || genres.contains("Mecha") { mode = .stars }
        else if genres.contains("Horror") || (!tags.isDisjoint(with: ["Gore", "Survival", "Tragedy"]) && genres.contains("Psychological")) { mode = .abyss }
        else if genres.contains("Sports") || !tags.isDisjoint(with: ["Racing", "Cars"]) { mode = .speed }
        else if !tags.isDisjoint(with: ["Urban Fantasy", "Noir", "Detective", "Cyberpunk", "Rain"]) || genres.contains("Mystery") { mode = .rain }
        else if genres.contains("Romance") || !tags.isDisjoint(with: ["School", "Coming of Age", "Love Triangle"]) { mode = .petals }
        else if genres.contains("Action") || !tags.isDisjoint(with: ["Demons", "Super Power", "War", "Martial Arts"]) { mode = .embers }
        else if genres.contains("Slice of Life") || !tags.isDisjoint(with: ["Iyashikei", "Rural", "Travel", "Food"]) { mode = .motes }
        else { mode = .aurora }

        return Atmosphere(mode: mode, palette: pal, energy: clamp(0.25 + vibe.intensity * 0.75), density: clamp(0.4 + vibe.intensity * 0.4))
    }
}
