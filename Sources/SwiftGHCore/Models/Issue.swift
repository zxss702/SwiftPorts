import Foundation

/// A GitHub issue. Pull requests are also returned by the issues API
/// (with `pullRequest != nil`); for PR-specific fields use ``PullRequest``.
public struct Issue: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let number: Int
    public let title: String
    public let body: String?
    public let state: IssueState
    public let stateReason: String?
    public let locked: Bool
    public let activeLockReason: String?
    public let comments: Int
    public let user: User
    public let assignees: [User]
    public let labels: [Label]
    public let milestone: Milestone?
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let htmlUrl: URL
    public let url: URL
    public let commentsUrl: URL
    public let eventsUrl: URL
    public let labelsUrl: String  // template, contains `{/name}`
    public let repositoryUrl: URL
    public let authorAssociation: AuthorAssociation
    public let draft: Bool?
    public let pullRequest: IssuePullRequestRef?
    public let reactions: Reactions?
}

public struct IssuePullRequestRef: Codable, Sendable {
    public let url: URL
    public let htmlUrl: URL
    public let diffUrl: URL
    public let patchUrl: URL
    public let mergedAt: Date?
}
