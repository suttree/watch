import Foundation

/// One up/down vote on a story, kept as training data for `NaiveBayesRanker`.
/// Deliberately doesn't key on the story's URL — URLs are essentially always
/// unique, so remembering "you liked this exact URL" wouldn't help predict
/// interest in stories you haven't seen yet. What generalizes is the words.
public struct VoteRecord: Codable, Sendable {
    /// Which card this vote came from, so a second press of the same button
    /// can find and undo it. Not used for training — the words are what
    /// generalize — and optional so records saved before it existed decode.
    public let storyID: String?
    public let title: String
    public let sourceName: String
    /// A bounded slice of the article's opening text (not the whole thing —
    /// full articles are noisy enough, relative to how few votes exist
    /// early on, that they'd add more sparsity than signal). Optional so
    /// records saved before this field existed still decode fine.
    public let contentExcerpt: String?
    public let isUpvote: Bool
    public let votedAt: Date

    public init(storyID: String? = nil, title: String, sourceName: String, contentExcerpt: String? = nil, isUpvote: Bool, votedAt: Date = Date()) {
        self.storyID = storyID
        self.title = title
        self.sourceName = sourceName
        self.contentExcerpt = contentExcerpt
        self.isUpvote = isUpvote
        self.votedAt = votedAt
    }
}

public protocol VoteStore {
    func loadVotes() throws -> [VoteRecord]
    func saveVotes(_ votes: [VoteRecord]) throws
}

public final class FileVoteStore: VoteStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadVotes() throws -> [VoteRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([VoteRecord].self, from: data)
    }

    public func saveVotes(_ votes: [VoteRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(votes)
        try data.write(to: fileURL, options: .atomic)
    }
}
