import Foundation

/// A multinomial Naive Bayes classifier over tokens drawn from a story's
/// title, source, a bounded slice of its article text, and named entities
/// recognized in that text — trained on your up/down votes. Scores a new,
/// never-seen story by how similar its tokens are to stories you've
/// upvoted vs downvoted — the standard "spam filter" technique, applied to
/// news instead of email.
public final class NaiveBayesRanker: Sendable {
    private let likeWordCounts: [String: Int]
    private let dislikeWordCounts: [String: Int]
    private let likeTotal: Int
    private let dislikeTotal: Int
    private let likeDocs: Int
    private let dislikeDocs: Int
    private let vocabularySize: Int

    /// Article text is noisier and much larger-vocabulary than a title —
    /// with only a handful of votes to calibrate against, using the whole
    /// thing would add more sparsity than signal. Bounding it keeps the
    /// added content genuinely informative rather than diluting everything.
    private static let excerptTokenBudget = 500

    public init(votes: [VoteRecord]) {
        var likeWordCounts: [String: Int] = [:]
        var dislikeWordCounts: [String: Int] = [:]
        var likeTotal = 0
        var dislikeTotal = 0
        var likeDocs = 0
        var dislikeDocs = 0
        var vocabulary: Set<String> = []

        for vote in votes {
            let tokens = Self.allTokens(title: vote.title, sourceName: vote.sourceName, excerpt: vote.contentExcerpt)
            vocabulary.formUnion(tokens)
            if vote.isUpvote {
                likeDocs += 1
                for token in tokens {
                    likeWordCounts[token, default: 0] += 1
                    likeTotal += 1
                }
            } else {
                dislikeDocs += 1
                for token in tokens {
                    dislikeWordCounts[token, default: 0] += 1
                    dislikeTotal += 1
                }
            }
        }

        self.likeWordCounts = likeWordCounts
        self.dislikeWordCounts = dislikeWordCounts
        self.likeTotal = likeTotal
        self.dislikeTotal = dislikeTotal
        self.likeDocs = likeDocs
        self.dislikeDocs = dislikeDocs
        self.vocabularySize = max(vocabulary.count, 1)
    }

    /// Needs a few examples of both classes before predictions mean
    /// anything — below that it's just noise dressed up as a score.
    public var isTrained: Bool {
        likeDocs >= 3 && dislikeDocs >= 3
    }

    /// Higher = predicted more interesting. The log-odds of "like" vs
    /// "dislike" given the tokens, Laplace-smoothed (+1 to every count) so a
    /// token that's never been seen before doesn't zero out the whole score.
    public func score(title: String, sourceName: String, excerpt: String? = nil) -> Double {
        guard isTrained else {
            return 0
        }
        let tokens = Self.allTokens(title: title, sourceName: sourceName, excerpt: excerpt)
        let totalDocs = Double(likeDocs + dislikeDocs)

        var likeScore = log(Double(likeDocs) / totalDocs)
        var dislikeScore = log(Double(dislikeDocs) / totalDocs)
        for token in tokens {
            likeScore += log(Double(likeWordCounts[token, default: 0] + 1) / Double(likeTotal + vocabularySize))
            dislikeScore += log(Double(dislikeWordCounts[token, default: 0] + 1) / Double(dislikeTotal + vocabularySize))
        }
        return likeScore - dislikeScore
    }

    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "to", "in", "on", "for", "and", "is", "at", "by", "with",
        "as", "it", "its", "this", "that", "from", "are", "was", "be", "how", "what", "why",
        "after", "over", "into", "your", "you", "new", "says"
    ]

    private static func allTokens(title: String, sourceName: String, excerpt: String?) -> [String] {
        var tokens = tokenize(title + " " + sourceName)

        let boundedExcerpt = excerpt.map { String($0.prefix(excerptTokenBudget)) } ?? ""
        if !boundedExcerpt.isEmpty {
            tokens += tokenize(boundedExcerpt)
        }

        // Entities from the title and excerpt both, since a title alone
        // often doesn't name who/what a story's actually about.
        tokens += EntityExtractor.entities(in: title + " " + boundedExcerpt)

        return tokens
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
