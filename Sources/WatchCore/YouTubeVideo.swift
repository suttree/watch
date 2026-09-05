import Foundation

public struct YouTubeVideo: Equatable, Sendable {
    public let id: String
    public let start: Int

    public init?(url: URL) {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var identifier: String?
        if host == "youtu.be" {
            identifier = parts.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "www.youtube-nocookie.com" {
            if parts.first == "watch" { identifier = query.first { $0.name == "v" }?.value }
            if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) { identifier = parts[1] }
        }
        guard let identifier, identifier.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        id = identifier
        let raw = query.first { $0.name == "t" || $0.name == "start" }?.value ?? "0"
        if let seconds = Int(raw) { start = max(0, seconds) }
        else {
            let regex = try! NSRegularExpression(pattern: "(\\d+)([hms])")
            start = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reduce(0) { total, match in
                let n = Int((raw as NSString).substring(with: match.range(at: 1))) ?? 0
                let unit = (raw as NSString).substring(with: match.range(at: 2))
                return total + n * (unit == "h" ? 3600 : unit == "m" ? 60 : 1)
            }
        }
    }

    public var thumbnailURL: String { "https://i.ytimg.com/vi/\(id)/hqdefault.jpg" }
    public var embedURL: URL { URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&start=\(start)")! }
}
