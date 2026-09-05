import AppKit
import Foundation
import WatchCore
import SwiftUI

enum WatchRoute: Hashable {
    case story(String)
}

@MainActor
final class WatchAppModel: ObservableObject {
    private struct SeenURLRecord: Codable {
        let url: String
        let seenAt: Date
    }

    @Published var sources: [TrackedSource] = []
    @Published var bookmarkStatus = "Firefox bookmarks / tv"
    private let bookmarkSource = TrackedSource(id: FirefoxBookmarks.sourceID, url: "Firefox bookmarks / tv", name: "Firefox · tv")
    @Published var stories: [Story] = []
    @Published var isRefreshing = false
    @Published var refreshStatus: String?
    /// 0...1 across the whole refresh — pulling front pages, then fetching
    /// each story, then scoring the batch. Drives the bar on `RefreshScreen`,
    /// which is up for the entire run and needs something better to say than
    /// an indeterminate spinner.
    @Published var refreshProgress: Double = 0
    /// Set by the "Skip to the feed" button, cleared when the next refresh
    /// starts — one refresh being waved past shouldn't stop the curtain going
    /// up on the next one.
    @Published var hasSkippedRefreshScreen = false
    @Published var lastRefreshError: String?
    @Published var isShowingSettings = false
    @Published var path: [WatchRoute] = []

    typealias FeedMode = BookmarkFeedMode

    @Published var feedMode: FeedMode {
        didSet {
            UserDefaults.standard.set(feedMode.rawValue, forKey: Self.feedModeStorageKey)
        }
    }

    @Published var theme: ReaderTheme {
        didSet {
            UserDefaults.standard.set(theme.id, forKey: Self.themeStorageKey)
            AppIconTheming.apply(theme)
        }
    }

    /// Stories you've rated by hand, keyed by story id. Absent means you
    /// haven't touched it and the ranker's prediction stands. This is UI state
    /// for the current batch, not the training history itself — that's
    /// `voteHistory`, keyed on title words instead so it generalizes.
    @Published var ratingByStoryID: [String: Bool] = [:]

    /// Story id -> predicted-interest score. Recomputed after a refresh and
    /// after every vote, so voting visibly reshuffles the Feed tab right away.
    /// Empty until the ranker has enough votes to say anything.
    @Published private(set) var scoreByStoryID: [String: Double] = [:]

    private let sourceStore: SourceStore
    private let voteStore: VoteStore
    private let readStateStore: WatchStateStore
    private let articleCacheStore: ArticleCacheStore
    private let fetcher = ArticleFetcher()
    /// In-memory mirror of the on-disk article cache, capped at the same 100
    /// most-recent entries — refreshes hit this before ever loading a page,
    /// since the same front pages (and often the same stories) get pulled
    /// again on every refresh.
    private var articleCache: [String: Article] = [:]
    private var articleCacheFetchedAt: [String: Date] = [:]
    private var voteHistory: [VoteRecord] = []
    private var ranker: NaiveBayesRanker
    /// Stories that have been opened. Deliberately not training data — see
    /// `WatchState`. Feed uses it to drop a story once you've read it; All
    /// keeps every story and just dims the ones in here.
    @Published private(set) var readStoryIDs: Set<String> = []
    /// Recently read URLs are kept separately from the permanent read-state
    /// IDs. This is the cheap refresh-time filter: it stops a source that
    /// republishes the same item from putting it back in the queue, while the
    /// ten-day expiry keeps the file bounded and lets old stories return.
    private var seenURLAt: [String: Date] = [:]

    private static let themeStorageKey = "WatchTheme"
    private static let feedModeStorageKey = "WatchFeedMode"
    private static let seenURLLifetime: TimeInterval = 10 * 24 * 60 * 60

