import Foundation

public enum BookmarkFeedMode: String, CaseIterable, Sendable {
    case youtube
    case other
    case favourites
    case deleted

    public var title: String {
        switch self {
        case .youtube: "All"
        case .other: "Other"
        case .favourites: "Favourites"
        case .deleted: "Deleted"
        }
    }

    public func stories(from bookmarks: [Story], isRemoved: (Story) -> Bool = { _ in false }) -> [Story] {
        guard self != .favourites else { return [] }
        return bookmarks.filter { story in
            if self == .deleted { return isRemoved(story) }
            guard !isRemoved(story) else { return false }
            let isVideo = URL(string: story.storyURL).flatMap(BookmarkVideo.init) != nil
            return self == .youtube ? isVideo : !isVideo
        }.sorted {
            if $0.fetchedAt != $1.fetchedAt { return $0.fetchedAt > $1.fetchedAt }
            return $0.id < $1.id
        }
    }
}
