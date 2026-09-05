import XCTest
import SQLite3
@testable import WatchCore

final class FirefoxBookmarksTests: XCTestCase {
    func testFeedTabsAreDisjointAndSortByBookmarkDate() {
        let source = UUID()
        let older = Story(title: "Video", storyURL: "https://youtu.be/jNas99oEXBU", sourceID: source, sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: 1))
        let newer = Story(title: "Short", storyURL: "https://youtube.com/shorts/sY27Ds6Wc-A", sourceID: source, sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: 3))
        let channel = Story(title: "Channel", storyURL: "https://youtube.com/@channel", sourceID: source, sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: 2))
        let article = Story(title: "Article", storyURL: "https://example.com/article", sourceID: source, sourceName: "tv", fetchedAt: Date(timeIntervalSince1970: 4))
        let all = [older, article, newer, channel]
        let youtube = BookmarkFeedMode.youtube.stories(from: all)
        let other = BookmarkFeedMode.other.stories(from: all)
        XCTAssertEqual(youtube.map(\.id), [newer.id, older.id])
        XCTAssertEqual(other.map(\.id), [article.id, channel.id])
        XCTAssertTrue(Set(youtube.map(\.id)).isDisjoint(with: Set(other.map(\.id))))
        XCTAssertEqual(youtube.count + other.count, all.count)
    }

    func testVideoLinksAndTimestamps() throws {
        for path in ["https://youtu.be/jNas99oEXBU?t=1m2s", "https://www.youtube.com/watch?v=jNas99oEXBU&t=62", "https://www.youtube.com/shorts/jNas99oEXBU?start=62"] {
            let video = try XCTUnwrap(YouTubeVideo(url: URL(string: path)!))
            XCTAssertEqual(video.id, "jNas99oEXBU")
            XCTAssertEqual(video.start, 62)
        }
        for path in ["https://youtube.com/@channel", "https://youtube.com/results?search_query=test", "https://youtube.com.evil.test/watch?v=jNas99oEXBU", "https://youtu.be/invalid"] {
            XCTAssertNil(YouTubeVideo(url: URL(string: path)!))
        }
    }

    func testOnlyMenuTVAndDescendantsWithDeduplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("places.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE moz_bookmarks(id INTEGER, parent INTEGER, type INTEGER, title TEXT, guid TEXT, fk INTEGER, dateAdded INTEGER);
        CREATE TABLE moz_places(id INTEGER, url TEXT);
        INSERT INTO moz_bookmarks VALUES(1,0,2,'Menu','menu________',NULL,0),(2,1,2,'TV','tvfolder',NULL,0),(3,2,2,'Films','nested',NULL,0),(4,0,2,'tv','outside',NULL,0);
        INSERT INTO moz_places VALUES(1,'https://youtube.com/watch?v=jNas99oEXBU&t=1s'),(2,'https://youtu.be/jNas99oEXBU'),(3,'https://example.com/article'),(4,'https://example.com/private');
        INSERT INTO moz_bookmarks VALUES(5,2,1,'Newest','video',1,3000000),(6,3,1,'Duplicate','dup',2,2000000),(7,3,1,'Article','article',3,1000000),(8,4,1,'Excluded','excluded',4,4000000);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let stories = try XCTUnwrap(FirefoxBookmarks.read(database: database))
        XCTAssertEqual(stories.map(\.title), ["Newest", "Article"])
        XCTAssertEqual(stories.first?.fetchedAt, Date(timeIntervalSince1970: 3))
        XCTAssertNotNil(stories.first?.video)
        XCTAssertNil(stories.last?.video)
        XCTAssertEqual(try FirefoxBookmarks.read(database: database)?.map(\.id), stories.map(\.id))
    }

    func testLiveFirefoxSnapshotWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["WATCH_VERIFY_FIREFOX"] == "1" else {
            throw XCTSkip("Set WATCH_VERIFY_FIREFOX=1 to verify the local tv folder.")
        }
        let stories = try FirefoxBookmarks.load()
        XCTAssertFalse(stories.isEmpty)
        print("Firefox tv: \(stories.count) bookmarks, \(stories.filter { $0.video != nil }.count) videos")
    }
}
