import Foundation

public struct GlossaryTerm: Hashable, Sendable, Identifiable {
    public var term: String
    public var aliases: [String]
    public var definition: String
    public var category: Category
    public var id: String { term }

    public enum Category: String, CaseIterable, Sendable {
        case format = "Formats", genre = "Demographics & genres", industry = "Industry", fandom = "Fandom", story = "Story terms"
    }
}

public enum Glossary {
    public static let terms: [GlossaryTerm] = [
        GlossaryTerm(term: "Anime", aliases: [], definition: "Animation from Japan. It's a medium, not a genre — there's anime for every taste and age.", category: .format),
        GlossaryTerm(term: "Manga", aliases: [], definition: "Japanese comics, usually read right-to-left. Most popular anime adapt a manga.", category: .format),
        GlossaryTerm(term: "Manhwa", aliases: ["webtoon"], definition: "Korean comics, often in full colour and read by vertical scrolling (webtoons). Solo Leveling is a famous example.", category: .format),
        GlossaryTerm(term: "Manhua", aliases: [], definition: "Chinese comics. Many are fantasy or cultivation stories.", category: .format),
        GlossaryTerm(term: "Light novel", aliases: ["ln", "light novels"], definition: "Short Japanese novels with illustrations. Shows like Re:Zero and Spice and Wolf adapt light novels.", category: .format),
        GlossaryTerm(term: "OVA", aliases: ["oav"], definition: "Original Video Animation: episodes released straight to home video, often bonus stories or extra arcs.", category: .format),
        GlossaryTerm(term: "ONA", aliases: [], definition: "Original Net Animation: anime released first on the internet or a streaming service.", category: .format),
        GlossaryTerm(term: "Special", aliases: ["specials"], definition: "Short extras — recaps, comedy shorts or bonus episodes. Usually optional.", category: .format),
        GlossaryTerm(term: "Cour", aliases: ["cours"], definition: "A broadcast block of roughly 12–13 weekly episodes (one season of TV). A \"2-cour\" show runs about 24 episodes.", category: .industry),
        GlossaryTerm(term: "Simulcast", aliases: [], definition: "Streaming an episode with subtitles shortly after it airs in Japan.", category: .industry),
        GlossaryTerm(term: "Sub / Dub", aliases: ["sub", "dub", "subbed", "dubbed"], definition: "Sub keeps the Japanese voices with subtitles; dub replaces them with voices in your language. Both are valid ways to watch.", category: .industry),
        GlossaryTerm(term: "Seiyuu", aliases: ["voice actor"], definition: "A Japanese voice actor. Many fans follow favourite seiyuu between shows.", category: .industry),
        GlossaryTerm(term: "Studio", aliases: [], definition: "The company that animates a show (e.g. MAPPA, Kyoto Animation, ufotable). Studios often have a recognisable style.", category: .industry),
        GlossaryTerm(term: "Shounen", aliases: ["shonen"], definition: "Manga aimed at teenage boys — think adventure, rivals and growth (Naruto, Jujutsu Kaisen). Anyone can enjoy them.", category: .genre),
        GlossaryTerm(term: "Shoujo", aliases: ["shojo"], definition: "Aimed at teenage girls — often focused on relationships and feelings (Fruits Basket).", category: .genre),
        GlossaryTerm(term: "Seinen", aliases: [], definition: "Aimed at adult men — frequently darker or more complex (Berserk, Vinland Saga).", category: .genre),
        GlossaryTerm(term: "Josei", aliases: [], definition: "Aimed at adult women — grounded drama and romance (Nana).", category: .genre),
        GlossaryTerm(term: "Isekai", aliases: [], definition: "\"Another world\" stories: someone is transported or reborn into a fantasy world.", category: .genre),
        GlossaryTerm(term: "Mecha", aliases: [], definition: "Stories built around giant robots or powered suits (Gundam, Evangelion).", category: .genre),
        GlossaryTerm(term: "Slice of life", aliases: ["sol"], definition: "Calm stories about everyday moments. Low stakes, high comfort.", category: .genre),
        GlossaryTerm(term: "Iyashikei", aliases: [], definition: "\"Healing\" anime designed to relax you (Mushishi, Laid-Back Camp).", category: .genre),
        GlossaryTerm(term: "Mahou shoujo", aliases: ["magical girl"], definition: "Magical-girl stories — sometimes cheerful, sometimes deconstructed into something much darker (Madoka Magica).", category: .genre),
        GlossaryTerm(term: "Filler", aliases: ["fillers"], definition: "Anime-original episodes made so the show doesn't overtake the manga. Usually skippable.", category: .story),
        GlossaryTerm(term: "Canon", aliases: [], definition: "Events that are part of the official story, as opposed to filler or alternate versions.", category: .story),
        GlossaryTerm(term: "Arc", aliases: ["arcs"], definition: "A story section with its own goal and climax, like a chapter of a long saga.", category: .story),
        GlossaryTerm(term: "Recap", aliases: ["recap episode", "compilation"], definition: "An episode or film that retells earlier events. Safe to skip if you've seen the originals.", category: .story),
        GlossaryTerm(term: "Source material", aliases: ["source"], definition: "What an anime is based on — usually a manga, light novel or game.", category: .story),
        GlossaryTerm(term: "Anime original ending", aliases: ["anime ending"], definition: "When an anime overtakes its source and invents its own ending (FMA 2003 vs. Brotherhood).", category: .story),
        GlossaryTerm(term: "Tsundere", aliases: [], definition: "A character who acts cold or prickly but is secretly warm-hearted.", category: .fandom),
        GlossaryTerm(term: "Yandere", aliases: [], definition: "A character whose affection turns obsessive or dangerous.", category: .fandom),
        GlossaryTerm(term: "Kuudere", aliases: [], definition: "A calm, unemotional character with hidden feelings.", category: .fandom),
        GlossaryTerm(term: "Senpai / Kouhai", aliases: ["senpai", "kouhai", "sempai"], definition: "Senior and junior in a school or workplace.", category: .fandom),
        GlossaryTerm(term: "Waifu / Husbando", aliases: ["waifu", "husbando"], definition: "Playful fan slang for a favourite character.", category: .fandom),
        GlossaryTerm(term: "Otaku", aliases: [], definition: "A devoted fan. Once an insult in Japan, now worn proudly by many.", category: .fandom),
        GlossaryTerm(term: "OP / ED", aliases: ["op", "ed", "opening", "ending song"], definition: "Opening and ending theme songs. Some are so good people never skip them.", category: .fandom),
        GlossaryTerm(term: "Sakuga", aliases: [], definition: "Moments of exceptionally fluid, high-effort animation — fans clip and celebrate them.", category: .industry),
        GlossaryTerm(term: "Donghua", aliases: [], definition: "Chinese animation, often adapting web novels or manhua.", category: .format),
        GlossaryTerm(term: "Chibi", aliases: [], definition: "A cute, super-deformed art style with tiny bodies and big heads, often for comedy.", category: .fandom)
    ]

