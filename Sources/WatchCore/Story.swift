import Foundation

/// A headline pulled from a tracked source's front page, shown as a card on
/// the homepage. `id` is stable per (source, story URL) pair so a story that
/// reappears across refreshes doesn't get treated as new.
public struct Story: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let storyURL: String
    public let sourceID: UUID
    public let sourceName: String
    public var imageURL: String?
    /// The opening line(s) of the story's own page, filled in by a second
    /// enrichment pass after the headline is found — listing pages mostly
    /// don't carry deck/trail text in the DOM for anything but hero stories.
    public var excerpt: String?
    public let fetchedAt: Date
    /// The page's own stated publish time, filled in during enrichment once
    /// the story's article page has been fetched — see `Article.publishedAt`.
    /// Nil until then, and nil after if the page doesn't expose one.
    public var publishedAt: Date?
    /// Video details discovered while parsing the linked page. A nil value
    /// means the page is still a normal article, not that parsing failed.
    public var video: VideoInfo?

    public init(
        title: String,
        storyURL: String,
        sourceID: UUID,
        sourceName: String,
        imageURL: String? = nil,
        excerpt: String? = nil,
        fetchedAt: Date = Date(),
        publishedAt: Date? = nil,
        video: VideoInfo? = nil
    ) {
        self.id = "\(sourceID.uuidString)|\(storyURL)"
        self.title = title
        self.storyURL = storyURL
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.imageURL = imageURL
        self.excerpt = excerpt
        self.fetchedAt = fetchedAt
        self.publishedAt = publishedAt
        self.video = video ?? Self.videoInfo(for: storyURL)
    }

    private static func videoInfo(for rawURL: String) -> VideoInfo? {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return nil }
        let videoHosts = ["youtube.com", "youtu.be", "vimeo.com", "player.vimeo.com", "loom.com", "cinejoy.to", "popcornmovies.ac"]
        guard videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return VideoInfo(url: rawURL)
    }
}

public struct VideoInfo: Codable, Equatable, Sendable {
    public let url: String
    public let durationSeconds: Int?
    public let highlight: String?

    public init(url: String, durationSeconds: Int? = nil, highlight: String? = nil) {
        self.url = url
        self.durationSeconds = durationSeconds
        self.highlight = highlight
    }

    public var durationLabel: String? {
        guard let durationSeconds else { return nil }
        return "\(durationSeconds / 60):\(String(format: "%02d", durationSeconds % 60))"
    }
}
