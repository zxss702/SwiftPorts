import Foundation

public struct Label: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let url: URL
    public let name: String
    public let color: String
    public let `default`: Bool
    public let description: String?
}
