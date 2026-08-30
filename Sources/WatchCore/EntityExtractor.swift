import Foundation
import NaturalLanguage

/// Named-entity recognition via Apple's on-device NaturalLanguage framework
/// — no API, no network call, no cost. People, places, and organizations are
/// much cleaner recurring signals for the ranker than generic words: "Elon
/// Musk" or "the Federal Reserve" showing up across stories you've voted on
/// says more than most individual words would.
public enum EntityExtractor {
    /// Returns entity tokens like `entity_elon_musk`, distinct from plain
    /// word tokens so a ranker can weight or reason about them separately
    /// while still fitting the same bag-of-tokens model.
    public static func entities(in text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var results: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag, tag == .personalName || tag == .placeName || tag == .organizationName {
                let entity = text[range]
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "_")
                if !entity.isEmpty {
                    results.append("entity_\(entity)")
                }
            }
            return true
        }
        return results
    }
}
