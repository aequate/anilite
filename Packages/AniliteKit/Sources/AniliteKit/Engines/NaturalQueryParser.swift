import Foundation

/// Turns plain requests like "short cozy fantasy from the 2010s, no romance" or
/// "something like Frieren but darker, I have 3 hours" into a structured query.
/// Deterministic and on-device: every interpretation is shown back as an editable chip.
public struct NaturalQueryParser: Sendable {
    public var now: Date
    public var calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.now = now
        self.calendar = calendar
    }

    // Phrase → AniList genre (exact GenreCollection names).
    static let genreLexicon: [(String, String)] = [
        ("slice of life", "Slice of Life"), ("everyday life", "Slice of Life"),
        ("science fiction", "Sci-Fi"), ("sci-fi", "Sci-Fi"), ("sci fi", "Sci-Fi"), ("scifi", "Sci-Fi"),
        ("magical girls?", "Mahou Shoujo"), ("mahou shoujo", "Mahou Shoujo"),
        ("giant robots?", "Mecha"), ("mecha", "Mecha"),
        ("action", "Action"), ("adventure", "Adventure"), ("adventures", "Adventure"),
        ("comedy", "Comedy"), ("comedies", "Comedy"),
        ("drama", "Drama"), ("dramas", "Drama"),
        ("fantasy", "Fantasy"),
        ("horror", "Horror"), ("scary", "Horror"), ("creepy", "Horror"), ("spooky", "Horror"),
        ("mystery", "Mystery"), ("mysteries", "Mystery"), ("whodunn?it", "Mystery"),
        ("psychological", "Psychological"),
        ("romance", "Romance"), ("love stor(?:y|ies)", "Romance"), ("rom-?com", "Romance"),
        ("sports?", "Sports"),
        ("supernatural", "Supernatural"),
        ("thrillers?", "Thriller"), ("suspense", "Thriller"),
        ("music", "Music"), ("musical", "Music")
    ]

    // Phrase → AniList tag (exact MediaTagCollection names; validated in tests).
    static let tagLexicon: [(String, String)] = [
        ("another world", "Isekai"), ("isekai", "Isekai"), ("transported to", "Isekai"),
        ("iyashikei", "Iyashikei"), ("healing", "Iyashikei"),
        ("time loops?", "Time Loop"), ("time travel", "Time Manipulation"),
        ("space opera", "Space Opera"), ("outer space", "Space"), ("space", "Space"),
        ("vampires?", "Vampire"), ("zombies?", "Zombie"), ("samurai", "Samurai"), ("ninjas?", "Ninja"),
        ("pirates?", "Pirates"), ("dragons?", "Dragons"), ("demons?", "Demons"), ("gods", "Gods"),
        ("elf|elves", "Elf"), ("witch(?:es)?", "Witch"), ("detectives?", "Detective"),
        ("high school", "School"), ("school", "School"), ("idols?", "Idol"), ("bands?", "Band"),
        ("cooking", "Food"), ("food", "Food"), ("video games?", "Video Games"), ("gaming", "Video Games"),
        ("virtual reality", "Virtual World"), ("vr", "Virtual World"), ("cyberpunk", "Cyberpunk"),
        ("post-?apocalyptic", "Post-Apocalyptic"), ("apocalypse", "Post-Apocalyptic"),
        ("dystopian?", "Dystopian"), ("military", "Military"), ("war", "War"),
        ("martial arts", "Martial Arts"), ("kung fu", "Martial Arts"),
        ("superheroe?s?", "Superhero"), ("super ?powers?", "Super Power"),
        ("revenge", "Revenge"), ("found family", "Found Family"), ("coming of age", "Coming of Age"),
        ("female (?:lead|protagonist|mc)", "Female Protagonist"), ("male (?:lead|protagonist|mc)", "Male Protagonist"),
        ("villainess", "Villainess"), ("reincarnat(?:ion|ed)", "Reincarnation"),
        ("survival", "Survival"), ("death games?", "Death Game"), ("battle royale", "Battle Royale"),
        ("yuri", "Yuri"), ("boys'? love", "Boys' Love"), ("workplace", "Work"), ("office", "Office"),
        ("historical", "Historical"), ("mythology", "Mythology"), ("philosophical", "Philosophy"), ("philosophy", "Philosophy"),
        ("political", "Politics"), ("politics", "Politics"), ("crime", "Crime"), ("yakuza", "Yakuza"), ("mafia", "Mafia"),
        ("anthology", "Anthology"), ("episodic", "Episodic"), ("road trip", "Travel"), ("travel(?:ling|ing)?", "Travel"),
        ("camping", "Camping"), ("kaiju", "Kaiju"), ("ghosts?", "Ghost"), ("youkai|yokai", "Youkai"),
        ("alchemy", "Alchemy"), ("assassins?", "Assassins"), ("robots?", "Robots"), ("aliens?", "Aliens"),
        ("dungeons?", "Dungeon"), ("cultivation", "Cultivation"), ("wuxia", "Wuxia"), ("tragedy", "Tragedy"),
        ("chess|shogi", "Shogi"), ("basketball", "Basketball"), ("volleyball", "Volleyball"), ("baseball", "Baseball"),
        ("football|soccer", "Football"), ("boxing", "Boxing"), ("swimming", "Swimming"), ("cars|racing", "Cars"),
        ("ensemble cast", "Ensemble Cast"), ("anti-?hero", "Anti-Hero"), ("conspiracy", "Conspiracy"),
        ("magic", "Magic"), ("gore|gory", "Gore"), ("parody", "Parody")
    ]

    static let moodLexicon: [(String, Mood)] = [
        ("feel-?good", .uplifting), ("uplifting", .uplifting), ("inspiring", .uplifting), ("hopeful", .uplifting),
        ("motivat(?:ing|ional)", .uplifting), ("happy", .uplifting), ("wholesome", .uplifting), ("lighter", .uplifting),
        ("cozy|cosy|comfy", .cozy), ("heart-?warming", .cozy), ("comforting", .cozy), ("soothing", .cozy),
        ("intense", .intense), ("adrenaline", .intense), ("hype", .intense), ("action-?packed", .intense), ("thrilling", .intense), ("edge of (?:my|your) seat", .intense),
        ("darker", .dark), ("dark", .dark), ("grim", .dark), ("bleak", .dark), ("gritty", .dark), ("disturbing", .dark), ("brutal", .dark),
        ("funny", .funny), ("hilarious", .funny), ("make me laugh", .funny), ("laughs?", .funny),
        ("sad", .heartbreaking), ("tear-?jerkers?", .heartbreaking), ("make me cry", .heartbreaking), ("cry", .heartbreaking),
        ("heart-?breaking", .heartbreaking), ("emotional", .heartbreaking), ("tragic", .heartbreaking),
        ("mind-? ?bending", .mindBending), ("mind-?blowing", .mindBending), ("twisty", .mindBending), ("plot twists?", .mindBending),
        ("cerebral", .mindBending), ("trippy", .mindBending), ("make me think", .mindBending),
        ("romantic", .romantic), ("cute couples?", .romantic),
        ("epic", .epic), ("grand", .epic), ("sweeping", .epic),
        ("chill", .chill), ("relaxing", .chill), ("laid-? ?back", .chill), ("low-? ?key", .chill), ("background", .chill)
    ]

    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "with", "some", "something", "anything", "anime", "animes", "show", "shows", "series",
        "i", "im", "i'm", "me", "my", "want", "wanna", "need", "looking", "for", "to", "watch", "read", "find", "recommend",
        "give", "please", "good", "great", "that", "is", "are", "be", "of", "in", "on", "about", "kind", "sort", "type", "vibe",
        "vibes", "really", "very", "super", "pretty", "quite", "but", "can", "you", "suggest", "what", "should", "which", "title",
        "titles", "one", "ones", "like", "less", "more", "it", "its", "have", "has", "got", "time", "just", "maybe", "also", "new", "story", "stories", "where"
    ]

    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "twenty": 20, "a couple": 2, "a few": 3, "an": 1, "a": 1, "half an": 0
    ]

    public func parse(_ input: String) -> ParsedQuery {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var q = DiscoveryQuery()
        var chips: [InterpretationChip] = []
        var work = " " + normalise(original) + " "
        var structuredHits = 0

        func add(_ kind: InterpretationChip.Kind, _ label: String) {
            let chip = InterpretationChip(kind: kind, label: label)
            if !chips.contains(chip) { chips.append(chip) }
        }

        // 1. "like X" / "similar to X" — capture the title before other rules eat its words.
        if let m = firstCapture(#"(?:similar to|same vibes? as|reminds? me of|if i liked|fans? of|like)\s+([a-z0-9'’\-\.!:; ]+?)(?=\s+(?:but|with|without|and|under|from|that|which|in|less|more|no)\s|[,\.]|\s*$)"#, in: work) {
            let title = m.capture.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !Self.stopwords.contains(title), !isLexiconOnly(title) {
                q.likeTitle = title
                add(.similar, "Like “\(title.capitalizedTitle)”")
                work.replaceSubrange(m.range, with: " ")
                structuredHits += 1
            }
        }

        // 2. Type and format.
        if consume(#"manhwa|webtoons?"#, in: &work) { q.type = .manga; q.country = "KR"; add(.type, "Manhwa"); structuredHits += 1 }
        if consume(#"manhua"#, in: &work) { q.type = .manga; q.country = "CN"; add(.type, "Manhua"); structuredHits += 1 }
        if consume(#"light novels?|novels?"#, in: &work) { q.type = .manga; q.formats = [.novel]; add(.type, "Light novel"); structuredHits += 1 }
        if consume(#"one-?shots?"#, in: &work) { q.type = .manga; q.formats = [.oneShot]; add(.format, "One-shot"); structuredHits += 1 }
        if consume(#"manga|comics?|to read|reading"#, in: &work) { q.type = .manga; add(.type, "Manga"); structuredHits += 1 }
        if consume(#"movies?|films?"#, in: &work) { q.formats = [.movie]; add(.format, "Movie"); structuredHits += 1 }
        if consume(#"ovas?"#, in: &work) { q.formats = [.ova]; add(.format, "OVA"); structuredHits += 1 }

        // 3. Time budget.
        if let m = firstCapture(#"(?:i have|i've got|got|in|within|only|under|less than)?\s*(\d+(?:\.\d+)?|an?|one|two|three|four|five|six|half an)\s*(hours?|hrs?|h|minutes?|mins?)\b(?!\s*(?:per|an|each|long episodes))"#, in: work) {
            let parts = m.capture.split(separator: "|")
            if parts.count == 2 {
                let amount = Double(parts[0]) ?? Double(Self.numberWords[String(parts[0])] ?? 1)
                let unitIsHours = parts[1].hasPrefix("h")
                let minutes = String(parts[0]) == "half an" ? 30 : Int(unitIsHours ? amount * 60 : amount)
                if minutes > 0 {
                    q.maxTotalMinutes = minutes
                    add(.time, minutes >= 60 ? "Fits in \(formatHours(minutes))" : "Fits in \(minutes) min")
                    work.replaceSubrange(m.range, with: " ")
                    structuredHits += 1
                }
            }
        }
        if consume(#"tonight|this evening"#, in: &work) { q.maxTotalMinutes = q.maxTotalMinutes ?? 180; add(.time, "Tonight (~3h)"); structuredHits += 1 }
        if consume(#"(?:this |a |one )?weekend"#, in: &work) { q.maxTotalMinutes = q.maxTotalMinutes ?? 600; add(.time, "A weekend (~10h)"); structuredHits += 1 }
        if consume(#"commute|bite-?sized|quick episodes"#, in: &work) { q.maxEpisodeMinutes = 12; add(.length, "Short episodes"); structuredHits += 1 }

        // 4. Episode counts.
        if let m = firstCapture(#"(?:under|less than|fewer than|below|at most|max(?:imum)?|no more than|up to|<=?)\s*(\d+|[a-z]+)\s*(?:episodes?|eps?|chapters?|ch)\b"#, in: work),
           let n = Int(m.capture) ?? Self.numberWords[m.capture] {
            if q.type == .manga { add(.length, "≤ \(n) chapters") } else { q.maxEpisodes = n; add(.length, "≤ \(n) episodes") }
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        } else if let m = firstCapture(#"(\d+|[a-z]+)\s*(?:episodes?|eps?)\s*(?:or less|or fewer|max)"#, in: work),
                  let n = Int(m.capture) ?? Self.numberWords[m.capture] {
            q.maxEpisodes = n
            add(.length, "≤ \(n) episodes")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        }
        if let m = firstCapture(#"(?:over|more than|at least|longer than|>=?)\s*(\d+)\s*(?:episodes?|eps?)"#, in: work), let n = Int(m.capture) {
            q.minEpisodes = n
            add(.length, "≥ \(n) episodes")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        }
        if consume(#"one cour|single season|one season|short(?:er)?|quick|bingeable|binge-?able"#, in: &work) {
            if q.maxEpisodes == nil && q.formats.isEmpty { q.maxEpisodes = 13; add(.length, "Short (≤ 13 eps)") }
            structuredHits += 1
        }
        if consume(#"long-?running|longer|long|lengthy|epic length"#, in: &work) {
            if q.minEpisodes == nil { q.minEpisodes = 40; add(.length, "Long (40+ eps)") }
            structuredHits += 1
        }

        // 5. Era.
        let year = calendar.component(.year, from: now)
        if let m = firstCapture(#"(?:from the |in the )?(?:19|20)?(\d0)'?s\b"#, in: work), let decade = Int(m.capture) {
            let full = decade >= 50 ? 1900 + decade : 2000 + decade
            q.yearFrom = full
            q.yearTo = full + 9
            add(.era, "\(full)s")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        } else if let m = firstCapture(#"(?:after|since|from|newer than)\s+((?:19|20)\d\d)"#, in: work), let y = Int(m.capture) {
            q.yearFrom = y
            add(.era, "Since \(y)")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        } else if let m = firstCapture(#"(?:before|older than|pre)\s*-?\s*((?:19|20)\d\d)"#, in: work), let y = Int(m.capture) {
            q.yearTo = y - 1
            add(.era, "Before \(y)")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        } else if let m = firstCapture(#"(?:in|from|aired in)\s+((?:19|20)\d\d)"#, in: work), let y = Int(m.capture) {
            q.yearFrom = y
            q.yearTo = y
            add(.era, "\(y)")
            work.replaceSubrange(m.range, with: " ")
            structuredHits += 1
        }
        if consume(#"recent|latest|modern|newer|new(?:ish)? releases?"#, in: &work) { q.yearFrom = q.yearFrom ?? year - 2; add(.era, "Recent"); structuredHits += 1 }
        if consume(#"classics?|old-? ?school|retro|vintage|older"#, in: &work) { q.yearTo = q.yearTo ?? 2005; add(.era, "Classic"); structuredHits += 1 }

        // 6. Status.
        if consume(#"(?:currently |still )?(?:airing|ongoing|this season|simulcast)"#, in: &work) { q.status = .releasing; add(.status, "Airing now"); structuredHits += 1 }
        if consume(#"finished|completed|complete|already ended|done airing"#, in: &work) { q.status = .finished; add(.status, "Finished"); structuredHits += 1 }

        // 7. Quality and popularity.
        if consume(#"hidden gems?|underrated|under-?the-?radar|obscure|lesser-? ?known|underground|niche"#, in: &work) {
            q.maxPopularity = 40_000
            q.minScore = max(q.minScore ?? 0, 72)
            q.sort = .score
            add(.quality, "Hidden gems")
            structuredHits += 1
        }
        if consume(#"masterpieces?|best|top-? ?rated|highly rated|acclaimed|critically acclaimed|must-? ?watch|greatest"#, in: &work) {
            q.minScore = max(q.minScore ?? 0, 80)
            q.sort = q.sort ?? .score
            add(.quality, "Highly rated")
            structuredHits += 1
        }
        if consume(#"trending|everyone'?s watching|hot right now"#, in: &work) { q.sort = .trending; add(.quality, "Trending"); structuredHits += 1 }
        if consume(#"popular|mainstream"#, in: &work) { q.sort = q.sort ?? .popularity; add(.quality, "Popular"); structuredHits += 1 }

        // 8. Exclusions ("no romance", "without fanservice").
        let negator = #"(?:no|not|without|minus|except|zero|skip|avoid|hate|less)\s+(?:too much\s+|any\s+|much\s+)?"#
        for (pattern, genre) in Self.genreLexicon {
            if consume(negator + "(?:" + pattern + ")", in: &work) {
                q.genresExclude.append(genre)
                add(.exclude, "No \(genre)")
                structuredHits += 1
            }
        }
        for (pattern, tag) in Self.tagLexicon {
            if consume(negator + "(?:" + pattern + ")", in: &work) {
                q.tagsExclude.append(tag)
                add(.exclude, "No \(tag)")
                structuredHits += 1
            }
        }
        if consume(negator + "(?:fan ?service|ecchi)", in: &work) { q.genresExclude.append("Ecchi"); add(.exclude, "No Ecchi"); structuredHits += 1 }

        // 9. Moods (before genres so "romantic" becomes a mood, "romance" a genre).
        for (pattern, mood) in Self.moodLexicon where consume(pattern, in: &work) {
            if !q.moods.contains(mood) {
                q.moods.append(mood)
                add(.mood, mood.label)
            }
            structuredHits += 1
        }

        // 10. Genres and tags.
        for (pattern, genre) in Self.genreLexicon where consume(pattern, in: &work) {
            if !q.genresInclude.contains(genre), !q.genresExclude.contains(genre) {
                q.genresInclude.append(genre)
                add(.genre, genre)
            }
            structuredHits += 1
        }
        for (pattern, tag) in Self.tagLexicon where consume(pattern, in: &work) {
            if !q.tagsInclude.contains(tag), !q.tagsExclude.contains(tag) {
                q.tagsInclude.append(tag)
                add(.tag, tag)
            }
            structuredHits += 1
        }

        // 11. Whatever's left is free text (often a title or keyword).
        let residual = work
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty && !Self.stopwords.contains($0) && $0.count > 1 && Int($0) == nil }
        if structuredHits == 0 {
            q.text = original.isEmpty ? nil : original
        } else if !residual.isEmpty {
            q.text = residual.joined(separator: " ")
        }

        // Too many required genres/tags usually means zero results; keep the strongest.
        if q.genresInclude.count > 2 { q.genresInclude = Array(q.genresInclude.prefix(2)) }
        if q.tagsInclude.count > 2 { q.tagsInclude = Array(q.tagsInclude.prefix(2)) }

        let words = original.split(separator: " ").count
        let titleGuess = (words <= 4 && structuredHits <= 1 && q.maxTotalMinutes == nil && q.maxEpisodes == nil) ? original : nil
        return ParsedQuery(query: q, chips: chips, alsoSearchTitle: (titleGuess?.isEmpty == false && titleGuess != q.text) ? titleGuess : nil)
    }

    // MARK: Helpers

    /// "I like action anime" shouldn't treat "action anime" as a title.
    private func isLexiconOnly(_ phrase: String) -> Bool {
        var copy = " " + phrase + " "
        let patterns = Self.genreLexicon.map(\.0) + Self.tagLexicon.map(\.0) + Self.moodLexicon.map(\.0)
            + ["manga", "manhwa", "movies?", "films?", "shows?", "anime", "short", "long", "old", "new", "recent", "classics?"]
        for p in patterns { _ = consume(p, in: &copy) }
        let rest = copy.split(separator: " ").map(String.init).filter { !Self.stopwords.contains($0) }
        return rest.isEmpty
    }

    private func normalise(_ s: String) -> String {
        var out = s.lowercased()
        out = out.replacingOccurrences(of: "’", with: "'")
        out = out.replacingOccurrences(of: #"[?!\"“”]"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out
    }

    /// Removes every whole-word match of `pattern`; returns whether anything matched.
    private func consume(_ pattern: String, in work: inout String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![a-z0-9'])(?:"# + pattern + #")(?![a-z0-9])"#) else { return false }
        let range = NSRange(work.startIndex..., in: work)
        let matches = regex.matches(in: work, range: range)
        guard !matches.isEmpty else { return false }
        for m in matches.reversed() {
            if let r = Range(m.range, in: work) { work.replaceSubrange(r, with: " ") }
        }
        return true
    }

    /// Returns the first match's capture groups joined with "|", plus the full match range.
    private func firstCapture(_ pattern: String, in work: String) -> (capture: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![a-z0-9])"# + pattern) else { return nil }
        let range = NSRange(work.startIndex..., in: work)
        guard let m = regex.firstMatch(in: work, range: range), let full = Range(m.range, in: work) else { return nil }
        var captures: [String] = []
        if m.numberOfRanges > 1 {
            for i in 1..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: work) { captures.append(String(work[r])) }
            }
        }
        return (captures.joined(separator: "|"), full)
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

extension String {
    var capitalizedTitle: String {
        split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
