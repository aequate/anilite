import Foundation

/// Where a legitimate provider operates. This describes the *service*, not a particular
/// title — catalogues differ per country, so the UI always says to confirm on the provider.
public enum ServiceFootprint: Hashable, Sendable {
    case worldwide(except: Set<String>)
    case only(Set<String>)
    case discontinued
    case unknown

    public func covers(_ region: String?) -> Bool? {
        guard let region = region?.uppercased() else { return nil }
        switch self {
        case .worldwide(let except): return !except.contains(region)
        case .only(let regions): return regions.contains(region)
        case .discontinued: return false
        case .unknown: return nil
        }
    }
}

public struct ProviderInfo: Hashable, Sendable {
    public var name: String
    public var kind: Kind
    public var footprint: ServiceFootprint
    public var isFree: Bool

    public enum Kind: String, Hashable, Sendable { case streaming, reading }
}

public struct WhereOption: Hashable, Sendable, Identifiable {
    public enum Availability: Hashable, Sendable {
        /// The service operates in the viewer's region (title availability not verified).
        case serviceInRegion
        /// The service is not normally offered in the viewer's region.
        case serviceNotInRegion
        /// A regional channel (e.g. Muse Asia on YouTube) that targets specific countries.
        case regionalChannel(String)
        case discontinued
        case unknown
    }

    public var site: String
    public var url: URL
    public var kind: ProviderInfo.Kind
    public var availability: Availability
    public var isFree: Bool
    public var language: String?
    public var colorHex: String?
    public var iconURL: String?
    public var id: String { site + url.absoluteString }

    public var note: String {
        switch availability {
        case .serviceInRegion: return "Offered in your region — check the title is in your catalogue."
        case .serviceNotInRegion: return "This service isn't usually available in your region."
        case .regionalChannel(let label): return "\(label) — regional, may be geo-restricted."
        case .discontinued: return "This service has closed."
        case .unknown: return "Listed on AniList. Availability varies by region."
        }
    }

    public var isLikelyAvailable: Bool {
        switch availability {
        case .serviceInRegion, .unknown, .regionalChannel: return true
        case .serviceNotInRegion, .discontinued: return false
        }
    }
}

public enum StreamingResolver {
    static let mainlandChina: Set<String> = ["CN"]

    static let providers: [String: ProviderInfo] = {
        let list: [ProviderInfo] = [
            ProviderInfo(name: "Crunchyroll", kind: .streaming, footprint: .worldwide(except: ["CN", "KR", "JP", "VN", "TH"]), isFree: false),
            ProviderInfo(name: "Netflix", kind: .streaming, footprint: .worldwide(except: ["CN", "KP", "SY", "RU"]), isFree: false),
            ProviderInfo(name: "Amazon Prime Video", kind: .streaming, footprint: .worldwide(except: ["CN", "KP", "IR", "SY", "CU"]), isFree: false),
            ProviderInfo(name: "Disney Plus", kind: .streaming, footprint: .worldwide(except: ["CN", "RU", "KP", "IN"]), isFree: false),
            ProviderInfo(name: "Hulu", kind: .streaming, footprint: .only(["US", "JP"]), isFree: false),
            ProviderInfo(name: "HIDIVE", kind: .streaming, footprint: .worldwide(except: ["CN", "JP", "KR"]), isFree: false),
            ProviderInfo(name: "Tubi TV", kind: .streaming, footprint: .only(["US", "CA", "MX", "AU", "NZ", "GB", "EC", "CR", "GT", "SV", "PA"]), isFree: true),
            ProviderInfo(name: "YouTube", kind: .streaming, footprint: .worldwide(except: ["CN", "KP"]), isFree: true),
            ProviderInfo(name: "Bilibili TV", kind: .streaming, footprint: .worldwide(except: ["CN"]), isFree: true),
            ProviderInfo(name: "iQ", kind: .streaming, footprint: .worldwide(except: ["CN"]), isFree: true),
            ProviderInfo(name: "Max", kind: .streaming, footprint: .unknown, isFree: false),
            ProviderInfo(name: "Adult Swim", kind: .streaming, footprint: .only(["US"]), isFree: false),
            ProviderInfo(name: "Funimation", kind: .streaming, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "VRV", kind: .streaming, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "Wakanim", kind: .streaming, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "AnimeLab", kind: .streaming, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "Netflix Japan", kind: .streaming, footprint: .only(["JP"]), isFree: false),
            ProviderInfo(name: "U-NEXT", kind: .streaming, footprint: .only(["JP"]), isFree: false),
            ProviderInfo(name: "ABEMA", kind: .streaming, footprint: .only(["JP"]), isFree: true),
            ProviderInfo(name: "Laftel", kind: .streaming, footprint: .only(["KR"]), isFree: false),
            ProviderInfo(name: "Bilibili", kind: .streaming, footprint: .only(["CN"]), isFree: false),
            ProviderInfo(name: "Aniplus Asia", kind: .streaming, footprint: .only(["SG", "MY", "PH", "ID", "TH", "VN"]), isFree: false),
            ProviderInfo(name: "MANGA Plus", kind: .reading, footprint: .worldwide(except: ["CN", "KR", "JP"]), isFree: true),
            ProviderInfo(name: "Viz", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "K MANGA", kind: .reading, footprint: .only(["US", "CA"]), isFree: false),
            ProviderInfo(name: "WEBTOON", kind: .reading, footprint: .worldwide(except: ["CN"]), isFree: true),
            ProviderInfo(name: "Tapas", kind: .reading, footprint: .worldwide(except: ["CN"]), isFree: true),
            ProviderInfo(name: "Comikey", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "BOOK☆WALKER", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "Pocket Comics", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "INKR", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "Azuki", kind: .reading, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "Comixology", kind: .reading, footprint: .discontinued, isFree: false),
            ProviderInfo(name: "Kodansha Comics", kind: .reading, footprint: .unknown, isFree: false),
            ProviderInfo(name: "Shonen Jump", kind: .reading, footprint: .unknown, isFree: false)
        ]
        return Dictionary(uniqueKeysWithValues: list.map { (normalize($0.name), $0) })
    }()

