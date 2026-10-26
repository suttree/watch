import XCTest
@testable import WatchCore

final class BookmarkLibraryTests: XCTestCase {
    private func story(_ url: String, title: String = "Video") -> Story {
        Story(title: title, storyURL: url, sourceID: FirefoxBookmarks.sourceID, sourceName: "tv")
    }

    func testRemovalSurvivesSyncRelaunchAndChangedYouTubeURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookmarkLibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        let video = story("https://www.youtube.com/watch?v=jNas99oEXBU&t=1s")
        let other = story("https://example.com/article", title: "Article")
        var library = BookmarkLibrary()
        library.sync([video, other])
        library.remove(video)
        try store.save(library)
        var relaunched = try store.load()
        XCTAssertEqual(relaunched.visibleBookmarks.map(\.id), [other.id])
        let changed = story("https://youtu.be/jNas99oEXBU?t=20", title: "Renamed video")
        relaunched.sync([changed, other])
        XCTAssertEqual(relaunched.visibleBookmarks.map(\.id), [other.id])
        XCTAssertEqual(relaunched.bookmarks.count, 2)
        relaunched.restore(video)
        XCTAssertEqual(relaunched.visibleBookmarks.count, 2)
    }

    func testRestoreAllAndRemovalAfterBookmarkDisappearsAndReturns() {
        let video = story("https://youtu.be/jNas99oEXBU")
        let other = story("https://example.com/article")
        var library = BookmarkLibrary()
        library.sync([video, other])
        library.remove(video)
        library.remove(other)
        library.sync([])
        library.sync([video, other])
        XCTAssertTrue(library.visibleBookmarks.isEmpty)
        library.restoreAll()
        XCTAssertEqual(library.visibleBookmarks.count, 2)
        XCTAssertTrue(library.removedKeys.isEmpty)
    }

    func testRemovedRowsKeepTheirPositionAndRestoreIndependently() throws {
        let first = story("https://youtu.be/jNas99oEXBU")
        let second = story("https://example.com/second")
        var library = BookmarkLibrary()
        library.sync([first, second])
        library.remove(first)
        library.remove(second)
        library = try JSONDecoder().decode(BookmarkLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(library.bookmarks.map(\.id), [first.id, second.id])
        XCTAssertTrue(library.isRemoved(first))
        XCTAssertTrue(library.isRemoved(second))
        library.restore(first)
        XCTAssertFalse(library.isRemoved(first))
        XCTAssertTrue(library.isRemoved(second))
        XCTAssertEqual(library.bookmarks.map(\.id), [first.id, second.id])
    }

    func testSectionsSurviveStoreSyncAndCanonicalURLChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookmarkLibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        let video = story("https://www.youtube.com/watch?v=jNas99oEXBU&t=1s")
        let reel = story("https://www.instagram.com/reel/ABC123/")
        var library = BookmarkLibrary()
        library.sync([video, reel])
        library.setSection(.sleep, for: video, included: true)
        library.setSection(.eat, for: reel, included: true)
        try store.save(library)
        library = try store.load()
        library.sync([])
        let changedVideo = story("https://youtu.be/jNas99oEXBU?t=20")
        let changedReel = story("https://instagram.com/p/ABC123/?utm_source=test")
        library.sync([changedVideo, changedReel])
        XCTAssertTrue(library.contains(changedVideo, in: .sleep))
        XCTAssertTrue(library.contains(changedReel, in: .eat))
    }

    func testOldLibraryLoadsWithoutLosingBookmarksOrRemovals() throws {
        let video = story("https://youtu.be/jNas99oEXBU")
        var library = BookmarkLibrary()
        library.sync([video])
        library.remove(video)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        json.removeValue(forKey: "sectionKeys")
        let loaded = try JSONDecoder().decode(BookmarkLibrary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.bookmarks, [video])
        XCTAssertTrue(loaded.isRemoved(video))
        XCTAssertEqual(loaded.lastSyncedAt, library.lastSyncedAt)
        XCTAssertFalse(loaded.contains(video, in: .sleep))
        XCTAssertFalse(loaded.contains(video, in: .eat))
    }

    func testMissingStoreStartsEmptyAndCorruptStoreThrows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookmarkLibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        XCTAssertTrue(try store.load().bookmarks.isEmpty)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }
}
