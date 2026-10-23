import SwiftUI
import Observation
import AniliteKit

/// The app's single source of truth. Owns the AniList client, the offline-first library
/// and mutation queue, local-only collections (journal, shelves, clubs) and everything
/// derived from them (Taste DNA, recommendations, achievements).
@MainActor
@Observable
final class AppModel {
    // MARK: Services
    @ObservationIgnored let client: AniListClient
    @ObservationIgnored let store: PersistentStore
    @ObservationIgnored let auth = AuthService()
    let network = NetworkMonitor()
    let router = Router()
    let effects: EffectsBudget

    // MARK: Persistent state
    var settings: AppSettings { didSet { settingsChanged(from: oldValue) } }
    private(set) var account: AccountMode
    private(set) var library: Library = .empty
    private(set) var queue = MutationQueue()
    private(set) var journal: [JournalEntry] = []
    private(set) var shelves: [Shelf] = []
    private(set) var clubs: [Club] = []
    private(set) var savedLists: [SharedList] = []
    private(set) var friends: [TasteFingerprint] = []
    // People you follow on AniList, and people whose taste overlaps yours. Not persisted.
    private(set) var following: [AniListUser] = []
    private(set) var followingState: LoadState = .idle
    private(set) var suggestions: [PersonSuggestion] = []
    private(set) var suggestionsState: LoadState = .idle
    private(set) var unlockedSpoilers: Set<Int> = []
    private(set) var recentSearches: [String] = []

    // MARK: Derived
    private(set) var dna: TasteDNA = .empty
    private(set) var forYou: [ScoredMedia] = []
    private(set) var revivals: [ScoredMedia] = []
    private(set) var achievements: [Achievement] = []

    // MARK: Remote
    private(set) var home: HomeFeed?
    private(set) var homeState: LoadState = .idle
    private(set) var syncState: LoadState = .idle
    private(set) var activities: [ListActivity] = []
    private(set) var pace: PaceEstimate = .fallback
    private(set) var isFlushing = false
    private(set) var sessionExpired = false
    private(set) var isLibraryLoaded = false
    var banner: String?

    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var communityCandidates: [Media] = []
    @ObservationIgnored private var communitySignals: [Int: CommunitySignal] = [:]
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var deriveTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    enum Keys {
        static let settings = "settings"
        static let account = "account"
        static let library = "library"
        static let queue = "queue"
        static let journal = "journal"
        static let shelves = "shelves"
        static let clubs = "clubs"
        static let savedLists = "saved-lists"
        static let friends = "friends"
        static let unlocked = "unlocked-spoilers"
        static let recents = "recent-searches"
    }

    init(effects: EffectsBudget, store: PersistentStore = .appSupport(), cacheDirectory: URL? = ResponseCache.defaultDirectory()) {
        self.effects = effects
        self.store = store
        self.client = AniListClient(cache: ResponseCache(directory: cacheDirectory))
        // Tiny files: read synchronously so the first frame already knows onboarding vs. app.
        let loadedSettings = store.load(AppSettings.self, key: Keys.settings) ?? AppSettings()
        self.settings = loadedSettings
        self.account = store.load(AccountMode.self, key: Keys.account) ?? .undecided
        Haptics.enabled = loadedSettings.haptics
        effects.preference = Self.level(for: loadedSettings.effects)
    }

    // MARK: - Derived accessors

    var spoilerPolicy: SpoilerPolicy { SpoilerPolicy(level: settings.spoilerLevel, unlockedMediaIds: unlockedSpoilers) }
    var canEdit: Bool { account == .local || (account.isConnected && !sessionExpired) }
    var isOffline: Bool { !network.isOnline }
    var scoreFormat: ScoreFormat { library.user?.mediaListOptions?.scoreFormat ?? .point10Decimal }
    var region: String? { settings.region }
    var needsOnboarding: Bool { account == .undecided || !settings.hasOnboarded }
    var myFingerprint: TasteFingerprint { TasteFingerprint(name: account.displayName ?? "Me", dna: dna) }