    public static func lookup(_ text: String) -> GlossaryTerm? {
        let q = normalize(text)
        guard !q.isEmpty else { return nil }
        return terms.first { normalize($0.term) == q || $0.aliases.map(normalize).contains(q) }
    }

    /// Terms mentioned anywhere in a question.
    public static func mentioned(in text: String) -> [GlossaryTerm] {
        let q = " " + normalize(text) + " "
        return terms.filter { t in
            ([t.term] + t.aliases).contains { name in
                let n = normalize(name)
                return n.count >= 2 && q.contains(" " + n + " ")
            }
        }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
    }
}

/// A hand-picked first step for newcomers.
public struct GatewayPick: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var type: MediaType
    public var why: String
    public var commitment: String
    public var tags: Set<String>
}

public enum Gateway {
    public static let picks: [GatewayPick] = [
        GatewayPick(id: 154587, title: "Frieren: Beyond Journey's End", type: .anime, why: "A gentle, gorgeous fantasy about time and memory. Great first anime for adults.", commitment: "28 episodes", tags: ["fantasy", "emotional", "calm", "adventure"]),
        GatewayPick(id: 5114, title: "Fullmetal Alchemist: Brotherhood", type: .anime, why: "The all-rounder: action, mystery, heart and a satisfying ending.", commitment: "64 episodes", tags: ["action", "adventure", "fantasy", "complete"]),
        GatewayPick(id: 1535, title: "Death Note", type: .anime, why: "A cat-and-mouse thriller between two geniuses. Hard to stop watching.", commitment: "37 episodes", tags: ["thriller", "mystery", "dark", "psychological"]),
        GatewayPick(id: 1, title: "Cowboy Bebop", type: .anime, why: "Jazz, bounty hunters and space noir — mostly self-contained episodes.", commitment: "26 episodes", tags: ["scifi", "action", "classic", "episodic"]),
        GatewayPick(id: 140960, title: "Spy x Family", type: .anime, why: "A spy, an assassin and a telepath pretend to be a family. Funny and warm.", commitment: "12 episodes to start", tags: ["comedy", "action", "family", "lighthearted"]),
        GatewayPick(id: 199, title: "Spirited Away", type: .anime, why: "Studio Ghibli's masterpiece. One evening, no commitment.", commitment: "One film", tags: ["film", "fantasy", "family", "short"]),
        GatewayPick(id: 21519, title: "Your Name.", type: .anime, why: "A breathtaking romance with a twist. The perfect single-evening introduction.", commitment: "One film", tags: ["film", "romance", "emotional", "short"]),
        GatewayPick(id: 120377, title: "Cyberpunk: Edgerunners", type: .anime, why: "Stylish, intense and only ten episodes — a weekend binge.", commitment: "10 episodes", tags: ["scifi", "action", "dark", "short"]),
        GatewayPick(id: 20464, title: "Haikyu!!", type: .anime, why: "Proof that a volleyball show can be the most exciting thing you watch all year.", commitment: "25 episodes to start", tags: ["sports", "comedy", "hype"]),
        GatewayPick(id: 101921, title: "Kaguya-sama: Love is War", type: .anime, why: "Two geniuses too proud to confess. Romantic comedy at its sharpest.", commitment: "12 episodes to start", tags: ["romance", "comedy", "lighthearted"]),
        GatewayPick(id: 21827, title: "Violet Evergarden", type: .anime, why: "A former soldier learns what love means by writing letters. Bring tissues.", commitment: "13 episodes", tags: ["emotional", "drama", "beautiful"]),
        GatewayPick(id: 9253, title: "Steins;Gate", type: .anime, why: "A slow-burn time-travel thriller with one of the best payoffs in anime.", commitment: "24 episodes", tags: ["scifi", "thriller", "mystery"]),
        GatewayPick(id: 130003, title: "Bocchi the Rock!", type: .anime, why: "A painfully shy guitarist joins a band. Hilarious and very relatable.", commitment: "12 episodes", tags: ["comedy", "music", "lighthearted", "short"]),
        GatewayPick(id: 153518, title: "Delicious in Dungeon", type: .anime, why: "A dungeon crawl where the party cooks the monsters. Cozy and clever.", commitment: "24 episodes", tags: ["fantasy", "comedy", "adventure", "calm"]),
        GatewayPick(id: 21507, title: "Mob Psycho 100", type: .anime, why: "Explosive animation with a kind heart and a complete story.", commitment: "37 episodes total", tags: ["action", "comedy", "complete", "supernatural"]),
        GatewayPick(id: 30013, title: "One Piece (manga)", type: .manga, why: "The best-selling manga ever: a huge, joyful adventure. Reading is faster than watching.", commitment: "1100+ chapters", tags: ["adventure", "manga", "long"]),
        GatewayPick(id: 105398, title: "Solo Leveling", type: .manga, why: "A Korean webtoon power fantasy in full colour — easy scrolling on a phone.", commitment: "~200 chapters", tags: ["manga", "action", "manhwa", "complete"]),
        GatewayPick(id: 31706, title: "Steel Ball Run", type: .manga, why: "JoJo's horse-race epic stands alone — often called the best part of JoJo.", commitment: "96 chapters", tags: ["manga", "adventure", "complete"])
    ]

