import Foundation

/// A GitHub account — user, organization, or bot.
///
/// REST returns this on issues, PRs, comments, repo owners, etc.
/// Many fields are optional because the "minimal user" representation
/// embedded in nested responses omits most of them.
public struct User: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let login: String
    public let avatarUrl: URL
    public let htmlUrl: URL
    public let type: UserType
    public let siteAdmin: Bool
    public let name: String?
    public let company: String?
    public let blog: String?
    public let location: String?
    public let email: String?
    public let bio: String?
    public let publicRepos: Int?
    public let publicGists: Int?
    public let followers: Int?
    public let following: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
}
