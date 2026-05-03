import Foundation

/// `head` / `base` of a pull request — points at a branch on a repo.
public struct PullRequestRef: Codable, Sendable {
    public let label: String
    public let ref: String
    public let sha: String
    public let user: User?
    public let repo: Repository?
}