    public static func picks(matching words: Set<String>, limit: Int = 4) -> [GatewayPick] {
        guard !words.isEmpty else { return Array(picks.prefix(limit)) }
        return picks
            .map { ($0, $0.tags.intersection(words).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

/// What the concierge understood from a question.
public enum ConciergeIntent: Equatable, Sendable {
    case define(GlossaryTerm)
    case whereToStart(franchise: String)
    case whatNext
    case beginnerPicks(Set<String>)
    case watchOrder(franchise: String)
    case fillerQuestion(franchise: String)
    case findSimilar(title: String)
    case search(String)
    case greeting

    public static func == (a: ConciergeIntent, b: ConciergeIntent) -> Bool {
        switch (a, b) {
        case (.define(let x), .define(let y)): return x.term == y.term
        case (.whereToStart(let x), .whereToStart(let y)), (.watchOrder(let x), .watchOrder(let y)),
             (.fillerQuestion(let x), .fillerQuestion(let y)), (.findSimilar(let x), .findSimilar(let y)), (.search(let x), .search(let y)):
            return x == y
        case (.whatNext, .whatNext), (.greeting, .greeting): return true
        case (.beginnerPicks(let x), .beginnerPicks(let y)): return x == y
        default: return false
        }
    }
}

public enum Concierge {
    static let topicWords: [String: String] = [
        "fantasy": "fantasy", "magic": "fantasy", "action": "action", "fight": "action", "fighting": "action",
        "funny": "comedy", "comedy": "comedy", "laugh": "comedy", "romance": "romance", "romantic": "romance", "love": "romance",
        "sad": "emotional", "cry": "emotional", "emotional": "emotional", "scary": "dark", "dark": "dark", "horror": "dark",
        "mystery": "mystery", "detective": "mystery", "thriller": "thriller", "space": "scifi", "scifi": "scifi", "sci": "scifi", "robot": "scifi",
        "sports": "sports", "sport": "sports", "music": "music", "band": "music", "short": "short", "quick": "short", "film": "film", "movie": "film",
        "relaxing": "calm", "calm": "calm", "cozy": "calm", "chill": "calm", "manga": "manga", "read": "manga", "reading": "manga",
        "webtoon": "manhwa", "manhwa": "manhwa", "classic": "classic", "old": "classic", "finished": "complete", "complete": "complete", "ending": "complete",
        "kids": "family", "family": "family", "hype": "hype", "adventure": "adventure", "psychological": "psychological", "beautiful": "beautiful"
    ]

    public static func interpret(_ question: String) -> ConciergeIntent {
        let raw = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return .greeting }
        if ["hi", "hello", "hey", "yo", "help"].contains(lower) { return .greeting }

        let definePatterns = [#"^what(?:'s| is| are| does)\s+(?:an?\s+|the\s+)?(.+?)(?:\s+mean)?\??$"#, #"^(?:define|meaning of|explain)\s+(.+?)\??$"#]
        for p in definePatterns {
            if let capture = firstCapture(p, in: lower), let term = Glossary.lookup(capture) { return .define(term) }
        }

        if let f = firstCapture(#"(?:where|how) (?:do|should|can) i (?:start|begin)(?: with| watching| reading)?\s+(.+?)\??$"#, in: lower) {
            return .whereToStart(franchise: cleanTitle(f))
        }
        if let f = firstCapture(#"(?:watch|reading|viewing) order (?:for |of )?(.+?)\??$"#, in: lower)
            ?? firstCapture(#"(?:in )?what order (?:should i |do i |to )?(?:watch|read) (.+?)\??$"#, in: lower) {
            return .watchOrder(franchise: cleanTitle(f))
        }
        if let f = firstCapture(#"filler(?:s| episodes?| arcs?)?\s+(?:in|of|for)\s+(.+?)\??$"#, in: lower)
            ?? firstCapture(#"^(?:does|is there|are there)\s+(.+?)\s+(?:have\s+)?(?:any\s+)?filler"#, in: lower)
            ?? firstCapture(#"(?:skip|filler)(?: episodes?)?(?: in| of| for)?\s+(.+?)\??$"#, in: lower), !f.isEmpty, !f.hasPrefix("episodes") {
            return .fillerQuestion(franchise: cleanTitle(f))
        }
        if let t = firstCapture(#"(?:something|anything|shows?|anime|manga)\s+(?:like|similar to)\s+(.+?)\??$"#, in: lower)
            ?? firstCapture(#"^(?:like|similar to)\s+(.+?)\??$"#, in: lower) {
            return .findSimilar(title: cleanTitle(t))
        }
        if lower.contains("what next") || lower.contains("what should i watch next") || lower.contains("what to watch next") || lower.contains("what should i read next") {
            return .whatNext
        }

        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let isBeginner = ["new", "beginner", "first", "start", "starting", "newbie", "never", "recommend", "suggest", "into"].contains { words.contains($0) }
        let topics = Set(words.compactMap { topicWords[$0] })
        if isBeginner || (!topics.isEmpty && words.count <= 8) {
            return .beginnerPicks(topics)
        }
        if let term = Glossary.lookup(lower) { return .define(term) }
        return .search(raw)
    }

    static func cleanTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["the anime ", "the manga ", "the series "] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        return t.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        let value = String(text[r]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Plain-language advice for where to begin a franchise once it's been mapped.
    public static func startAdvice(graph: FranchiseGraph) -> String {
        let mainline = graph.mainline
        guard let first = mainline.first else {
            if let source = graph.sourceMedia { return "There's no anime yet — start with \(source.titleText) from chapter 1." }
            return "Start with the first entry."
        }
        var lines = ["Start with \(first.titleText)\(first.year.map { " (\($0))" } ?? "")."]
        if mainline.count > 1 {
            let total = mainline.reduce(0) { $0 + Pathfinder.minutes(for: $1) }
            lines.append("The main story is \(mainline.count) entries, about \(Formatting.duration(minutes: total)) in total.")
        }
        let alternatives = graph.allAnime.filter { m in mainline.contains { graph.relation(from: $0.id, to: m.id) == .alternative } }
        if let alt = alternatives.first {
            lines.append("\(alt.titleText) is an alternate version — pick one, not both.")
        }
        if let filler = mainline.compactMap({ FillerGuide.info(for: $0.id) }).first {
            lines.append("There are \(filler.fillerCount) filler episodes you can skip — Pathfinder marks them.")
        }
        return lines.joined(separator: " ")
    }
}
