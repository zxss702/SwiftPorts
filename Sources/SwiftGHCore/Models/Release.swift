import Foundation

public struct Release: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let tagName: String
    public let targetCommitish: String
    public let name: String?
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let createdAt: Date
    public let publishedAt: Date?
    public let author: User
    public let assets: [ReleaseAsset]
    public let tarballUrl: URL?
    public let zipballUrl: URL?
    public let url: URL
    public let htmlUrl: URL
    public let assetsUrl: URL
    public let uploadUrl: String  // RFC 6570 URI template
}
