import Foundation

/// GraphQL queries for `gh issue list/view --json`. Mirrors upstream's
/// field set so output is byte-identical.
public enum IssueQueries {

    private static let issueFields = """
        id
        number
        title
        state
        stateReason
        body
        url
        createdAt
        updatedAt
        closedAt
        isPinned
        author {
          __typename
          login
          ... on User { id name }
          ... on Bot { id }
        }
        labels(first: 100) {
          nodes { id name color description }
        }
        assignees(first: 100) {
          nodes { id login name }
        }
        milestone {
          number title description dueOn
        }
        comments(first: 0) { totalCount }
        reactionGroups {
          content
          users(first: 0) { totalCount }
          reactors(first: 0) { totalCount }
        }
        closedByPullRequestsReferences(first: 100) {
          nodes { number title url state }
        }
        """

    public static func list() -> String {
        """
        query($owner: String!, $name: String!, $first: Int!, $states: [IssueState!], $labels: [String!]) {
          repository(owner: $owner, name: $name) {
            issues(
              first: $first,
              states: $states,
              labels: $labels,
              orderBy: {field: CREATED_AT, direction: DESC}
            ) {
              totalCount
              nodes {
                \(issueFields)
              }
            }
          }
        }
        """
    }

    public static let view = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) {
              \(issueFields)
            }
          }
        }
        """
}

public struct IssueListResponse: Codable, Sendable {
    public let repository: Container?
    public struct Container: Codable, Sendable {
        public let issues: IssueConnection
    }
}

public struct IssueViewResponse: Codable, Sendable {
    public let repository: Container?
    public struct Container: Codable, Sendable {
        public let issue: GraphQLIssue?
    }
}

public struct IssueConnection: Codable, Sendable {
    public let totalCount: Int
    public let nodes: [GraphQLIssue]
}

public struct GraphQLIssue: Codable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let state: String
    public let stateReason: String?
    public let body: String
    public let url: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let isPinned: Bool
    public let author: GQLActor?
    public let labels: GQLNodeList<GQLLabel>?
    public let assignees: GQLNodeList<GQLUser>?
    public let milestone: GQLMilestone?
    public let comments: GQLCount?
    public let reactionGroups: [GQLReactionGroup]?
    public let closedByPullRequestsReferences: GQLNodeList<GQLIssueRef>?
}
