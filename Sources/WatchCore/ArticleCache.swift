import Foundation

/// One cached full-article fetch, keyed by the story's URL — refreshes pull
/// the same front pages (and often the same stories) repeatedly, so reusing
/// a recent fetch avoids re-loading and re-scraping a page that hasn't
/// changed since last time.
public struct ArticleCacheEntry: Codable, Sendable {
    public let storyURL: String
    public let article: Article
    public let fetchedAt: Date

    public init(storyURL: String, article: Article, fetchedAt: Date = Date()) {
        self.storyURL = storyURL
        self.article = article
        self.fetchedAt = fetchedAt
    }
}

public protocol ArticleCacheStore {
    func loadEntries() throws -> [ArticleCacheEntry]
    func saveEntries(_ entries: [ArticleCacheEntry]) throws
}

/// Caps storage at the most recent `limit` articles (oldest dropped first),
/// keeping the on-disk cache from growing without bound across months of use.
public final class FileArticleCacheStore: ArticleCacheStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let limit: Int

    public init(fileURL: URL, limit: Int = 100, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.limit = limit
        self.fileManager = fileManager
    }

    public func loadEntries() throws -> [ArticleCacheEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ArticleCacheEntry].self, from: data)
    }

    public func saveEntries(_ entries: [ArticleCacheEntry]) throws {
        let trimmed = Array(entries.sorted { $0.fetchedAt > $1.fetchedAt }.prefix(limit))
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(trimmed)
        try data.write(to: fileURL, options: .atomic)
    }
}
