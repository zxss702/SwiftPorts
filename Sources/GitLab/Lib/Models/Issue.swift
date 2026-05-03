import Foundation

/// A GitLab issue. Identified by `iid` (per-project) — that's the
/// number users see in URLs like `/-/issues/123`. The global `id` is
/// rarely useful in the CLI.
public struct Issue: Codable, Sendable, Identifiable {
    public let id: Int
    public let iid: Int
    public let projectId: Int
    public let title: String
    public let description: String?
    public let state: IssueState
    public let confidential: Bool
    public let discussionLocked: Bool?
    public let labels: [String]
    public let milestone: Milestone?
    public let author: User?
    public let assignees: [User]
    public let assignee: User?
    public let userNotesCount: Int?
    public let upvotes: Int?
    public let downvotes: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let closedAt: Date?
    public let dueDate: String?
    public let webUrl: URL
    public let issueType: String?
    public let hasTasks: Bool?
    public let taskStatus: String?
}
