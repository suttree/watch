import XCTest
@testable import WatchApp

final class PlayerKeyboardTests: XCTestCase {
    @MainActor
    func testOnlyHorizontalArrowsSeek() {
        XCTAssertEqual(BookmarkVideoPlayer.Coordinator.seekOffset(for: 123), -5)
        XCTAssertEqual(BookmarkVideoPlayer.Coordinator.seekOffset(for: 124), 5)
        for key: UInt16 in [0, 49, 53, 125, 126] {
            XCTAssertNil(BookmarkVideoPlayer.Coordinator.seekOffset(for: key))
        }
    }
}
