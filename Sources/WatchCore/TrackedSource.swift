import Foundation

public struct TrackedSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: String
    public var name: String

    public init(id: UUID = UUID(), url: String, name: String = "") {
        self.id = id
        self.url = url
        self.name = name
    }
}
