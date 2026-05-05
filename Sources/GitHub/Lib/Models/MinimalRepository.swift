import Foundation

/// The slimmed-down "minimal-repository" shape GitHub embeds in
/// search-code / search-commits / many other list payloads. Strictly
/// fewer fields than ``Repository``; everything beyond the basics is
/// optional because endpoints disagree on exactly which extras to
/// include.
public struct MinimalRepository: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let name: String
    public let fullName: String
    public let owner: User
    public let `private`: Bool
    public let htmlUrl: URL
    public let description: String?
    public let fork: Bool
    public let url: URL
    public let homepage: String?
    public let language: String?
    public let defaultBranch: String?
    public let visibility: Visibility?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let pushedAt: Date?
    public let stargazersCount: Int?
    public let watchersCount: Int?
    public let forksCount: Int?
    public let openIssuesCount: Int?
    public let topics: [String]?
    public let archived: Bool?
    public let disabled: Bool?
    public let license: License?
    public let size: Int?
    public let hasIssues: Bool?
    public let hasProjects: Bool?
    public let hasWiki: Bool?
    public let hasPages: Bool?
    public let hasDownloads: Bool?
    public let hasDiscussions: Bool?
}