    /// Known regional channels that appear in AniList's link notes.
    static let regionalNotes: [String: String] = [
        "muse asia": "Muse Asia channel (South & Southeast Asia)",
        "ani-one asia": "Ani-One Asia channel (Asia-Pacific)",
        "ani-one": "Ani-One channel (Asia-Pacific)",
        "gundam info": "GUNDAM.INFO channel"
    ]

    /// Reading sites AniList sometimes files under INFO rather than STREAMING.
    static let readingSites: Set<String> = ["manga plus", "viz", "k manga", "webtoon", "tapas", "comikey", "book walker", "bookwalker",
                                            "pocket comics", "inkr", "azuki", "comixology", "kodansha comics", "shonen jump", "manga up!", "j-novel club", "yen press"]

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "☆", with: " ")
            .replacingOccurrences(of: "+", with: " plus")
            .split(separator: " ").joined(separator: " ")
    }

    public static func options(for media: Media, region: String?) -> [WhereOption] {
        var options: [WhereOption] = []
        var seen = Set<String>()
        for link in media.externalLinks ?? [] {
            guard link.isDisabled != true, let raw = link.url, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { continue }
            let key = normalize(link.site)
            let isReading = readingSites.contains(key) || providers[key]?.kind == .reading
            guard link.type == .streaming || isReading else { continue }
            guard seen.insert(key + "|" + (link.notes ?? "")).inserted else { continue }

            let provider = providers[key]
            var availability: WhereOption.Availability = .unknown
            if let note = link.notes?.lowercased(), let label = regionalNotes.first(where: { note.contains($0.key) })?.value {
                availability = .regionalChannel(label)
            } else if let provider {
                switch provider.footprint {
                case .discontinued: availability = .discontinued
                default:
                    switch provider.footprint.covers(region) {
                    case true?: availability = .serviceInRegion
                    case false?: availability = .serviceNotInRegion
                    case nil: availability = .unknown
                    }
                }
            }
            options.append(WhereOption(
                site: link.site, url: url, kind: isReading || media.mediaType == .manga ? .reading : .streaming,
                availability: availability, isFree: provider?.isFree ?? false, language: link.language,
                colorHex: link.color, iconURL: link.icon
            ))
        }
        return options.sorted { a, b in
            func rank(_ o: WhereOption) -> Int {
                switch o.availability {
                case .serviceInRegion: return 0
                case .regionalChannel: return 1
                case .unknown: return 2
                case .serviceNotInRegion: return 3
                case .discontinued: return 4
                }
            }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.isFree != b.isFree { return a.isFree }
            return a.site < b.site
        }
    }

    public static var currentRegion: String? {
        #if canImport(Darwin)
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.region?.identifier
        }
        #endif
        return Locale.current.regionCode
    }
}
