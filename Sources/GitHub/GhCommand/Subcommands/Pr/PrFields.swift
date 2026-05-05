import Foundation
import GitHub

/// Field map for `gh pr list --json` and `gh pr view --json`. Field
/// names and JSON shapes mirror upstream gh exactly, so callers can
/// pipe output to the same scripts/jq filters they already use.
enum PrFields {
    static let map: [String: @Sendable (GraphQLPullRequest) -> Any?] = makeMap()

    private static func makeMap() -> [String: @Sendable (GraphQLPullRequest) -> Any?] {
        var m: [String: @Sendable (GraphQLPullRequest) -> Any?] = [:]
        m["additions"]               = { $0.additions }
        m["assignees"]               = { ($0.assignees?.nodes ?? []).map(userDict) }
        m["author"]                  = { $0.author.map(actorDict) }
        m["autoMergeRequest"]        = { $0.autoMergeRequest.map(autoMergeDict) }
        m["baseRefName"]             = { $0.baseRefName }
        m["baseRefOid"]              = { $0.baseRefOid }
        m["body"]                    = { $0.body }
        m["changedFiles"]            = { $0.changedFiles }
        m["closed"]                  = { $0.closedAt != nil }
        m["closedAt"]                = { $0.closedAt.map(JSONFieldSelector.iso8601) }
        m["closingIssuesReferences"] = { ($0.closingIssuesReferences?.nodes ?? []).map(issueRefDict) }
        m["comments"]                = { $0.comments?.totalCount ?? 0 }
        m["commits"]                 = { ($0.commits?.nodes ?? []).map(commitWrapDict) }
        m["createdAt"]               = { JSONFieldSelector.iso8601($0.createdAt) }
        m["deletions"]               = { $0.deletions }
        m["files"]                   = { ($0.files?.nodes ?? []).map(fileDict) }
        m["fullDatabaseId"]          = { $0.fullDatabaseId ?? "" }
        m["headRefName"]             = { $0.headRefName }
        m["headRefOid"]              = { $0.headRefOid }
        m["headRepository"]          = { $0.headRepository.map(repoStubDict) }
        m["headRepositoryOwner"]     = { $0.headRepositoryOwner.map(ownerDict) }
        m["id"]                      = { $0.id }
        m["isCrossRepository"]       = { $0.isCrossRepository }
        m["isDraft"]                 = { $0.isDraft }
        m["labels"]                  = { ($0.labels?.nodes ?? []).map(labelDict) }
        m["latestReviews"]           = { ($0.latestReviews?.nodes ?? []).map(reviewDict) }
        m["maintainerCanModify"]     = { $0.maintainerCanModify }
        m["mergeCommit"]             = { $0.mergeCommit.map(oidDict) }
        m["mergeStateStatus"]        = { $0.mergeStateStatus }
        m["mergeable"]               = { $0.mergeable }
        m["mergedAt"]                = { $0.mergedAt.map(JSONFieldSelector.iso8601) }
        m["mergedBy"]                = { $0.mergedBy.map(actorDict) }
        m["milestone"]               = { $0.milestone.map(milestoneDict) }
        m["number"]                  = { $0.number }
        m["potentialMergeCommit"]    = { $0.potentialMergeCommit.map(oidDict) }
        m["reactionGroups"]          = { ($0.reactionGroups ?? []).map(reactionGroupDict) }
        m["reviewDecision"]          = { $0.reviewDecision ?? "" }
        m["projectCards"]            = { _ in [] as [Any] }
        m["projectItems"]            = { ($0.projectItems?.nodes ?? []).map(projectItemDict) }
        m["reviewRequests"]          = { ($0.reviewRequests?.nodes ?? []).compactMap(reviewRequestDict) }
        m["reviews"]                 = { ($0.latestReviews?.nodes ?? []).map(reviewDict) }
        m["state"]                   = { $0.state }
        m["statusCheckRollup"]       = { statusCheckRollupArray($0) }
        m["title"]                   = { $0.title }
        m["updatedAt"]               = { JSONFieldSelector.iso8601($0.updatedAt) }
        m["url"]                     = { $0.url.absoluteString }
        return m
    }

    // MARK: Per-shape projectors

    static func actorDict(_ actor: GQLActor) -> [String: Any] {
        var dict: [String: Any] = [
            "id": actor.id ?? "",
            "is_bot": actor.typename == "Bot",
            "login": actor.login,
        ]
        if actor.typename != "Bot" { dict["name"] = actor.name ?? "" }
        return dict
    }

    static func ownerDict(_ owner: GQLOwner) -> [String: Any] {
        ["id": owner.id, "login": owner.login]
    }

    static func userDict(_ u: GQLUser) -> [String: Any] {
        [
            "id": u.id,
            "login": u.login,
            "name": u.name ?? "",
        ]
    }

    static func labelDict(_ l: GQLLabel) -> [String: Any] {
        [
            "id": l.id,
            "name": l.name,
            "color": l.color,
            "description": l.description ?? "",
        ]
    }

    static func milestoneDict(_ m: GQLMilestone) -> [String: Any] {
        [
            "number": m.number,
            "title": m.title,
            "description": m.description ?? "",
            "dueOn": m.dueOn.map(JSONFieldSelector.iso8601) ?? NSNull(),
        ]
    }

