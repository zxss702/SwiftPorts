import Foundation

public struct GistFile: Codable, Sendable {
    public let filename: String
    public let type: String
    public let language: String?
    public let rawUrl: URL
    public let size: Int
    public let truncated: Bool?
    public let content: String?
    public let encoding: String?
}
