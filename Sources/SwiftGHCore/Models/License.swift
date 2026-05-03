import Foundation

public struct License: Codable, Sendable {
    public let key: String
    public let name: String
    public let spdxId: String?
    public let url: URL?
    public let nodeId: String?
}
