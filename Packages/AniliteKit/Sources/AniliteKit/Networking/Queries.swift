import Foundation

// All AniList operations used by the app. Each one batches as much as possible into a
// single request: the public API is currently limited to 30 requests per minute.

public enum Fragments {
    public static let card = """
    fragment card on Media {
      id idMal type format status episodes chapters volumes duration season seasonYear averageScore meanScore popularity trending favourites genres isAdult countryOfOrigin source(version: 3)
      title { romaji english native userPreferred }
      coverImage { extraLarge large color }
      bannerImage
      startDate { year month day } endDate { year month day }
      nextAiringEpisode { airingAt episode timeUntilAiring }
      studios(isMain: true) { nodes { id name } }
      tags { id name rank category isGeneralSpoiler isMediaSpoiler }
    }
    """

    /// Lighter card for graph expansion and relation walks.
    public static let lite = """
    fragment lite on Media {
      id type format status episodes chapters volumes duration seasonYear averageScore popularity genres isAdult countryOfOrigin
      title { romaji english native userPreferred }
      coverImage { large color }
      startDate { year month day }
      nextAiringEpisode { airingAt episode timeUntilAiring }
    }
    """
}

public struct PageInfo: Codable, Hashable, Sendable {
    public var hasNextPage: Bool?
    public var currentPage: Int?
    public var total: Int?
}

public struct MediaPage: Codable, Hashable, Sendable {
    public var pageInfo: PageInfo?
    public var media: [Media]
}

public struct PageResponse: Codable, Sendable {
    public var Page: MediaPage
}

public struct HomeFeed: Codable, Sendable {
    public var trending: MediaPage
    public var season: MediaPage
    public var manga: MediaPage
    public var top: MediaPage
    public var upcoming: MediaPage
}

public struct MediaResponse: Codable, Sendable {
    public var Media: Media
}

public struct MediaBatchResponse: Codable, Sendable {
    public var Page: MediaPage
}

public struct AiringSchedule: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var airingAt: Int
    public var episode: Int
    public var media: Media?
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(airingAt)) }

    public init(id: Int, airingAt: Int, episode: Int, media: Media?) {
        self.id = id
        self.airingAt = airingAt
        self.episode = episode
        self.media = media
    }
}

public struct AiringPage: Codable, Sendable {
    public var pageInfo: PageInfo?
    public var airingSchedules: [AiringSchedule]
}

public struct AiringResponse: Codable, Sendable {
    public var Page: AiringPage
}

public struct ListsResponse: Codable, Sendable {
    public var anime: MediaListCollection?
    public var manga: MediaListCollection?
}

public struct ViewerResponse: Codable, Sendable {
    public var Viewer: AniListUser
}

public struct CharacterResponse: Codable, Sendable {
    public var Character: Character
}

public struct StaffResponse: Codable, Sendable {
    public var Staff: Staff
}

public struct StudioDetail: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isAnimationStudio: Bool?
    public var media: MediaNodeConnection?
}

public struct StudioResponse: Codable, Sendable {
    public var Studio: StudioDetail
}

public struct TagDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var category: String?
    public var isAdult: Bool?
}

public struct TaxonomyResponse: Codable, Sendable {
    public var MediaTagCollection: [TagDefinition]
    public var GenreCollection: [String]
}

public struct UserSearchPage: Codable, Sendable {
    public var users: [AniListUser]
}

public struct UserSearchResponse: Codable, Sendable {
    public var Page: UserSearchPage
}

public struct SavedEntry: Codable, Sendable {
    public var id: Int
    public var mediaId: Int
    public var status: MediaListStatus?
    public var progress: Int?
    public var progressVolumes: Int?
    public var score: Double?
    public var notes: String?
}

public struct SaveEntryResponse: Codable, Sendable {
    public var SaveMediaListEntry: SavedEntry
}

