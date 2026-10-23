import Foundation

/// A piece of AniList prose. Spoiler segments come from `~!…!~` markup.
public struct TextSegment: Hashable, Sendable {
    public var text: String
    public var isSpoiler: Bool

    public init(text: String, isSpoiler: Bool) {
        self.text = text
        self.isSpoiler = isSpoiler
    }
}

/// Converts AniList descriptions (light HTML + AniList markdown) into clean segments.
public enum RichText {
    public static func segments(from raw: String?) -> [TextSegment] {
        guard let raw, !raw.isEmpty else { return [] }
        var result: [TextSegment] = []
        var remaining = Substring(raw)
        while let open = remaining.range(of: "~!") {
            let before = String(remaining[..<open.lowerBound])
            if !before.isEmpty { result.append(TextSegment(text: before, isSpoiler: false)) }
            let afterOpen = remaining[open.upperBound...]
            if let close = afterOpen.range(of: "!~") {
                result.append(TextSegment(text: String(afterOpen[..<close.lowerBound]), isSpoiler: true))
                remaining = afterOpen[close.upperBound...]
            } else {
                // Unterminated spoiler: treat the rest as a spoiler to be safe.
                result.append(TextSegment(text: String(afterOpen), isSpoiler: true))
                remaining = ""
            }
        }
        if !remaining.isEmpty { result.append(TextSegment(text: String(remaining), isSpoiler: false)) }

        // AniList HTML descriptions also use <span class='markdown_spoiler'>.
        result = result.flatMap(splitHTMLSpoilers)

        return result
            .map { TextSegment(text: clean($0.text), isSpoiler: $0.isSpoiler) }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func plain(_ raw: String?, includeSpoilers: Bool = false) -> String {
        segments(from: raw)
            .filter { includeSpoilers || !$0.isSpoiler }
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitHTMLSpoilers(_ segment: TextSegment) -> [TextSegment] {
        guard !segment.isSpoiler, segment.text.contains("markdown_spoiler") else { return [segment] }
        var out: [TextSegment] = []
        var rest = Substring(segment.text)
        let openPattern = #"<span class=['"]markdown_spoiler['"]>"#
        while let open = rest.range(of: openPattern, options: .regularExpression) {
            let before = String(rest[..<open.lowerBound])
            if !before.isEmpty { out.append(TextSegment(text: before, isSpoiler: false)) }
            let after = rest[open.upperBound...]
            if let close = after.range(of: "</span>") {
                out.append(TextSegment(text: String(after[..<close.lowerBound]), isSpoiler: true))
                rest = after[close.upperBound...]
            } else {
                out.append(TextSegment(text: String(after), isSpoiler: true))
                rest = ""
            }
        }
        if !rest.isEmpty { out.append(TextSegment(text: String(rest), isSpoiler: false)) }
        return out
    }

    /// Strips HTML/markdown and normalises whitespace while keeping paragraph breaks.
    public static func clean(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Markdown links: [text](url) → text
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Bold/italic markers
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\r", with: "")
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        // Ordered so "&amp;" is decoded last and "&amp;lt;" stays "&lt;".
        let table: [(String, String)] = [("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
                                         ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&amp;", "&")]
        for (k, v) in table { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    /// Drops the "(Source: …)" credit line AniList appends to synopses.
    public static func withoutSourceCredit(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*\((?i:source|written by)[^)]*\)\s*$"#, with: "", options: .regularExpression)
    }
}
