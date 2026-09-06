import XCTest
import WatchCore
@testable import WatchApp

final class PlaybackProgressTests: XCTestCase {
    @MainActor
    func testResumePersistsByVideoIDAndCompletionRestarts() throws {
        let suite = "WatchProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let video = try XCTUnwrap(YouTubeVideo(url: URL(string: "https://youtu.be/jNas99oEXBU?t=60")!))
        let progress = PlaybackProgress(defaults: defaults)
        XCTAssertEqual(progress.start(for: video), 60)
        progress.save(900.5, for: video.id)
        let reopened = PlaybackProgress(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        let sameVideo = try XCTUnwrap(YouTubeVideo(url: URL(string: "https://youtube.com/watch?v=jNas99oEXBU")!))
        XCTAssertEqual(reopened.start(for: sameVideo), 900)
        progress.save(.nan, for: video.id)
        progress.save(-1, for: video.id)
        XCTAssertEqual(reopened.start(for: video), 900)
        progress.save(950, for: video.id, ended: true)
        XCTAssertEqual(reopened.start(for: video), 0)
    }
}
