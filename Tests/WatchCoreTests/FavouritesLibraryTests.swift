import XCTest
@testable import WatchCore

final class FavouritesLibraryTests: XCTestCase {
    private func story(_ url: String, title: String = "Saved video") -> Story {
        Story(title: title, storyURL: url, sourceID: FirefoxBookmarks.sourceID, sourceName: "tv")
    }

    func testSavedCopySurvivesFirefoxRemovalAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let favouritesStore = FavouritesStore(fileURL: directory.appendingPathComponent("favourites.json"))
        let bookmarksStore = BookmarkLibraryStore(fileURL: directory.appendingPathComponent("bookmarks.json"))
        let video = story("https://instagram.com/reel/ABC123/", title: "My reel")
        var bookmarks = BookmarkLibrary()
        bookmarks.sync([video])
        var favourites = FavouritesLibrary()
        favourites.toggle(video)
        try favouritesStore.save(favourites)
        bookmarks.remove(video)
        bookmarks.sync([])
        try bookmarksStore.save(bookmarks)
        let reloaded = try favouritesStore.load()
        XCTAssertEqual(reloaded.stories, [video])
        XCTAssertTrue(reloaded.contains(video))
        XCTAssertTrue(try bookmarksStore.load().bookmarks.isEmpty)
    }

    func testAliasesToggleSameFavouriteAndNewestSavedFirst() {
        let reel = story("https://instagram.com/reel/ABC123/?igsh=one")
        let alias = story("https://www.instagram.com/p/ABC123/")
        let youtube = story("https://youtu.be/jNas99oEXBU?t=10")
        var favourites = FavouritesLibrary()
        favourites.toggle(reel, now: Date(timeIntervalSince1970: 1))
        favourites.toggle(youtube, now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(favourites.stories, [youtube, reel])
        XCTAssertTrue(favourites.contains(alias))
        favourites.toggle(alias)
        XCTAssertEqual(favourites.stories, [youtube])
        favourites.toggle(story("https://youtube.com/watch?v=jNas99oEXBU"))
        XCTAssertTrue(favourites.stories.isEmpty)
    }

    func testCorruptStoreThrowsInsteadOfReturningEmptyLibrary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try FavouritesStore(fileURL: url).load())
    }
}