public struct DeletedResponse: Codable, Sendable {
    public struct Deleted: Codable, Sendable { public var deleted: Bool? }
    public var DeleteMediaListEntry: Deleted
}

public struct ListActivity: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var status: String?
    public var progress: String?
    public var createdAt: Int
    public var media: Media?
    /// Only present in feeds that mix several people.
    public var user: AniListUser?

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }

    /// "watched episode 4 - 6" style progress → number of units covered.
    public var unitsCovered: Int {
        guard let progress else { return 0 }
        let numbers = progress.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if numbers.count >= 2 { return max(1, numbers[1] - numbers[0] + 1) }
        return numbers.isEmpty ? 0 : 1
    }
}

public struct ActivityPage: Codable, Sendable {
    public var pageInfo: PageInfo?
    public var activities: [ListActivity]
}

public struct ActivityResponse: Codable, Sendable {
    public var Page: ActivityPage
}

public enum Queries {
    // MARK: Discovery

    public static func home(now: Date = Date()) -> GraphQLOperation<HomeFeed> {
        let current = MediaSeason.of(now)
        let next = current.season.next(year: current.year)
        var v = Variables()
        v.set("season", current.season)
        v.set("year", current.year)
        v.set("nextSeason", next.season)
        v.set("nextYear", next.year)
        let query = """
        query Home($season: MediaSeason, $year: Int, $nextSeason: MediaSeason, $nextYear: Int) {
          trending: Page(perPage: 16) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { ...card } }
          season: Page(perPage: 16) { media(type: ANIME, season: $season, seasonYear: $year, sort: POPULARITY_DESC, isAdult: false) { ...card } }
          manga: Page(perPage: 16) { media(type: MANGA, sort: TRENDING_DESC, isAdult: false) { ...card } }
          top: Page(perPage: 16) { media(type: ANIME, sort: SCORE_DESC, isAdult: false) { ...card } }
          upcoming: Page(perPage: 12) { media(type: ANIME, season: $nextSeason, seasonYear: $nextYear, sort: POPULARITY_DESC, isAdult: false) { ...card } }
        }
        """ + Fragments.card
        return GraphQLOperation(name: "home", query: query, variables: v, ttl: 60 * 30)
    }

    public static func detail(id: Int) -> GraphQLOperation<MediaResponse> {
        var v = Variables()
        v.set("id", id)
        let query = """
        query Detail($id: Int) {
          Media(id: $id) {
            ...card
            description(asHtml: false) synonyms hashtag siteUrl
            trailer { id site thumbnail }
            relations { edges { relationType(version: 2) node { ...card } } }
            characters(sort: [ROLE, RELEVANCE, ID], perPage: 18) { edges { role node { id name { full native } image { large } description gender age } voiceActors(language: JAPANESE, sort: RELEVANCE) { id name { full } image { medium } } } }
            staff(sort: RELEVANCE, perPage: 12) { edges { role node { id name { full native } image { large } primaryOccupations } } }
            recommendations(perPage: 14, sort: RATING_DESC) { nodes { rating mediaRecommendation { ...card } } }
            externalLinks { id url site type language color icon notes isDisabled }
            streamingEpisodes { title thumbnail url site }
            rankings { rank type context allTime year season }
            stats { scoreDistribution { score amount } statusDistribution { status amount } }
            airingSchedule(notYetAired: true, perPage: 6) { nodes { airingAt episode } }
          }
        }
        """ + Fragments.card
        return GraphQLOperation(name: "detail", query: query, variables: v, ttl: 60 * 60 * 6)
    }

