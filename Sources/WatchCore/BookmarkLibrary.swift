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

    public func isRemoved(_ story: Story) -> Bool {
        removedKeys.contains(Self.key(for: story))
    }

    public mutating func sync(_ bookmarks: [Story], now: Date = Date()) {
        // Older versions stored Instagram removals as full URLs.
        removedKeys = Set(removedKeys.map { key in
            guard let url = URL(string: key), let video = InstagramVideo(url: url) else { return key }
            return "instagram:\(video.id)"
        })
        self.bookmarks = bookmarks
        lastSyncedAt = now
    }

    public mutating func remove(_ story: Story) { removedKeys.insert(Self.key(for: story)) }
    public mutating func restore(_ story: Story) { removedKeys.remove(Self.key(for: story)) }
    public mutating func restoreAll() { removedKeys.removeAll() }

    private static func key(for story: Story) -> String {
        if let url = URL(string: story.storyURL), let video = BookmarkVideo(url: url) {
            return video.key
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
