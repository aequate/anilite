import Foundation

public enum Formatting {
    /// 950 → "950", 12_400 → "12K", 1_250_000 → "1.3M"
    public static func compact(_ value: Int) -> String {
        let v = Double(value)
        switch abs(value) {
        case 1_000_000...: return trim(v / 1_000_000) + "M"
        case 10_000...: return String(Int((v / 1_000).rounded())) + "K"
        case 1_000...: return trim(v / 1_000) + "K"
        default: return String(value)
        }
    }

    private static func trim(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// 135 → "2h 15m", 45 → "45m", 3_000 → "50h"
    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        if h >= 20 || m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "in 3d 4h", "in 25m", "now"
    public static func countdown(seconds: Int) -> String {
        if seconds <= 0 { return "now" }
        let d = seconds / 86_400, h = (seconds % 86_400) / 3_600, m = (seconds % 3_600) / 60
        if d > 0 { return "in \(d)d \(h)h" }
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(max(1, m))m"
    }
}
