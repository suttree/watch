import XCTest
@testable import WatchCore

final class BookmarkFeedModeTests: XCTestCase {
    func testDeletedItemsMoveBetweenFeedsAndRestoreAfterRelaunch() throws {
        let video = story("https://youtu.be/jNas99oEXBU", date: 1)
        let reel = story("https://instagram.com/reel/ABC123/", date: 2)
        let other = story("https://example.com/article", date: 3)
        var library = BookmarkLibrary()
        library.sync([video, other, reel])
        library.remove(video)
        library.remove(other)
        library = try JSONDecoder().decode(BookmarkLibrary.self, from: JSONEncoder().encode(library))

        XCTAssertEqual(BookmarkFeedMode.youtube.stories(from: library.bookmarks, isRemoved: library.isRemoved), [reel])
        XCTAssertTrue(BookmarkFeedMode.other.stories(from: library.bookmarks, isRemoved: library.isRemoved).isEmpty)
        XCTAssertEqual(BookmarkFeedMode.deleted.stories(from: library.bookmarks, isRemoved: library.isRemoved), [other, video])

        library.restore(video)
        XCTAssertEqual(BookmarkFeedMode.youtube.stories(from: library.bookmarks, isRemoved: library.isRemoved), [reel, video])
        XCTAssertEqual(BookmarkFeedMode.deleted.stories(from: library.bookmarks, isRemoved: library.isRemoved), [other])

        library.restoreAll()
        XCTAssertTrue(BookmarkFeedMode.deleted.stories(from: library.bookmarks, isRemoved: library.isRemoved).isEmpty)
        XCTAssertEqual(BookmarkFeedMode.other.stories(from: library.bookmarks, isRemoved: library.isRemoved), [other])
    }

    private func story(_ url: String, date: TimeInterval) -> Story {
        Story(title: "Bookmark", storyURL: url, sourceID: FirefoxBookmarks.sourceID,
              sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: date))
    }
}
