import Foundation

/// A GitHub repository as returned by the REST API.
///
/// Mirrors `GET /repos/{owner}/{repo}` plus the trimmed shape
/// returned in lists.
public struct Repository: Codable, Sendable, Identifiable {
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
    public let forksCount: Int
    public let stargazersCount: Int
    public let watchersCount: Int
    public let size: Int
    public let defaultBranch: String
    public let openIssuesCount: Int
    public let isTemplate: Bool?
    public let topics: [String]?
    public let hasIssues: Bool
    public let hasProjects: Bool
    public let hasWiki: Bool
    public let hasPages: Bool
    public let hasDownloads: Bool
    public let hasDiscussions: Bool?
    public let archived: Bool
    public let disabled: Bool
    public let visibility: Visibility?
    public let pushedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let license: License?
    public let allowForking: Bool?
    public let webCommitSignoffRequired: Bool?
    public let permissions: Permissions?
    public let networkCount: Int?
    public let subscribersCount: Int?

    // `parent` and `source` are recursive `Repository` references on
    // forks. Omitted here because Swift structs can't recursively
    // contain themselves; reintroduce via a reference-typed wrapper
    // (`final class`) when fork support actually lands.
}
