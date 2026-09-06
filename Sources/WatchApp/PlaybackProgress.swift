import Foundation
import WatchCore

/// Positions belong to video IDs, not bookmark URLs or timestamps.
@MainActor
struct PlaybackProgress {
    var defaults: UserDefaults = .standard
    private func key(_ id: String) -> String { "WatchPlaybackPosition.\(id)" }

    func start(for video: YouTubeVideo) -> Int {
        guard defaults.object(forKey: key(video.id)) != nil else { return video.start }
        return max(0, Int(defaults.double(forKey: key(video.id))))
    }

    func save(_ seconds: Double, for id: String, ended: Bool = false) {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return }
        defaults.set(ended ? 0 : seconds, forKey: key(id))
    }
}
