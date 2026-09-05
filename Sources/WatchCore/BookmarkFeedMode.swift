import Foundation

public enum BookmarkFeedMode: String, CaseIterable, Sendable {
    case youtube
    case other

    public var title: String { self == .youtube ? "YouTube" : "Other" }

    public func stories(from bookmarks: [Story]) -> [Story] {
        bookmarks.filter { story in
            let isVideo = URL(string: story.storyURL).flatMap(YouTubeVideo.init) != nil
            return self == .youtube ? isVideo : !isVideo
        }.sorted {
            if $0.fetchedAt != $1.fetchedAt { return $0.fetchedAt > $1.fetchedAt }
            return $0.id < $1.id
        }
    }
}
