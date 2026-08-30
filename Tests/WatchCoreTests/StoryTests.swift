import XCTest
@testable import WatchCore

final class StoryTests: XCTestCase {
    func testStoryIDIsStablePerSourceAndURL() {
        let sourceID = UUID()
        let a = Story(title: "A", storyURL: "https://example.com/a", sourceID: sourceID, sourceName: "Example")
        let b = Story(title: "A changed", storyURL: "https://example.com/a", sourceID: sourceID, sourceName: "Example")
        XCTAssertEqual(a.id, b.id)
    }
}
