import Foundation

/// The full extracted content of one story, fetched on demand when its
/// permalink page is opened (not pre-fetched for every headline on the
/// homepage, to keep refreshes fast).
public struct Article: Codable, Equatable, Sendable {
    public let title: String
    public let bodyText: String
    public let imageURL: String?
    public let sourceURL: String
    /// When the page itself says the story was published — pulled from
    /// `article:published_time`, a `<time datetime>` element, or JSON-LD
    /// `datePublished`, whichever the page actually carries. Nil when none of
    /// those are present, which is common enough that callers need a fallback
    /// rather than treating it as required.
    public let publishedAt: Date?

    public init(title: String, bodyText: String, imageURL: String?, sourceURL: String, publishedAt: Date? = nil) {
        self.title = title
        self.bodyText = bodyText
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.publishedAt = publishedAt
    }
}
