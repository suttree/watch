import Foundation

public protocol SourceStore {
    func loadSources() throws -> [TrackedSource]
    func saveSources(_ sources: [TrackedSource]) throws
}

public final class FileSourceStore: SourceStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadSources() throws -> [TrackedSource] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([TrackedSource].self, from: data)
    }

    public func saveSources(_ sources: [TrackedSource]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(sources)
        try data.write(to: fileURL, options: .atomic)
    }
}