    init() {
        let store = FileSourceStore(fileURL: Self.sourcesFileURL())
        sourceStore = store
        let votes = FileVoteStore(fileURL: Self.votesFileURL())
        voteStore = votes
        let readState = FileWatchStateStore(fileURL: Self.readStateFileURL())
        readStateStore = readState
        let articleCacheFile = FileArticleCacheStore(fileURL: Self.articleCacheFileURL())
        articleCacheStore = articleCacheFile
        sources = [bookmarkSource]
        voteHistory = (try? votes.loadVotes()) ?? []
        ranker = NaiveBayesRanker(votes: voteHistory)
        readStoryIDs = Set((try? readState.loadState())?.readIDs ?? [])
        seenURLAt = (try? Self.loadSeenURLs()) ?? [:]
        let cachedEntries = (try? articleCacheFile.loadEntries()) ?? []
        for entry in cachedEntries {
            articleCache[entry.storyURL] = entry.article
            articleCacheFetchedAt[entry.storyURL] = entry.fetchedAt
        }
        self.theme = ReaderTheme.named(UserDefaults.standard.string(forKey: Self.themeStorageKey))
        if let stored = UserDefaults.standard.string(forKey: Self.feedModeStorageKey), let mode = FeedMode(rawValue: stored) {
            self.feedMode = mode
        } else {
            self.feedMode = .youtube
        }
        pruneSeenURLs(persist: true)
    }

