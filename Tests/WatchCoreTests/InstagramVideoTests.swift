import XCTest
@testable import WatchCore

final class InstagramVideoTests: XCTestCase {
    func testSupportedLinksAndCanonicalIdentity() throws {
        for kind in ["reel", "reels", "p", "tv"] {
            let video = try XCTUnwrap(InstagramVideo(url: URL(string: "https://www.instagram.com/\(kind)/ABC_12-xy/?igsh=tracking")!))
            XCTAssertEqual(video.id, "ABC_12-xy")
            XCTAssertEqual(video.embedURL.absoluteString, "https://www.instagram.com/\(kind == "reels" ? "reel" : kind)/ABC_12-xy/embed/")
            XCTAssertEqual(BookmarkVideo(url: URL(string: "https://instagram.com/\(kind)/ABC_12-xy/")!)?.key, "instagram:ABC_12-xy")
        }
    }

    func testRejectsProfilesStoriesAndUntrustedHosts() {
        for address in ["https://instagram.com/person/", "https://instagram.com/stories/person/123/", "https://instagram.com/reel/", "https://instagram.com/reel/abc/extra", "https://instagram.com.evil.test/reel/abc/", "https://evilinstagram.com/p/abc/", "file://instagram.com/p/abc/", "https://instagram.com/p/a%22b/"] {
            XCTAssertNil(InstagramVideo(url: URL(string: address)!), address)
        }
    }

    func testLegacyRemovalSurvivesSync() throws {
        let address = "https://www.instagram.com/reel/ABC123/?igsh=old"
        let data = try JSONSerialization.data(withJSONObject: ["bookmarks": [], "removedKeys": [address]])
        var library = try JSONDecoder().decode(BookmarkLibrary.self, from: data)
        let story = Story(title: "Reel", storyURL: "https://instagram.com/p/ABC123/", sourceID: UUID(), sourceName: "tv")
        library.sync([story])
        XCTAssertTrue(library.isRemoved(story))
        XCTAssertTrue(library.visibleBookmarks.isEmpty)
        library.restore(story)
        XCTAssertFalse(library.isRemoved(story))
    }

    func testInstagramSharesVideoFeedAndRemovalIdentity() {
        let source = UUID()
        let reel = Story(title: "Reel", storyURL: "https://instagram.com/reel/ABC123/?igsh=one", sourceID: source, sourceName: "tv")
        let alias = Story(title: "Same post", storyURL: "https://www.instagram.com/p/ABC123/", sourceID: source, sourceName: "tv")
        let profile = Story(title: "Profile", storyURL: "https://instagram.com/person/", sourceID: source, sourceName: "tv")
        XCTAssertEqual(BookmarkFeedMode.youtube.stories(from: [reel, profile]).map(\.id), [reel.id])
        XCTAssertEqual(BookmarkFeedMode.other.stories(from: [reel, profile]).map(\.id), [profile.id])
        var library = BookmarkLibrary()
        library.remove(reel)
        XCTAssertTrue(library.isRemoved(alias))
        library.restore(alias)
        XCTAssertFalse(library.isRemoved(reel))
    }
}
