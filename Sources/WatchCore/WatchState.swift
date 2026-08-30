import Foundation

/// Which stories have been opened — the one thing Feed needs beyond its own
/// ranking. A story you've read no longer belongs in the queue, but reading it
/// isn't an opinion about it, so this is deliberately separate from
/// `VoteRecord`: unliking a story you've read would train the ranker on a
/// rating you never actually gave.
public struct WatchState: Codable, Sendable {
    public let readIDs: [String]

    public init(readIDs: [String] = []) {
        self.readIDs = readIDs
    }
}

public protocol WatchStateStore {
    func loadState() throws -> WatchState
    func saveState(_ state: WatchState) throws
}

public final class FileWatchStateStore: WatchStateStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadState() throws -> WatchState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return WatchState()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WatchState.self, from: data)
    }

    public func saveState(_ state: WatchState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
