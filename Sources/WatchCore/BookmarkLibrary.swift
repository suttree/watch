import Foundation

/// A local snapshot with removals stored independently from Firefox.
public struct BookmarkLibrary: Codable, Sendable {
    public private(set) var bookmarks: [Story] = []
    public private(set) var removedKeys: Set<String> = []
    public private(set) var lastSyncedAt: Date?

    public init() {}

    public var visibleBookmarks: [Story] {
        bookmarks.filter { !removedKeys.contains(Self.key(for: $0)) }
    }

    public mutating func sync(_ bookmarks: [Story], now: Date = Date()) {
        self.bookmarks = bookmarks
        lastSyncedAt = now
    }

    public mutating func remove(_ story: Story) { removedKeys.insert(Self.key(for: story)) }
    public mutating func restore(_ story: Story) { removedKeys.remove(Self.key(for: story)) }
    public mutating func restoreAll() { removedKeys.removeAll() }

    private static func key(for story: Story) -> String {
        if let url = URL(string: story.storyURL), let video = YouTubeVideo(url: url) {
            return "youtube:\(video.id)"
        }
        return story.storyURL
    }
}

public struct BookmarkLibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> BookmarkLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return BookmarkLibrary() }
        return try JSONDecoder().decode(BookmarkLibrary.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ library: BookmarkLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: fileURL, options: .atomic)
    }
}
