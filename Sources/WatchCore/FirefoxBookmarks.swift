import Foundation
import SQLite3

public enum FirefoxBookmarks {
    public static let sourceID = UUID(uuidString: "31D649E7-7715-4334-A6B5-E037218F5A92")!

    public enum Failure: LocalizedError {
        case unavailable(String)
        public var errorDescription: String? {
            switch self { case .unavailable(let reason): return reason }
        }
    }

    public static func load(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Firefox")) throws -> [Story] {
        let fm = FileManager.default
        let profiles = try fm.contentsOfDirectory(at: root.appendingPathComponent("Profiles"), includingPropertiesForKeys: nil)
        let ini = (try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8)) ?? ""
        let preferred = ini.components(separatedBy: .newlines).first { $0.hasPrefix("Default=Profiles/") }?.replacingOccurrences(of: "Default=Profiles/", with: "")
        let ordered = profiles.sorted { a, b in
            if a.lastPathComponent == preferred { return true }
            if b.lastPathComponent == preferred { return false }
            return a.lastPathComponent < b.lastPathComponent
        }
        for profile in ordered where fm.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path) {
            if let stories = try snapshot(profile.appendingPathComponent("places.sqlite")) { return stories }
        }
        throw Failure.unavailable("No tv bookmark folder found in Firefox.")
    }

    // Firefox holds an exclusive database lock. Copy the database and WAL,
    // checking that neither changed during the copy, then recover locally.
    private static func snapshot(_ database: URL) throws -> [Story]? {
        let fm = FileManager.default
        let files = [database, URL(fileURLWithPath: database.path + "-wal")]
        func signatures() throws -> [String] {
            try files.map { file in
                guard fm.fileExists(atPath: file.path) else { return "missing" }
                let attrs = try fm.attributesOfItem(atPath: file.path)
                return "\(attrs[.size]!)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            }
        }
        for _ in 0..<3 {
            let directory = fm.temporaryDirectory.appendingPathComponent("watch-bookmarks-" + UUID().uuidString)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: directory) }
            let before = try signatures()
            for file in files where fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
            }
            guard before == (try signatures()) else { continue }
            return try read(database: directory.appendingPathComponent("places.sqlite"))
        }
        throw Failure.unavailable("Firefox is updating bookmarks. Try refreshing again.")
    }

    static func read(database: URL) throws -> [Story]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw Failure.unavailable("Could not read Firefox bookmarks.")
        }
        defer { sqlite3_close(db) }
        let sql = """
        WITH RECURSIVE tree(id,depth) AS (
          SELECT id,0 FROM moz_bookmarks WHERE guid IN ('menu________','toolbar_____')
          UNION ALL SELECT b.id,tree.depth+1 FROM moz_bookmarks b JOIN tree ON b.parent=tree.id WHERE b.type=2
        ), chosen(id) AS (
          SELECT b.id FROM moz_bookmarks b JOIN tree ON b.id=tree.id WHERE lower(b.title)='tv'
          ORDER BY tree.depth,b.id DESC LIMIT 1
        ), folders(id) AS (
          SELECT id FROM chosen
          UNION SELECT b.id FROM moz_bookmarks b JOIN folders f ON b.parent=f.id WHERE b.type=2
        )
        SELECT b.title,p.url,b.dateAdded FROM moz_bookmarks b
        JOIN folders f ON b.parent=f.id JOIN moz_places p ON p.id=b.fk
        WHERE b.type=1
        UNION ALL SELECT NULL,NULL,NULL FROM folders
        ORDER BY 3 DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.unavailable("Firefox's bookmark database could not be queried.")
        }
        defer { sqlite3_finalize(statement) }
        var found = false
        var seen = Set<String>()
        var stories: [Story] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            found = true
            if let raw = sqlite3_column_text(statement, 1) {
                let address = String(cString: raw)
                if let url = URL(string: address), ["https", "http"].contains(url.scheme ?? "") {
                    let video = YouTubeVideo(url: url)
                    let key = video.map { "youtube:\($0.id)" } ?? address
                    if seen.insert(key).inserted {
                        let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? url.host ?? address
                        let date = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1_000_000)
                        var story = Story(title: title, storyURL: address, sourceID: sourceID, sourceName: "Firefox · tv", imageURL: video?.thumbnailURL, fetchedAt: date)
                        story.video = video.map { _ in VideoInfo(url: address) }
                        stories.append(story)
                    }
                }
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw Failure.unavailable("Firefox bookmark reading was interrupted.") }
        return found ? stories : nil
    }
}
