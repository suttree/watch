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

    func testSectionsOverlapKeepAllAndRespectRemoval() throws {
        let video = story("https://youtu.be/jNas99oEXBU", date: 1)
        let reel = story("https://instagram.com/reel/ABC123/", date: 2)
        let other = story("https://example.com/article", date: 3)
        var library = BookmarkLibrary()
        library.sync([video, reel, other])
        library.setSection(.sleep, for: video, included: true)
        library.setSection(.eat, for: video, included: true)
        library.setSection(.eat, for: reel, included: true)
        library.setSection(.sleep, for: other, included: true)
        library = try JSONDecoder().decode(BookmarkLibrary.self, from: JSONEncoder().encode(library))

        func feed(_ mode: BookmarkFeedMode) -> [Story] {
            mode.stories(from: library.bookmarks, isRemoved: library.isRemoved,
                         isInSection: { library.contains($0, in: $1) })
        }
        XCTAssertEqual(feed(.youtube), [reel, video])
        XCTAssertEqual(feed(.sleep), [video])
        XCTAssertEqual(feed(.eat), [reel, video])
        XCTAssertFalse(library.contains(other, in: .sleep))

        library.setSection(.sleep, for: video, included: false)
        XCTAssertTrue(feed(.sleep).isEmpty)
        XCTAssertEqual(feed(.youtube), [reel, video])
        XCTAssertEqual(feed(.eat), [reel, video])
        library.remove(video)
        XCTAssertEqual(feed(.eat), [reel])
        library.restore(video)
        XCTAssertEqual(feed(.eat), [reel, video])
    }

    private func story(_ url: String, date: TimeInterval) -> Story {
        Story(title: "Bookmark", storyURL: url, sourceID: FirefoxBookmarks.sourceID,
              sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: date))
    }
}