    /// Several titles (with their relations) in one request — used to walk franchises.
    public static func relationsBatch(ids: [Int]) -> GraphQLOperation<MediaBatchResponse> {
        var v = Variables()
        v.set("ids", ids.sorted())
        let query = """
        query Relations($ids: [Int]) {
          Page(perPage: 50) {
            media(id_in: $ids) {
              ...lite
              relations { edges { relationType(version: 2) node { ...lite } } }
            }
          }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "relations", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    public static func cards(ids: [Int]) -> GraphQLOperation<MediaBatchResponse> {
        var v = Variables()
        v.set("ids", ids.sorted())
        let query = """
        query Cards($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids) { ...card } } }
        """ + Fragments.card
        return GraphQLOperation(name: "cards", query: query, variables: v, ttl: 60 * 60 * 12)
    }

    public static func search(_ q: DiscoveryQuery, page: Int = 1) -> GraphQLOperation<PageResponse> {
        var v = Variables()
        v.set("page", page)
        v.set("search", q.text)
        v.set("type", q.type)
        v.set("genreIn", q.genresInclude)
        v.set("genreNotIn", q.genresExclude)
        v.set("tagIn", q.tagsInclude)
        v.set("tagNotIn", q.tagsExclude)
        v.set("formatIn", q.formats)
        v.set("episodesLesser", q.maxEpisodes.map { $0 + 1 })
        v.set("episodesGreater", q.minEpisodes.map { $0 - 1 })
        v.set("durationLesser", q.maxEpisodeMinutes.map { $0 + 1 })
        v.set("startGreater", q.yearFrom.map { $0 * 10_000 })
        v.set("startLesser", q.yearTo.map { ($0 + 1) * 10_000 })
        v.set("scoreGreater", q.minScore.map { $0 - 1 })
        v.set("popularityLesser", q.maxPopularity)
        v.set("popularityGreater", q.minPopularity)
        v.set("status", q.status)
        v.set("country", q.country)
        v.set("sort", [q.effectiveSort.rawValue])
        let query = """
        query Search($page: Int, $search: String, $type: MediaType, $genreIn: [String], $genreNotIn: [String], $tagIn: [String], $tagNotIn: [String], $formatIn: [MediaFormat], $episodesLesser: Int, $episodesGreater: Int, $durationLesser: Int, $startGreater: FuzzyDateInt, $startLesser: FuzzyDateInt, $scoreGreater: Int, $popularityLesser: Int, $popularityGreater: Int, $status: MediaStatus, $country: CountryCode, $sort: [MediaSort]) {
          Page(page: $page, perPage: 30) {
            pageInfo { hasNextPage currentPage }
            media(search: $search, type: $type, genre_in: $genreIn, genre_not_in: $genreNotIn, tag_in: $tagIn, tag_not_in: $tagNotIn, format_in: $formatIn, episodes_lesser: $episodesLesser, episodes_greater: $episodesGreater, duration_lesser: $durationLesser, startDate_greater: $startGreater, startDate_lesser: $startLesser, averageScore_greater: $scoreGreater, popularity_lesser: $popularityLesser, popularity_greater: $popularityGreater, status: $status, countryOfOrigin: $country, isAdult: false, sort: $sort) { ...card }
          }
        }
        """ + Fragments.card
        return GraphQLOperation(name: "search", query: query, variables: v, ttl: 60 * 60)
    }

    public static func airing(start: Date, end: Date, page: Int) -> GraphQLOperation<AiringResponse> {
        var v = Variables()
        v.set("page", page)
        v.set("start", Int(start.timeIntervalSince1970))
        v.set("end", Int(end.timeIntervalSince1970))
        let query = """
        query Airing($page: Int, $start: Int, $end: Int) {
          Page(page: $page, perPage: 50) {
            pageInfo { hasNextPage }
            airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
              id airingAt episode
              media { id type format status episodes duration isAdult popularity genres averageScore countryOfOrigin title { romaji english native userPreferred } coverImage { large color } nextAiringEpisode { airingAt episode timeUntilAiring } }
            }
          }
        }
        """
        return GraphQLOperation(name: "airing", query: query, variables: v, ttl: 60 * 60 * 3)
    }

    public static func taxonomy() -> GraphQLOperation<TaxonomyResponse> {
        let query = "query Taxonomy { MediaTagCollection { name description category isAdult } GenreCollection }"
        return GraphQLOperation(name: "taxonomy", query: query, ttl: 60 * 60 * 24 * 7)
    }

    // MARK: Atlas expansion

    public static func character(id: Int) -> GraphQLOperation<CharacterResponse> {
        var v = Variables()
        v.set("id", id)
        let query = """
        query CharacterDetail($id: Int) {
          Character(id: $id) {
            id name { full native } image { large } description gender age favourites
            media(perPage: 14, sort: POPULARITY_DESC) { edges { characterRole node { ...lite } } }
          }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "character", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    public static func staff(id: Int) -> GraphQLOperation<StaffResponse> {
        var v = Variables()
        v.set("id", id)
        let query = """
        query StaffDetail($id: Int) {
          Staff(id: $id) {
            id name { full native } image { large } primaryOccupations description
            staffMedia(perPage: 16, sort: POPULARITY_DESC) { nodes { ...lite } }
          }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "staff", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    public static func studio(id: Int) -> GraphQLOperation<StudioResponse> {
        var v = Variables()
        v.set("id", id)
        let query = """
        query StudioDetail($id: Int) {
          Studio(id: $id) {
            id name isAnimationStudio
            media(perPage: 18, sort: POPULARITY_DESC, isMain: true) { nodes { ...lite } }
          }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "studio", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    public static func byTag(_ tag: String, type: MediaType = .anime) -> GraphQLOperation<PageResponse> {
        var v = Variables()
        v.set("tag", [tag])
        v.set("type", type)
        let query = """
        query ByTag($tag: [String], $type: MediaType) {
          Page(perPage: 16) { pageInfo { hasNextPage } media(tag_in: $tag, type: $type, isAdult: false, sort: POPULARITY_DESC) { ...lite } }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "bytag", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    public static func byGenre(_ genre: String, type: MediaType = .anime) -> GraphQLOperation<PageResponse> {
        var v = Variables()
        v.set("genre", [genre])
        v.set("type", type)
        let query = """
        query ByGenre($genre: [String], $type: MediaType) {
          Page(perPage: 16) { pageInfo { hasNextPage } media(genre_in: $genre, type: $type, isAdult: false, sort: POPULARITY_DESC) { ...lite } }
        }
        """ + Fragments.lite
        return GraphQLOperation(name: "bygenre", query: query, variables: v, ttl: 60 * 60 * 24)
    }

    // MARK: Users and lists

    static let listEntryFields = """
    lists { name isCustomList status entries { id mediaId status score(format: POINT_100) progress progressVolumes repeat notes private updatedAt startedAt { year month day } completedAt { year month day } media { ...card } } }
    """

    public static func lists(userName: String) -> GraphQLOperation<ListsResponse> {
        var v = Variables()
        v.set("name", userName)
        let query = """
        query Lists($name: String) {
          anime: MediaListCollection(userName: $name, type: ANIME, sort: UPDATED_TIME_DESC) { user { id name avatar { large medium } bannerImage mediaListOptions { scoreFormat } } \(listEntryFields) }
          manga: MediaListCollection(userName: $name, type: MANGA, sort: UPDATED_TIME_DESC) { \(listEntryFields) }
        }
        """ + Fragments.card
        return GraphQLOperation(name: "lists", query: query, variables: v, ttl: 60 * 10)
    }

    public static func myLists(userId: Int) -> GraphQLOperation<ListsResponse> {
        var v = Variables()
        v.set("uid", userId)
        let query = """
        query MyLists($uid: Int) {
          anime: MediaListCollection(userId: $uid, type: ANIME, sort: UPDATED_TIME_DESC) { user { id name avatar { large medium } bannerImage mediaListOptions { scoreFormat } } \(listEntryFields) }
          manga: MediaListCollection(userId: $uid, type: MANGA, sort: UPDATED_TIME_DESC) { \(listEntryFields) }
        }
        """ + Fragments.card
        return GraphQLOperation(name: "mylists", query: query, variables: v, ttl: 60 * 5, requiresAuth: true)
    }

    public static func viewer() -> GraphQLOperation<ViewerResponse> {
        let query = """
        query Viewer { Viewer { id name avatar { large medium } bannerImage mediaListOptions { scoreFormat } options { displayAdultContent titleLanguage } } }
        """
        return GraphQLOperation(name: "viewer", query: query, ttl: 60 * 60, requiresAuth: true)
    }

    public static func searchUsers(_ text: String) -> GraphQLOperation<UserSearchResponse> {
        var v = Variables()
        v.set("q", text)
        let query = """
        query Users($q: String) { Page(perPage: 10) { users(search: $q, sort: SEARCH_MATCH) { id name avatar { large medium } } } }
        """
        return GraphQLOperation(name: "users", query: query, variables: v, ttl: 60 * 60)
    }

    public static func activities(userId: Int, since: Date, page: Int) -> GraphQLOperation<ActivityResponse> {
        var v = Variables()
        v.set("uid", userId)
        v.set("since", Int(since.timeIntervalSince1970))
        v.set("page", page)
        let query = """
        query Activity($uid: Int, $since: Int, $page: Int) {
          Page(page: $page, perPage: 50) {
            pageInfo { hasNextPage }
            activities(userId: $uid, type: MEDIA_LIST, createdAt_greater: $since, sort: ID_DESC) {
              ... on ListActivity { id status progress createdAt media { id type format episodes chapters duration genres title { romaji english userPreferred } coverImage { large color } } }
            }
          }
        }
        """
        return GraphQLOperation(name: "activity", query: query, variables: v, ttl: 60 * 60 * 6)
    }

    // MARK: Mutations

    public static func saveEntry(_ change: EntryChange) -> GraphQLOperation<SaveEntryResponse> {
        var v = Variables()
        v.set("mediaId", change.mediaId)
        v.set("status", change.status)
        v.set("progress", change.progress)
        v.set("progressVolumes", change.progressVolumes)
        v.set("scoreRaw", change.score.map { Int($0.rounded()) })
        v.set("notes", change.notes)
        v.set("repeat", change.repeatCount)
        var started: [String: JSONValue] = [:]
        if let s = change.startedAt, let y = s.year {
            started = ["year": .int(y)]
            if let m = s.month { started["month"] = .int(m) }
            if let d = s.day { started["day"] = .int(d) }
        }
        var completed: [String: JSONValue] = [:]
        if let c = change.completedAt, let y = c.year {
            completed = ["year": .int(y)]
            if let m = c.month { completed["month"] = .int(m) }
            if let d = c.day { completed["day"] = .int(d) }
        }
        var values = v.values
        if !started.isEmpty { values["startedAt"] = .object(started) }
        if !completed.isEmpty { values["completedAt"] = .object(completed) }
        let query = """
        mutation Save($mediaId: Int, $status: MediaListStatus, $progress: Int, $progressVolumes: Int, $scoreRaw: Int, $notes: String, $repeat: Int, $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) {
          SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, progressVolumes: $progressVolumes, scoreRaw: $scoreRaw, notes: $notes, repeat: $repeat, startedAt: $startedAt, completedAt: $completedAt) {
            id mediaId status progress progressVolumes score(format: POINT_100) notes
          }
        }
        """
        var op = GraphQLOperation<SaveEntryResponse>(name: "save", query: query, ttl: 0, isMutation: true, requiresAuth: true)
        op.variables = values
        return op
    }

    public static func deleteEntry(remoteId: Int) -> GraphQLOperation<DeletedResponse> {
        var v = Variables()
        v.set("id", remoteId)
        let query = "mutation Delete($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }"
        return GraphQLOperation(name: "delete", query: query, variables: v, ttl: 0, isMutation: true, requiresAuth: true)
    }
}