    static func repoStubDict(_ r: GQLRepoStub) -> [String: Any] {
        [
            "id": r.id,
            "name": r.name,
            "nameWithOwner": r.nameWithOwner,
        ]
    }

    static func issueRefDict(_ i: GQLIssueRef) -> [String: Any] {
        [
            "number": i.number,
            "title": i.title,
            "url": i.url.absoluteString,
            "state": i.state,
        ]
    }

    static func fileDict(_ f: GQLFile) -> [String: Any] {
        [
            "path": f.path,
            "additions": f.additions,
            "deletions": f.deletions,
        ]
    }

    static func commitWrapDict(_ c: GQLCommitWrap) -> [String: Any] {
        let cm = c.commit
        return [
            "oid": cm.oid,
            "messageHeadline": cm.messageHeadline,
            "messageBody": cm.messageBody,
            "committedDate": JSONFieldSelector.iso8601(cm.committedDate),
            "authoredDate": JSONFieldSelector.iso8601(cm.authoredDate),
            "additions": cm.additions ?? 0,
            "deletions": cm.deletions ?? 0,
            "authors": (cm.authors?.nodes ?? []).map(commitAuthorDict),
            "statusCheckRollup": cm.statusCheckRollup.map { ["state": $0.state] } ?? NSNull(),
        ]
    }

    static func commitAuthorDict(_ a: GQLCommitAuthor) -> [String: Any] {
        [
            "email": a.email ?? "",
            "name": a.name ?? "",
            "user": a.user.map { ["id": $0.id, "login": $0.login] } as Any? ?? NSNull(),
        ]
    }

    static func reviewDict(_ r: GQLReview) -> [String: Any] {
        [
            "id": r.id,
            "author": r.author.map { ["login": $0.login] } as Any? ?? NSNull(),
            "authorAssociation": r.authorAssociation,
            "body": r.body,
            "submittedAt": r.submittedAt.map(JSONFieldSelector.iso8601) ?? "",
            "includesCreatedEdit": r.includesCreatedEdit,
            "reactionGroups": (r.reactionGroups ?? []).map(reactionGroupDict),
            "state": r.state,
            "commit": r.commit.map { ["oid": $0.oid] } as Any? ?? NSNull(),
        ]
    }

    static func reactionGroupDict(_ g: GQLReactionGroup) -> [String: Any] {
        [
            "content": g.content,
            "users": ["totalCount": g.users?.totalCount ?? 0],
        ]
    }

    static func oidDict(_ o: GQLOid) -> [String: Any] { ["oid": o.oid] }

    static func autoMergeDict(_ a: GQLAutoMerge) -> [String: Any] {
        [
            "enabledAt": a.enabledAt.map(JSONFieldSelector.iso8601) ?? NSNull(),
            "mergeMethod": a.mergeMethod ?? "",
            "enabledBy": a.enabledBy.map { ["login": $0.login] } as Any? ?? NSNull(),
        ]
    }

    static func reviewRequestDict(_ rr: GQLReviewRequest) -> [String: Any]? {
        guard let r = rr.requestedReviewer else { return nil }
        var dict: [String: Any] = ["__typename": r.typename]
        if let login = r.login { dict["login"] = login }
        if let name = r.name { dict["name"] = name }
        if let slug = r.slug { dict["slug"] = slug }
        return dict
    }

    static func projectItemDict(_ p: GQLProjectItem) -> [String: Any] {
        var dict: [String: Any] = ["id": p.id]
        if let proj = p.project {
            dict["project"] = [
                "id": proj.id,
                "title": proj.title,
                "number": proj.number,
                "url": proj.url.absoluteString,
            ]
        }
        if let status = p.fieldValueByName {
            dict["status"] = [
                "name": status.name ?? "",
                "optionId": status.optionId ?? "",
            ]
        } else {
            dict["status"] = NSNull()
        }
        return dict
    }

    static func statusCheckRollupArray(_ p: GraphQLPullRequest) -> [[String: Any]] {
        guard let last = p.statusCheckRollup?.nodes.last,
              let contexts = last.commit.statusCheckRollup?.contexts?.nodes
        else { return [] }
        return contexts.map(statusCheckContextDict)
    }

    static func statusCheckContextDict(_ c: GQLStatusCheckContext) -> [String: Any] {
        switch c.typename {
        case "CheckRun":
            return [
                "__typename": "CheckRun",
                "name": c.name ?? "",
                "status": c.status ?? "",
                "conclusion": c.conclusion ?? "",
                "startedAt": c.startedAt.map(JSONFieldSelector.iso8601) ?? "",
                "completedAt": c.completedAt.map(JSONFieldSelector.iso8601) ?? "",
                "detailsUrl": c.detailsUrl?.absoluteString ?? "",
                "workflowName": c.checkSuite?.workflowRun?.workflow.name ?? "",
                "event": c.checkSuite?.workflowRun?.event ?? "",
            ]
        case "StatusContext":
            return [
                "__typename": "StatusContext",
                "context": c.context ?? "",
                "state": c.state ?? "",
                "targetUrl": c.targetUrl?.absoluteString ?? "",
                "description": c.description ?? "",
                "createdAt": c.createdAt.map(JSONFieldSelector.iso8601) ?? "",
            ]
        default:
            return ["__typename": c.typename]
        }
    }
}