    func title(_ media: Media) -> String { media.displayTitle(settings.titleLanguage) }
    func entry(_ mediaId: Int) -> LibraryEntry? { library.entry(for: mediaId) }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        let store = self.store
        let snapshot = await Task.detached(priority: .userInitiated) { Snapshot.load(from: store) }.value
        apply(snapshot)
        if account.isConnected, let token = Keychain.read(account: AuthService.tokenAccount) {
            await client.setToken(token)
        } else if account.isConnected {
            sessionExpired = true
        }
        network.start { [weak self] in
            Task { await self?.reconnected() }
        }
        NotificationRelay.shared.attach { [weak self] mediaId in
            self?.router.push(.media(mediaId), on: .library)
        }
        scheduleDerive()
        async let homeTask: Void = refreshHome()
        async let syncTask: Void = syncLibrary()
        _ = await (homeTask, syncTask)
        await flush()
        await refreshCommunitySignals()
        await refreshActivities()
        await rescheduleReminders()
    }

    private func reconnected() async {
        await flush()
        if homeState.errorMessage != nil || home == nil { await refreshHome() }
        await syncLibrary()
    }

    func refreshAll() async {
        async let homeTask: Void = refreshHome(force: true)
        async let syncTask: Void = syncLibrary(force: true)
        _ = await (homeTask, syncTask)
        await flush()
        await refreshActivities()
    }

    func backgroundRefresh() async {
        await syncLibrary(force: true)
        await flush()
        await rescheduleReminders()
        AiringReminders.scheduleBackgroundRefresh()
    }

    // MARK: - Home feed

    func refreshHome(force: Bool = false) async {
        if home == nil { homeState = .loading }
        do {
            if force {
                home = try await client.fetch(Queries.home(), policy: .networkFirst)
            } else {
                for try await fetched in client.stream(Queries.home()) {
                    home = fetched.value
                }
            }
            homeState = .loaded
        } catch {
            let message = Self.message(for: error)
            if home == nil {
                homeState = .failed(message)
            } else {
                homeState = .loaded
                showBanner(message)
            }
        }
        scheduleDerive()
    }

    // MARK: - Account

    func signIn() async {
        do {
            let token = try await auth.authorize()
            Keychain.save(token, account: AuthService.tokenAccount)
            await client.setToken(token)
            let viewer = try await client.fetch(Queries.viewer(), policy: .networkOnly).Viewer
            let previous = account
            let localLibrary = library
            if case .connected(let oldId, _) = previous, oldId != viewer.id {
                queue = MutationQueue()
            }
            if case .publicProfile = previous { queue = MutationQueue() }
            account = .connected(userId: viewer.id, name: viewer.name)
            sessionExpired = false
            settings.hasOnboarded = true
            persist(account, key: Keys.account)
            await syncLibrary(force: true)
            if previous == .local { migrateLocalEntries(localLibrary) }
            await flush()
            await refreshActivities()
            Haptics.success()
        } catch AuthError.cancelled {
            return
        } catch {
            if !account.isConnected, await client.hasToken {
                await client.setToken(nil)
                Keychain.delete(account: AuthService.tokenAccount)
            }
            showBanner(Self.message(for: error))
            Haptics.error()
        }
    }

    /// Follows a public AniList profile without signing in. Throws so onboarding can show
    /// the error inline (private profile, typo, offline).
    func usePublicProfile(_ rawName: String) async throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AniListError.notFound }
        let response = try await client.fetch(Queries.lists(userName: name), policy: .networkOnly)
        let user = response.anime?.user
        account = .publicProfile(name: user?.name ?? name)
        library = Library.from(anime: response.anime, manga: response.manga, user: user, isReadOnly: true)
        queue = MutationQueue()
        settings.hasOnboarded = true
        persist(account, key: Keys.account)
        persistQueue()
        libraryChanged()
        Task { await refreshActivities() }
    }

    func useLocalLibrary() {
        if account != .local {
            library = Library(user: nil, entries: account.isConnected ? library.entries : [:], lastSynced: nil, isReadOnly: false)
            queue = MutationQueue()
        }
        account = .local
        settings.hasOnboarded = true
        persist(account, key: Keys.account)
        persistQueue()
        libraryChanged()
    }

    func signOut() async {
        Keychain.delete(account: AuthService.tokenAccount)
        await client.setToken(nil)
        await client.clearCache()
        account = .undecided
        library = .empty
        queue = MutationQueue()
        activities = []
        pace = .fallback
        sessionExpired = false
        settings.hasOnboarded = false
        persist(account, key: Keys.account)
        persistQueue()
        libraryChanged()
        await AiringReminders.reschedule(library: .empty, language: settings.titleLanguage, leadMinutes: 0, enabled: false)
    }

    private func handleExpiredSession() {
        sessionExpired = true
        Keychain.delete(account: AuthService.tokenAccount)
        Task { await client.setToken(nil) }
        showBanner(AniListError.unauthorized.errorDescription ?? "Please sign in again.")
    }

    /// When a local library connects to AniList, queue its entries so nothing is lost.
    private func migrateLocalEntries(_ local: Library) {
        var queued = 0
        for entry in local.all where library.entry(for: entry.mediaId) == nil {
            let change = EntryChange(mediaId: entry.mediaId, status: entry.status, progress: entry.progress,
                                     progressVolumes: entry.progressVolumes, score: entry.isScored ? entry.score : nil,
                                     notes: entry.notes.isEmpty ? nil : entry.notes, repeatCount: entry.repeatCount,
                                     startedAt: entry.startedAt, completedAt: entry.completedAt)
            LibraryReducer.apply(change, media: entry.media, to: &library)
            queue.enqueue(.save(change))
            queued += 1
        }
        if queued > 0 {
            persistQueue()
            libraryChanged()
            showBanner("Uploading \(queued) titles from this device to AniList.")
        }
    }

    // MARK: - Library sync

    func syncLibrary(force: Bool = false) async {
        let op: GraphQLOperation<ListsResponse>
        switch account {
        case .connected(let id, _):
            guard !sessionExpired else { return }
            op = Queries.myLists(userId: id)
        case .publicProfile(let name):
            op = Queries.lists(userName: name)
        case .local, .undecided:
            return
        }
        syncState = .loading
        do {
            let response = try await client.fetch(op, policy: force ? .networkOnly : .networkFirst)
            let user = response.anime?.user ?? library.user
            let server = Library.from(anime: response.anime, manga: response.manga, user: user, isReadOnly: !account.isConnected)
            library = LibraryReducer.rebase(server: server, pending: queue)
            syncState = .loaded
            libraryChanged()
        } catch AniListError.unauthorized {
            syncState = .failed(AniListError.unauthorized.errorDescription ?? "")
            handleExpiredSession()
        } catch {
            let message = Self.message(for: error)
            syncState = .failed(message)
            if (error as? AniListError) != .offline { showBanner(message) }
        }
    }

    /// Sends queued edits to AniList in order. Retryable failures stop the loop (it resumes
    /// on reconnect); permanent ones are dropped so one bad edit can't jam the queue.
    func flush() async {
        guard account.isConnected, !sessionExpired, !isFlushing, network.isOnline, !queue.isEmpty else { return }
        guard await client.hasToken else { return }
        isFlushing = true
        defer { isFlushing = false }
        var sentAny = false
        drain: while let next = queue.first {
            do {
                switch next {
                case .save(let change):
                    let saved = try await client.fetch(Queries.saveEntry(change), policy: .networkOnly).SaveMediaListEntry
                    if var entry = library.entries[change.mediaId] {
                        entry.remoteId = saved.id
                        library.entries[change.mediaId] = entry
                    }
                case .delete(_, let remoteId):
                    _ = try await client.fetch(Queries.deleteEntry(remoteId: remoteId), policy: .networkOnly)
                }
                // If the user edited the same title while the request was in flight, the
                // queued item was merged and must be sent again.
                if queue.first == next { queue.removeFirst() }
                sentAny = true
            } catch let error as AniListError {
                if error == .unauthorized {
                    handleExpiredSession()
                    break drain
                }
                if error.isRetryable { break drain }
                if queue.first == next { queue.removeFirst() }
                showBanner("A change couldn't sync: \(error.errorDescription ?? "unknown error")")
            } catch {
                break drain
            }
        }
        persistQueue()
        if sentAny {
            if case .connected(let id, _) = account { await client.invalidate(Queries.myLists(userId: id)) }
            persistLibrary()
        }
    }

    // MARK: - Editing

    /// Applies an edit locally right away, then queues it for AniList.
    @discardableResult
    func save(_ change: EntryChange, media: Media) -> Bool {
        guard canEdit else {
            showBanner(sessionExpired ? "Sign in again to edit your AniList." : "This is a read-only profile. Connect AniList or use a local library to track.")
            Haptics.warning()
            return false
        }
        let before = library.entry(for: media.id)
        LibraryReducer.apply(change, media: media, to: &library)
        if account.isConnected {
            queue.enqueue(.save(change))
            persistQueue()
            Task { await flush() }
        }
        libraryChanged()
        let after = library.entry(for: media.id)
        if after?.status == .completed && before?.status != .completed {
            Haptics.success()
        } else {
            Haptics.tap(.soft)
        }
        if before == nil || after?.status != before?.status {
            Task { await rescheduleReminders() }
        }
        return true
    }

    func increment(_ entry: LibraryEntry, by amount: Int = 1) {
        save(LibraryReducer.increment(entry, by: amount), media: entry.media)
    }

    func add(_ media: Media, status: MediaListStatus = .planning) {
        save(EntryChange(mediaId: media.id, status: status), media: media)
    }

    func remove(mediaId: Int) {
        guard canEdit, let entry = library.entry(for: mediaId) else { return }
        if account.isConnected {
            if let remote = entry.remoteId {
                queue.enqueue(.delete(mediaId: mediaId, remoteId: remote))
            } else {
                queue.cancelLocalOnly(mediaId: mediaId)
            }
            persistQueue()
            Task { await flush() }
        }
        LibraryReducer.remove(mediaId: mediaId, from: &library)
        libraryChanged()
        Haptics.tap(.rigid)
    }

    // MARK: - Activity & pace

    func refreshActivities() async {
        guard let userId = library.user?.id else { return }
        let since = Calendar.current.date(byAdding: .day, value: -400, to: Date()) ?? Date()
        var all: [ListActivity] = []
        for page in 1...4 {
            do {
                let response = try await client.fetch(Queries.activities(userId: userId, since: since, page: page), policy: .cacheFirst)
                all.append(contentsOf: response.Page.activities)
                if response.Page.pageInfo?.hasNextPage != true { break }
            } catch {
                break
            }
        }
        guard !all.isEmpty else { return }
        activities = all
        pace = PaceEstimate.from(activities: all)
    }

    // MARK: - Recommendations

    /// Pulls AniList community recommendations for the user's recent favourites so
    /// "For you" can explain picks as "fans of X also loved this".
    func refreshCommunitySignals() async {
        let loved = library.all
            .filter { ($0.status == .completed || $0.status == .repeating) && (!$0.isScored || $0.score >= 80) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(4)
        guard !loved.isEmpty else { return }
        var candidates: [Int: Media] = [:]
        var signals: [Int: CommunitySignal] = [:]
        for entry in loved {
            guard let detail = try? await client.fetch(Queries.detail(id: entry.mediaId), policy: .cacheFirst).Media else { continue }
            for rec in detail.recommendations?.nodes ?? [] {
                guard let media = rec.mediaRecommendation, let votes = rec.rating, votes > 0 else { continue }
                candidates[media.id] = media
                if votes > (signals[media.id]?.votes ?? 0) {
                    signals[media.id] = CommunitySignal(fromTitle: title(entry.media), votes: votes)
                }
            }
        }
        communityCandidates = Array(candidates.values)
        communitySignals = signals
        scheduleDerive()
    }

    private var recommendationCandidates: [Media] {
        var seen = Set<Int>()
        var result: [Media] = []
        let pools: [[Media]] = [communityCandidates, home?.trending.media ?? [], home?.season.media ?? [],
                                home?.top.media ?? [], home?.manga.media ?? []]
        for pool in pools {
            for media in pool where seen.insert(media.id).inserted {
                result.append(media)
            }
        }
        return result
    }

    private struct Derived: Sendable {
        var dna: TasteDNA
        var forYou: [ScoredMedia]
        var revivals: [ScoredMedia]
        var achievements: [Achievement]
    }

    /// Recomputes Taste DNA and everything that depends on it off the main thread,
    /// coalescing bursts of edits.
    private func scheduleDerive() {
        deriveTask?.cancel()
        let library = self.library
        let journal = self.journal
        let candidates = recommendationCandidates
        let community = communitySignals
        let policy = spoilerPolicy
        deriveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let derived = await Task.detached(priority: .userInitiated) { () -> Derived in
                let dna = TasteDNA.build(from: library.all)
                return Derived(
                    dna: dna,
                    forYou: Recommender.rank(candidates: candidates, dna: dna, library: library, community: community, policy: policy, limit: 40),
                    revivals: Recommender.revivals(library: library, dna: dna),
                    achievements: Achievements.evaluate(library: library, journal: journal)
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            self.dna = derived.dna
            self.forYou = derived.forYou
            self.revivals = derived.revivals
            self.achievements = derived.achievements
        }
    }

    // MARK: - Local collections

    func unlockSpoilers(for mediaId: Int) {
        unlockedSpoilers.insert(mediaId)
        persist(unlockedSpoilers, key: Keys.unlocked)
        Haptics.tap(.medium)
    }

    func relockSpoilers(for mediaId: Int) {
        unlockedSpoilers.remove(mediaId)
        persist(unlockedSpoilers, key: Keys.unlocked)
    }

    func addJournal(_ entry: JournalEntry) {
        journal.insert(entry, at: 0)
        persist(journal, key: Keys.journal)
        scheduleDerive()
        Haptics.success()
    }

    func deleteJournal(_ id: UUID) {
        journal.removeAll { $0.id == id }
        persist(journal, key: Keys.journal)
        scheduleDerive()
    }

    var allShelves: [Shelf] { Shelf.builtIns + shelves }

    func shelf(_ id: UUID) -> Shelf? { allShelves.first { $0.id == id } }

    func createShelf(name: String, symbol: String, rule: SmartRule?) {
        shelves.append(Shelf(name: name, symbol: symbol, rule: rule))
        persist(shelves, key: Keys.shelves)
        Haptics.success()
    }

    func deleteShelf(_ id: UUID) {
        shelves.removeAll { $0.id == id }
        persist(shelves, key: Keys.shelves)
    }

    func toggle(_ mediaId: Int, onShelf id: UUID) {
        guard let index = shelves.firstIndex(where: { $0.id == id }) else { return }
        if let i = shelves[index].mediaIds.firstIndex(of: mediaId) {
            shelves[index].mediaIds.remove(at: i)
        } else {
            shelves[index].mediaIds.insert(mediaId, at: 0)
        }
        persist(shelves, key: Keys.shelves)
        Haptics.tick()
    }

    func saveClub(_ club: Club) {
        clubs.removeAll { $0.id == club.id }
        clubs.insert(club, at: 0)
        persist(clubs, key: Keys.clubs)
        Haptics.success()
    }

    func leaveClub(_ id: String) {
        clubs.removeAll { $0.id == id }
        persist(clubs, key: Keys.clubs)
    }

    func saveSharedList(_ list: SharedList) {
        savedLists.removeAll { $0.id == list.id }
        savedLists.insert(list, at: 0)
        persist(savedLists, key: Keys.savedLists)
        Haptics.success()
    }

    func removeSharedList(_ id: String) {
        savedLists.removeAll { $0.id == id }
        persist(savedLists, key: Keys.savedLists)
    }

    func addFriend(_ fingerprint: TasteFingerprint) {
        friends.removeAll { $0.name == fingerprint.name }
        friends.insert(fingerprint, at: 0)
        persist(friends, key: Keys.friends)
    }

    func removeFriend(named name: String) {
        friends.removeAll { $0.name == name }
        persist(friends, key: Keys.friends)
    }

    func rememberSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        recentSearches = Array(recentSearches.prefix(12))
        persist(recentSearches, key: Keys.recents)
    }

    func clearRecentSearches() {
        recentSearches = []
        persist(recentSearches, key: Keys.recents)
    }

    // MARK: - People

    /// The AniList id behind the current library, when there is one.
    var viewerId: Int? {
        if case .connected(let id, _) = account { return id }
        return library.user?.id
    }

    var canFollow: Bool { account.isConnected && !sessionExpired }

    func isFollowing(_ name: String) -> Bool {
        following.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func isFriend(_ name: String) -> Bool {
        friends.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func refreshFollowing(force: Bool = false) async {
        guard let id = viewerId, followingState != .loading else { return }
        if followingState == .loaded && !force { return }
        followingState = .loading
        var all: [AniListUser] = []
        do {
            for page in 1...4 {
                let response = try await client.fetch(Queries.following(userId: id, page: page), policy: force ? .networkFirst : .cacheFirst)
                all.append(contentsOf: response.Page.people)
                if response.Page.pageInfo?.hasNextPage != true { break }
            }
            following = all
            followingState = .loaded
        } catch {
            followingState = .failed(AppModel.message(for: error))
        }
    }

    /// Follows or unfollows on AniList. Returns the new state, or nil if it failed.
    @discardableResult
    func toggleFollow(_ user: AniListUser) async -> Bool? {
        guard canFollow else {
            showBanner("Connect your AniList account to follow people.")
            return nil
        }
        let wasFollowing = isFollowing(user.name)
        // Optimistic: flip it now, put it back if AniList says no.
        if wasFollowing { following.removeAll { $0.id == user.id } } else { following.insert(user, at: 0) }
        do {
            let state = try await client.fetch(Queries.toggleFollow(userId: user.id), policy: .networkOnly).ToggleFollow
            let now = state.isFollowing ?? !wasFollowing
            following.removeAll { $0.id == user.id }
            if now { following.insert(user, at: 0) }
            await client.invalidate(Queries.userProfile(name: user.name))
            if let id = viewerId { await client.invalidate(Queries.following(userId: id)) }
            suggestions.removeAll { $0.user.id == user.id && now }
            Haptics.success()
            return now
        } catch {
            following.removeAll { $0.id == user.id }
            if wasFollowing { following.insert(user, at: 0) }
            showBanner(AppModel.message(for: error))
            Haptics.warning()
            return nil
        }
    }

    /// Finds people who reviewed, finished or are watching the titles you rated highest.
    func loadSuggestions(force: Bool = false) async {
        guard suggestionsState != .loading else { return }
        if suggestionsState == .loaded && !force { return }
        let seeds = PeopleFinder.seeds(from: library)
        guard !seeds.isEmpty else {
            suggestions = []
            suggestionsState = .failed("Score a few titles you loved and people with similar taste will show up here.")
            return
        }
        suggestionsState = .loading
        if viewerId != nil { await refreshFollowing() }
        var excluded = Set(following.map { $0.name.lowercased() })
        excluded.formUnion(friends.map { $0.name.lowercased() })
        if let me = account.displayName ?? library.user?.name { excluded.insert(me.lowercased()) }
        do {
            let signals = try await client.fetch(Queries.peopleSignals(mediaIds: seeds.map(\.id)), policy: force ? .networkFirst : .cacheFirst)
            suggestions = PeopleFinder.rank(signals: signals, seeds: seeds, excluding: excluded)
            suggestionsState = .loaded
        } catch {
            suggestionsState = .failed(AppModel.message(for: error))
        }
    }

    /// Builds a Taste DNA fingerprint from someone's public lists and keeps them as a friend.
    func addFriend(named name: String) async {
        do {
            let response = try await client.fetch(Queries.lists(userName: name), policy: .cacheFirst)
            let theirs = Library.from(anime: response.anime, manga: response.manga, user: response.anime?.user ?? response.manga?.user, isReadOnly: true)
            let display = theirs.user?.name ?? name
            addFriend(TasteFingerprint(name: display, dna: TasteDNA.build(from: theirs.all)))
            Haptics.success()
            showBanner("\(display) is now in your friends.")
        } catch {
            showBanner(AppModel.message(for: error))
            Haptics.warning()
        }
    }

    // MARK: - Deep links

    func handle(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .auth:
            break // Handled by ASWebAuthenticationSession.
        case .media(let id):
            router.push(.media(id), on: router.tab)
        case .sharedList(let list):
            router.sheet = .sharedList(list)
        case .club(let club):
            router.sheet = .joinClub(club)
        case .fingerprint(let fingerprint):
            router.sheet = .fingerprint(fingerprint)
        case .user(let name):
            router.push(.person(name), on: .you)
        }
    }

    // MARK: - Reminders & maintenance

    func rescheduleReminders() async {
        await AiringReminders.reschedule(library: library, language: settings.titleLanguage,
                                         leadMinutes: settings.reminderLeadMinutes, enabled: settings.airingReminders)
    }

    func clearCaches() async {
        await client.clearCache()
        await ImagePipeline.shared.clearMemory()
        await ImagePipeline.shared.clearDisk()
        showBanner("Caches cleared.")
    }

    func showBanner(_ message: String) {
        banner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return error.localizedDescription
    }

    // MARK: - Persistence

    private func settingsChanged(from old: AppSettings) {
        guard settings != old else { return }
        Haptics.enabled = settings.haptics
        effects.preference = Self.level(for: settings.effects)
        persist(settings, key: Keys.settings, debounce: 0.2)
        if settings.spoilerLevel != old.spoilerLevel { scheduleDerive() }
        if settings.airingReminders != old.airingReminders || settings.reminderLeadMinutes != old.reminderLeadMinutes
            || settings.titleLanguage != old.titleLanguage {
            Task { await rescheduleReminders() }
        }
    }

    static func level(for preference: EffectsPreference) -> EffectsBudget.Level {
        switch preference {
        case .cinematic: return .full
        case .balanced: return .calm
        case .minimal: return .still
        }
    }

    private func libraryChanged() {
        persistLibrary()
        scheduleDerive()
    }

    private func persistLibrary() { persist(library, key: Keys.library, debounce: 0.6) }
    private func persistQueue() { persist(queue, key: Keys.queue, debounce: 0) }

    private func persist<T: Encodable & Sendable>(_ value: T, key: String, debounce: Double = 0.3) {
        saveTasks[key]?.cancel()
        let store = self.store
        saveTasks[key] = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            try? store.save(value, key: key)
        }
    }

    private func apply(_ s: Snapshot) {
        if let library = s.library { self.library = library }
        if account == .local && library.isReadOnly {
            library = Library(user: nil, entries: library.entries, lastSynced: nil, isReadOnly: false)
        }
        queue = s.queue ?? MutationQueue()
        journal = s.journal ?? []
        shelves = s.shelves ?? []
        clubs = s.clubs ?? []
        savedLists = s.savedLists ?? []
        friends = s.friends ?? []
        unlockedSpoilers = s.unlocked ?? []
        recentSearches = s.recents ?? []
        isLibraryLoaded = true
    }

    private struct Snapshot: Sendable {
        var library: Library?
        var queue: MutationQueue?
        var journal: [JournalEntry]?
        var shelves: [Shelf]?
        var clubs: [Club]?
        var savedLists: [SharedList]?
        var friends: [TasteFingerprint]?
        var unlocked: Set<Int>?
        var recents: [String]?

        static func load(from store: PersistentStore) -> Snapshot {
            Snapshot(
                library: store.load(Library.self, key: Keys.library),
                queue: store.load(MutationQueue.self, key: Keys.queue),
                journal: store.load([JournalEntry].self, key: Keys.journal),
                shelves: store.load([Shelf].self, key: Keys.shelves),
                clubs: store.load([Club].self, key: Keys.clubs),
                savedLists: store.load([SharedList].self, key: Keys.savedLists),
                friends: store.load([TasteFingerprint].self, key: Keys.friends),
                unlocked: store.load(Set<Int>.self, key: Keys.unlocked),
                recents: store.load([String].self, key: Keys.recents)
            )
        }
    }
}
