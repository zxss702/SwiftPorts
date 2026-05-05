import Foundation
import GitHub

/// Field map for `gh issue list --json` and `gh issue view --json`.
enum IssueFields {
    static let map: [String: @Sendable (GraphQLIssue) -> Any?] = makeMap()

    private static func makeMap() -> [String: @Sendable (GraphQLIssue) -> Any?] {
        var m: [String: @Sendable (GraphQLIssue) -> Any?] = [:]
        m["assignees"]                       = { ($0.assignees?.nodes ?? []).map(PrFields.userDict) }
        m["author"]                          = { $0.author.map(PrFields.actorDict) }
        m["body"]                            = { $0.body }
        m["closed"]                          = { $0.closedAt != nil }
        m["closedAt"]                        = { $0.closedAt.map(JSONFieldSelector.iso8601) }
        m["closedByPullRequestsReferences"]  = { ($0.closedByPullRequestsReferences?.nodes ?? []).map(PrFields.issueRefDict) }
        m["comments"]                        = { $0.comments?.totalCount ?? 0 }
        m["createdAt"]                       = { JSONFieldSelector.iso8601($0.createdAt) }
        m["id"]                              = { $0.id }
        m["isPinned"]                        = { $0.isPinned }
        m["labels"]                          = { ($0.labels?.nodes ?? []).map(PrFields.labelDict) }
        m["milestone"]                       = { $0.milestone.map(PrFields.milestoneDict) }
        m["number"]                          = { $0.number }
        m["projectCards"]                    = { _ in [] as [Any] }   // classic projects (deprecated)
        m["projectItems"]                    = { _ in [] as [Any] }   // requires extra GraphQL block
        m["reactionGroups"]                  = { ($0.reactionGroups ?? []).map(PrFields.reactionGroupDict) }
        m["state"]                           = { $0.state }
        m["stateReason"]                     = { $0.stateReason ?? "" }
        m["title"]                           = { $0.title }
        m["updatedAt"]                       = { JSONFieldSelector.iso8601($0.updatedAt) }
        m["url"]                             = { $0.url.absoluteString }
        return m
    }
}
