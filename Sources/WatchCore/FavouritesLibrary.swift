import Foundation

/// Independent copies of saved videos. Firefox sync never writes this library.
public struct FavouritesLibrary: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let story: Story
        public let savedAt: Date
    }
    public private(set) var entries: [String: Entry] = [:]
    public init() {}

    public var stories: [Story] {
        entries.sorted {
            if $0.value.savedAt != $1.value.savedAt { return $0.value.savedAt > $1.value.savedAt }
            return $0.key < $1.key
        }.map { $0.value.story }
    }

    private static func key(_ story: Story) -> String {
        URL(string: story.storyURL).flatMap(BookmarkVideo.init)?.key ?? story.storyURL
    }
    public func contains(_ story: Story) -> Bool { entries[Self.key(story)] != nil }
    public mutating func toggle(_ story: Story, now: Date = Date()) {
        let key = Self.key(story)
        if entries[key] != nil { entries.removeValue(forKey: key) }
        else { entries[key] = Entry(story: story, savedAt: now) }
    }
}

public struct FavouritesStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> FavouritesLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return FavouritesLibrary() }
        return try JSONDecoder().decode(FavouritesLibrary.self, from: Data(contentsOf: fileURL))
    }
    public func save(_ library: FavouritesLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: fileURL, options: .atomic)
    }
}
