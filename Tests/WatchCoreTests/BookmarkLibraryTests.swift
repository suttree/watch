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
