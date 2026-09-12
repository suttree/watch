import Foundation

public enum BookmarkFeedMode: String, CaseIterable, Sendable {
    case youtube
    case other
    case favourites

    public var title: String { self == .youtube ? "All" : self == .other ? "Other" : "Favourites" }

    public func stories(from bookmarks: [Story]) -> [Story] {
        guard self != .favourites else { return [] }
        return bookmarks.filter { story in
            let isVideo = URL(string: story.storyURL).flatMap(BookmarkVideo.init) != nil
            return self == .youtube ? isVideo : !isVideo
        }.sorted {
            if $0.fetchedAt != $1.fetchedAt { return $0.fetchedAt > $1.fetchedAt }
            return $0.id < $1.id
        }
    }
}
