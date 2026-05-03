import Foundation

public struct Gist: Codable, Sendable, Identifiable {
    public let id: String
    public let nodeId: String
    public let url: URL
    public let htmlUrl: URL
    public let gitPullUrl: URL
    public let gitPushUrl: URL
    public let commitsUrl: URL
    public let forksUrl: URL
    public let `public`: Bool
    public let description: String?
    public let comments: Int
    public let user: User?
    public let owner: User?
    public let truncated: Bool?
    public let createdAt: Date
    public let updatedAt: Date
    public let files: [String: GistFile]
}