    private static func sourcesFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Watch", isDirectory: true).appendingPathComponent("sources.json")
    }

    private static func votesFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Watch", isDirectory: true).appendingPathComponent("votes.json")
    }

    private static func readStateFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Watch", isDirectory: true).appendingPathComponent("readState.json")
    }

    private static func articleCacheFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Watch", isDirectory: true).appendingPathComponent("articleCache.json")
    }

    private static func seenURLsFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Watch", isDirectory: true).appendingPathComponent("seenURLs.json")
    }

    private static func loadSeenURLs() throws -> [String: Date] {
        let data = try Data(contentsOf: seenURLsFileURL())
        let records = try JSONDecoder().decode([SeenURLRecord].self, from: data)
        return records.reduce(into: [:]) { result, record in
            result[record.url] = record.seenAt
        }
    }

    private func persistSeenURLs() {
        let records = seenURLAt.map { SeenURLRecord(url: $0.key, seenAt: $0.value) }
            .sorted { $0.seenAt > $1.seenAt }
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        let fileURL = Self.seenURLsFileURL()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func pruneSeenURLs(now: Date = Date(), persist: Bool) {
        let cutoff = now.addingTimeInterval(-Self.seenURLLifetime)
        let before = seenURLAt.count
        seenURLAt = seenURLAt.filter { $0.value >= cutoff }
        if persist && seenURLAt.count != before {
            persistSeenURLs()
        }
    }

    private func seenURLKey(_ url: String) -> String {
        guard var components = URLComponents(string: url) else {
            return url
        }
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? url
    }

    private func isRecentlySeen(_ url: String, now: Date = Date()) -> Bool {
        guard let seenAt = seenURLAt[seenURLKey(url)] else {
            return false
        }
        return now.timeIntervalSince(seenAt) < Self.seenURLLifetime
    }

    private func markSeen(_ url: String) {
        pruneSeenURLs(persist: false)
        seenURLAt[seenURLKey(url)] = Date()
        persistSeenURLs()
    }

    private func unmarkSeen(_ url: String) {
        seenURLAt.removeValue(forKey: seenURLKey(url))
        persistSeenURLs()
    }

    private func persistArticleCache() {
        let entries = articleCache.compactMap { (url, article) -> ArticleCacheEntry? in
            ArticleCacheEntry(storyURL: url, article: article, fetchedAt: articleCacheFetchedAt[url] ?? Date())
        }
        try? articleCacheStore.saveEntries(entries)
    }

    private func cacheArticle(_ article: Article, for storyURL: String) {
        articleCache[storyURL] = article
        articleCacheFetchedAt[storyURL] = Date()
        persistArticleCache()
    }

    // MARK: - Read state

    func markRead(_ story: Story) {
        if readStoryIDs.insert(story.id).inserted {
            persistWatchState()
        }
        markSeen(story.storyURL)
    }

    func toggleRead(_ story: Story) {
        if !readStoryIDs.insert(story.id).inserted {
            readStoryIDs.remove(story.id)
            unmarkSeen(story.storyURL)
        } else {
            markSeen(story.storyURL)
        }
        persistWatchState()
    }

    func isRead(_ story: Story) -> Bool {
        readStoryIDs.contains(story.id)
    }

    private func persistWatchState() {
        try? readStateStore.saveState(WatchState(readIDs: Array(readStoryIDs)))
    }

    // MARK: - Feed ordering

    /// Both tabs use bookmark date. Ratings and watched state do not filter or reorder them.
    func visibleStories(from allStories: [Story]) -> [Story] {
        feedMode.stories(from: allStories)
    }

    /// Feed's ordering before read state is applied — used by `visibleStories`
    /// and, unfiltered by read, by `adjacentStory`. j/k on a permalink has to
    /// be able to step off a story that opening it just marked read, which the
    /// read filter would otherwise pull out from under the step.
    private func ratedCandidates(from allStories: [Story]) -> [Story] {
        guard feedMode == .youtube, !scoreByStoryID.isEmpty else {
            return allStories
        }
        return allStories.enumerated()
            .filter { isRated($0.element) }
            .sorted { lhs, rhs in
                let lhsScore = scoreByStoryID[lhs.element.id] ?? 0
                let rhsScore = scoreByStoryID[rhs.element.id] ?? 0
                // Fetch position breaks ties, so equally-scored stories hold
                // their order instead of the sort shuffling them arbitrarily.
                return (lhsScore, -Double(lhs.offset)) > (rhsScore, -Double(rhs.offset))
            }
            .map(\.element)
    }

    /// Scores are log-odds of "like" vs "dislike", so zero is the natural
    /// dividing line: above it the story's words look more like the ones you
    /// upvoted, below it more like the ones you downvoted.
    private static let feedScoreThreshold: Double = 0

    /// True when Feed is actively filtering rather than just passing All
    /// through — lets the homepage explain an empty Feed instead of showing
    /// the same "nothing fetched" message a failed refresh would.
    var isFeedRanked: Bool {
        feedMode == .youtube && !scoreByStoryID.isEmpty
    }

    // MARK: - Voting

    /// Records the vote for training, then immediately re-ranks whatever's
    /// currently on screen — voting should feel like it's shaping the feed
    /// right away, not just influencing some future refresh.
    /// Whether the bolt is lit for a story: your own rating if you've given
    /// one, otherwise the ranker's prediction. Untrained, everything is lit —
    /// with nothing learned yet there's no basis for dropping anything, and a
    /// feed that started out empty would be worse than one that starts full.
    func isRated(_ story: Story) -> Bool {
        if let rating = ratingByStoryID[story.id] {
            return rating
        }
        guard let score = scoreByStoryID[story.id] else {
            return true
        }
        return score > Self.feedScoreThreshold
    }

    func toggleRating(_ story: Story) {
        setRating(story, liked: !isRated(story))
    }

    /// Records the rating for training, then immediately re-scores whatever's
    /// on screen — rating should feel like it's shaping the feed right away,
    /// not just influencing some future refresh.
    func setRating(_ story: Story, liked: Bool) {
        // Any earlier rating of this story comes out first, so flipping the
        // bolt back and forth replaces the record instead of training the
        // model on both answers.
        voteHistory.removeAll { record in
            if let recordedID = record.storyID {
                return recordedID == story.id
            }
            return record.title == story.title && record.sourceName == story.sourceName
        }

        let excerpt = story.excerpt ?? articleCache[story.storyURL]?.bodyText
        voteHistory.append(
            VoteRecord(
                storyID: story.id,
                title: story.title,
                sourceName: story.sourceName,
                contentExcerpt: excerpt,
                isUpvote: liked
            )
        )
        ratingByStoryID[story.id] = liked

        try? voteStore.saveVotes(voteHistory)
        ranker = NaiveBayesRanker(votes: voteHistory)
        recomputeRanking()
        updatePermalinkOrder(afterRatingChangeFor: story)
    }

    /// Rating can immediately reorder or remove a story from Feed while its
    /// article is open. Keep that article as the navigation anchor, but use
    /// the newly ranked Feed order for the stories around it.
    private func updatePermalinkOrder(afterRatingChangeFor story: Story) {
        guard !permalinkStoryOrder.isEmpty,
              let oldIndex = permalinkStoryOrder.firstIndex(of: story.id) else {
            return
        }

        var updated = visibleStories(from: stories).filter { $0.id != story.id }
        let insertionIndex = min(oldIndex, updated.count)
        updated.insert(story, at: insertionIndex)
        permalinkStoryOrder = updated.map(\.id)
    }

    /// Predicted-interest position per story, which the Feed tab sorts by —
    /// the "algorithmic stream." Scored once here rather than inside a sort
    /// comparator, since each score tokenizes a title and an excerpt and a
    /// comparator would redo that work O(n log n) times per re-sort.
    ///
    /// Only populated once there's enough signal (a handful of votes in both
    /// directions); before that the feed keeps fetch order, because a ranker
    /// trained on 1-2 votes would just be reordering things randomly and
    /// calling it personalization. `stories` itself is deliberately left in
    /// fetch order either way — that's what the All tab shows.
    private func recomputeRanking() {
        guard ranker.isTrained else {
            scoreByStoryID = [:]
            return
        }
        scoreByStoryID = stories.reduce(into: [:]) { scores, story in
            scores[story.id] = ranker.score(title: story.title, sourceName: story.sourceName, excerpt: story.excerpt)
        }
    }

    // MARK: - Sources

    func addSource(urlString: String) {
        guard let normalized = normalizedSourceURL(urlString) else {
            return
        }
        sources.append(TrackedSource(url: normalized))
        persistSources()
    }

    func updateSourceURL(_ id: UUID, urlString: String) {
        guard let normalized = normalizedSourceURL(urlString),
              let index = sources.firstIndex(where: { $0.id == id }) else {
            return
        }
        sources[index].url = normalized
        stories.removeAll { $0.sourceID == id }
        persistSources()
    }

    private func normalizedSourceURL(_ urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let normalized = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: normalized), url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return normalized
    }

    func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
        stories.removeAll { $0.sourceID == id }
        persistSources()
    }

    private func persistSources() {
        try? sourceStore.saveSources(sources)
    }

    // MARK: - Homepage refresh

    func refresh() async {
        await refreshBookmarks()
    }

    private func refreshBookmarks() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshError = nil
        refreshStatus = "Reading Firefox tv bookmarks…"
        defer { isRefreshing = false; refreshStatus = nil; refreshProgress = 1 }
        do {
            let loaded = try await Task.detached { try FirefoxBookmarks.load() }.value
            stories = loaded
            sources = [bookmarkSource]
            let count = loaded.filter { $0.video != nil }.count
            bookmarkStatus = "\(count) videos · \(loaded.count - count) other bookmarks"
            ratingByStoryID = voteHistory.reduce(into: [:]) { states, record in
                if let id = record.storyID { states[id] = record.isUpvote }
            }
            recomputeRanking()
            goHome()
        } catch {
            lastRefreshError = "Couldn't sync Firefox tv bookmarks. \(error.localizedDescription)"
        }
    }

    private func refreshLegacySources() async {
        guard !isRefreshing, !sources.isEmpty else {
            return
        }
        isRefreshing = true
        refreshProgress = 0
        hasSkippedRefreshScreen = false
        lastRefreshError = nil
        stories = []
        pruneSeenURLs(persist: true)

        let sourcesSnapshot = sources
        var headlinesBySource: [UUID: [Story]] = [:]
        var completedSourceCount = 0
        refreshStatus = "Loading sources… 0 of \(sourcesSnapshot.count)"

        // One task group carries both phases rather than running them one
        // after the other. Sources used to all finish loading before the
        // first per-story fetch even started — with several dozen stories
        // behind several tracked sites, that meant paying the full cost of
        // both phases back to back. Enrichment for a source's stories now
        // starts the moment that source's headlines land, overlapping with
        // whichever other sources are still loading.
        enum Unit {
            case source(UUID, [Story])
            case enriched(String, Article?)
        }

        var pendingEnrichment: [Story] = []
        var runningSources = 0
        var runningEnrichment = 0
        var discoveredCount = 0
        var resolvedCount = 0
        let maxConcurrentSources = 3
        let maxConcurrentEnrichment = 4

        await withTaskGroup(of: Unit.self) { group in
            var sourceIterator = sourcesSnapshot.makeIterator()

            func startNextSource() {
                guard let source = sourceIterator.next() else {
                    return
                }
                runningSources += 1
                group.addTask { [fetcher] in
                    .source(source.id, await fetcher.fetchStories(from: source))
                }
            }

            func startNextEnrichment() {
                guard !pendingEnrichment.isEmpty else {
                    return
                }
                let story = pendingEnrichment.removeFirst()
                runningEnrichment += 1
                group.addTask { [fetcher] in
                    guard let url = URL(string: story.storyURL) else {
                        return .enriched(story.id, nil)
                    }
                    return .enriched(story.id, await fetcher.fetchArticle(url: url))
                }
            }

            func fillEnrichmentSlots() {
                while runningEnrichment < maxConcurrentEnrichment {
                    let before = runningEnrichment
                    startNextEnrichment()
                    if runningEnrichment == before {
                        break
                    }
                }
            }

            @MainActor
            func updateProgress() {
                let sourceProgress = Double(completedSourceCount) / Double(sourcesSnapshot.count)
                let enrichProgress = discoveredCount > 0 ? Double(resolvedCount) / Double(discoveredCount) : 0
                refreshProgress = Self.sourcePhaseShare * sourceProgress + Self.enrichPhaseShare * enrichProgress
            }

            for _ in 0..<maxConcurrentSources {
                startNextSource()
            }

            while let unit = await group.next() {
                switch unit {
                case .source(let sourceID, let sourceStories):
                    runningSources -= 1
                    headlinesBySource[sourceID] = sourceStories
                    completedSourceCount += 1

                    let unseenStories = sourceStories.filter { !isRecentlySeen($0.storyURL) }

                    // Appended to the existing array and re-sorted in place,
                    // never rebuilt from `headlinesBySource` — enrichment is
                    // now running concurrently with sources still arriving
                    // (that's the whole point of interleaving the two
                    // phases), and rebuilding from the pristine per-source
                    // snapshots on every arrival was discarding every excerpt
                    // and image already written into `stories` by enrichment
                    // tasks that had finished earlier in the same pass —
                    // which is why cards were coming back with no
                    // descriptions. Sorting the array that's actually been
                    // mutated keeps those in place.
                    var seenStoryURLs = Set(stories.map(\.storyURL))
                    for story in unseenStories where seenStoryURLs.insert(story.storyURL).inserted {
                        stories.append(story)
                    }
                    stories.sort { $0.fetchedAt > $1.fetchedAt }

                    // A cached article from a very recent refresh is still
                    // good — apply it straight to the card instead of
                    // hitting the network again for a page that was just
                    // fetched, and only queue the rest for a real fetch.
                    for story in unseenStories {
                        discoveredCount += 1
                        if let cached = articleCache[story.storyURL], let idx = stories.firstIndex(where: { $0.id == story.id }) {
                            resolvedCount += 1
                            if cached.bodyText.count >= 120 {
                                if stories[idx].imageURL == nil {
                                    stories[idx].imageURL = cached.imageURL
                                }
                                stories[idx].excerpt = String(cached.bodyText.prefix(1200))
                                stories[idx].publishedAt = cached.publishedAt
                            }
                        } else {
                            pendingEnrichment.append(story)
                        }
                    }

                    if runningSources < maxConcurrentSources {
                        startNextSource()
                    }
                    fillEnrichmentSlots()
                    refreshStatus = runningEnrichment > 0
                        ? "Fetching story details… \(resolvedCount) of \(discoveredCount)"
                        : "Loading sources… \(completedSourceCount) of \(sourcesSnapshot.count)"
                    updateProgress()

                case .enriched(let storyID, let article):
                    runningEnrichment -= 1
                    resolvedCount += 1
                    refreshStatus = "Fetching story details… \(resolvedCount) of \(discoveredCount)"
                    updateProgress()
                    startNextEnrichment()

                    guard let idx = stories.firstIndex(where: { $0.id == storyID }) else {
                        continue
                    }
                    // Some "headlines" turn out not to be real stories at all
                    // — site-chrome section labels ("Featured Podcasts",
                    // "Upcoming Tech Events") that happened to be marked up
                    // as headings. When the page it links to loads fine but
                    // yields almost no article text, that's a real signal
                    // it isn't a story — drop the card. But when the fetch
                    // itself failed or timed out (a slow page, a blocked
                    // script), that says nothing about whether it's a real
                    // story — dropping it there just makes entire sources
                    // vanish from the feed on a bad network day. Keep the
                    // card in that case, with its listing title standing in
                    // for an excerpt.
                    guard let article else {
                        continue
                    }
                    guard article.bodyText.count >= 120 else {
                        stories.remove(at: idx)
                        continue
                    }
                    cacheArticle(article, for: stories[idx].storyURL)
                    if stories[idx].imageURL == nil {
                        stories[idx].imageURL = article.imageURL
                    }
                    stories[idx].excerpt = String(article.bodyText.prefix(1200))
                    stories[idx].publishedAt = article.publishedAt
                }
            }
        }

        let failureCount = sourcesSnapshot.filter { (headlinesBySource[$0.id] ?? []).isEmpty }.count
        guard failureCount < sourcesSnapshot.count else {
            lastRefreshError = "Couldn't pull any stories from your tracked sources. Check the URLs in Settings."
            refreshStatus = nil
            refreshProgress = 0
            isRefreshing = false
            return
        }

        refreshStatus = "Sorting your feed…"
        refreshProgress = 0.97
        recomputeRanking()
        // Story ids are stable per source+URL, so a rating given before this
        // refresh still belongs to the card that came back — rebuild the
        // on-screen bolt states from the saved history rather than wiping
        // them, or a story you already rated comes back looking untouched.
        ratingByStoryID = voteHistory.reduce(into: [:]) { states, record in
            if let storyID = record.storyID {
                states[storyID] = record.isUpvote
            }
        }
        refreshProgress = 1
        refreshStatus = nil
        // Land back on a settled page 1 rather than wherever the reader was
        // when they hit refresh — the story they were reading is gone from
        // `stories` by now anyway.
        goHome()
        isRefreshing = false
    }

    /// How much of the bar each phase owns. The two now run concurrently
    /// rather than back to back, so this is a blend rather than two
    /// consecutive ranges — fetching every story is still the long pole by a
    /// wide margin, so it gets the bulk of the weight.
    private static let sourcePhaseShare = 0.3
    private static let enrichPhaseShare = 0.7

    // MARK: - Permalink

    func article(for story: Story) -> Article? {
        articleCache[story.storyURL]
    }

    func loadArticle(for story: Story) async -> Article? {
        if let cached = articleCache[story.storyURL] {
            return cached
        }
        guard let url = URL(string: story.storyURL) else {
            return nil
        }
        let article = await fetcher.fetchArticle(url: url)
        if let article {
            cacheArticle(article, for: story.storyURL)
        }
        return article
    }

    /// Popped routes go here so ⌘] can restore them — standard browser
    /// back/forward semantics: navigating to a new story clears this, so
    /// forward only ever replays what you just went back from.
    private var forwardPath: [WatchRoute] = []
    /// The list from which the current permalink was opened. Opening a story
    /// marks it read, which changes Feed immediately, so adjacent navigation
    /// must keep the pre-open list rather than rebuilding from all stories.
    private var permalinkStoryOrder: [String] = []

    func openStory(_ story: Story) {
        permalinkStoryOrder = visibleStories(from: stories).map(\.id)
        path.append(.story(story.id))
        forwardPath.removeAll()
    }

    /// The story immediately before/after `story` in the homepage's current
    /// list. Feed uses its ranked order before the read filter removes the
    /// opened story. All uses the same published-date ordering shown by the
    /// homepage. Read stories stay in the sequence so j/k keeps working from
    /// a story you just opened.
    func adjacentStory(to story: Story, offset: Int) -> Story? {
        let ordered: [Story]
        if permalinkStoryOrder.isEmpty {
            ordered = visibleStories(from: stories)
        } else {
            let storiesByID = Dictionary(uniqueKeysWithValues: stories.map { ($0.id, $0) })
            ordered = permalinkStoryOrder.compactMap { storiesByID[$0] }
        }
        guard let idx = ordered.firstIndex(where: { $0.id == story.id }) else {
            return nil
        }
        let newIndex = idx + offset
        guard ordered.indices.contains(newIndex) else {
            return nil
        }
        return ordered[newIndex]
    }

    /// Replaces the current permalink in place rather than pushing a new one
    /// — j/k browsing through stories one at a time shouldn't build up a
    /// back-stack of every story passed through along the way.
    func showAdjacentStory(from story: Story, offset: Int) {
        guard let next = adjacentStory(to: story, offset: offset) else {
            return
        }
        if path.isEmpty {
            path.append(.story(next.id))
        } else {
            path[path.count - 1] = .story(next.id)
        }
        forwardPath.removeAll()
    }

    func goBack() {
        guard let last = path.popLast() else {
            return
        }
        forwardPath.append(last)
        if path.isEmpty {
            permalinkStoryOrder.removeAll()
        }
    }

    func goForward() {
        guard let next = forwardPath.popLast() else {
            return
        }
        path.append(next)
    }

    func story(withID id: String) -> Story? {
        stories.first { $0.id == id }
    }

    /// Bumped whenever "Read" in the toolbar is clicked — HomepageView
    /// listens for this to reset back to page 1 and scroll to the top, the
    /// same way a site logo acts as a home link.
    @Published var homeRequestID = 0

    func goHome() {
        path.removeAll()
        forwardPath.removeAll()
        permalinkStoryOrder.removeAll()
        homeRequestID += 1
    }
}
