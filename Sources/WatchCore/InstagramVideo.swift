import Foundation

public struct InstagramVideo: Equatable, Sendable {
    public let id: String
    public let kind: String

    public init?(url: URL) {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, ["reel", "reels", "p", "tv"].contains(parts[0]),
              parts[1].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        id = parts[1]
        kind = parts[0] == "reels" ? "reel" : parts[0]
    }

    public var embedURL: URL { URL(string: "https://www.instagram.com/\(kind)/\(id)/embed/")! }
}

public enum BookmarkVideo: Equatable, Sendable {
    case youtube(YouTubeVideo)
    case instagram(InstagramVideo)

    public init?(url: URL) {
        if let video = YouTubeVideo(url: url) { self = .youtube(video) }
        else if let video = InstagramVideo(url: url) { self = .instagram(video) }
        else { return nil }
    }

    public var key: String {
        switch self {
        case .youtube(let video): return "youtube:\(video.id)"
        case .instagram(let video): return "instagram:\(video.id)"
        }
    }

    public var thumbnailURL: String? {
        if case .youtube(let video) = self { return video.thumbnailURL }
        return nil
    }
}
