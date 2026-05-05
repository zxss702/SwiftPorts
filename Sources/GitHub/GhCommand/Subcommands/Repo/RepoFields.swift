import Foundation
import GitHub

/// Field map for `gh repo list --json` and `gh repo view --json`.
enum RepoFields {
    static let map: [String: @Sendable (GraphQLRepository) -> Any?] = makeMap()

    private static func makeMap() -> [String: @Sendable (GraphQLRepository) -> Any?] {
        var m: [String: @Sendable (GraphQLRepository) -> Any?] = [:]
        m["archivedAt"]                    = { $0.archivedAt.map(JSONFieldSelector.iso8601) }
        m["assignableUsers"]               = { _ in [] as [Any] }
        m["codeOfConduct"]                 = { _ in NSNull() }
        m["contactLinks"]                  = { _ in [] as [Any] }
        m["createdAt"]                     = { JSONFieldSelector.iso8601($0.createdAt) }
        m["defaultBranchRef"]              = { $0.defaultBranchRef.map { ["name": $0.name] } }
        m["deleteBranchOnMerge"]           = { $0.deleteBranchOnMerge }
        m["description"]                   = { $0.description ?? "" }
        m["diskUsage"]                     = { $0.diskUsage ?? 0 }
        m["forkCount"]                     = { $0.forkCount }
        m["fundingLinks"]                  = { _ in [] as [Any] }
        m["hasDiscussionsEnabled"]         = { $0.hasDiscussionsEnabled }
        m["hasIssuesEnabled"]              = { $0.hasIssuesEnabled }
        m["hasProjectsEnabled"]            = { $0.hasProjectsEnabled }
        m["hasWikiEnabled"]                = { $0.hasWikiEnabled }
        m["homepageUrl"]                   = { $0.homepageUrl?.absoluteString ?? "" }
        m["id"]                            = { $0.id }
        m["isArchived"]                    = { $0.isArchived }
        m["isBlankIssuesEnabled"]          = { $0.isBlankIssuesEnabled }
        m["isEmpty"]                       = { $0.isEmpty }
        m["isFork"]                        = { $0.isFork }
        m["isInOrganization"]              = { $0.isInOrganization }
        m["isMirror"]                      = { $0.isMirror }
        m["isPrivate"]                     = { $0.isPrivate }
        m["isSecurityPolicyEnabled"]       = { $0.isSecurityPolicyEnabled ?? false }
        m["isTemplate"]                    = { $0.isTemplate }
        m["isUserConfigurationRepository"] = { $0.isUserConfigurationRepository }
        m["issueTemplates"]                = { _ in [] as [Any] }
        m["issues"]                        = { ["totalCount": $0.issues?.totalCount ?? 0] }
        m["labels"]                        = { _ in ["totalCount": 0] as [String: Any] }
        m["languages"]                     = { languagesArray($0) }
        m["latestRelease"]                 = { $0.latestRelease.map(latestReleaseDict) }
        m["licenseInfo"]                   = { $0.licenseInfo.map(licenseDict) }
        m["mentionableUsers"]              = { _ in [] as [Any] }
        m["mergeCommitAllowed"]            = { $0.mergeCommitAllowed }
        m["milestones"]                    = { _ in [] as [Any] }
        m["mirrorUrl"]                     = { $0.mirrorUrl?.absoluteString ?? "" }
        m["name"]                          = { $0.name }
        m["nameWithOwner"]                 = { $0.nameWithOwner }
        m["openGraphImageUrl"]             = { $0.openGraphImageUrl?.absoluteString ?? "" }
        m["owner"]                         = { $0.owner.map(ownerDict) }
        m["parent"]                        = { $0.parent.map(repoParentDict) }
        m["primaryLanguage"]               = { $0.primaryLanguage.map { ["name": $0.name] } }
        m["projects"]                      = { _ in ["totalCount": 0] as [String: Any] }
        m["projectsV2"]                    = { _ in ["totalCount": 0] as [String: Any] }
        m["pullRequestTemplates"]          = { _ in [] as [Any] }
        m["pullRequests"]                  = { ["totalCount": $0.pullRequests?.totalCount ?? 0] }
        m["pushedAt"]                      = { $0.pushedAt.map(JSONFieldSelector.iso8601) }
        m["rebaseMergeAllowed"]            = { $0.rebaseMergeAllowed }
        m["repositoryTopics"]              = { topicsArray($0) }
        m["securityPolicyUrl"]             = { $0.securityPolicyUrl?.absoluteString ?? "" }
        m["squashMergeAllowed"]            = { $0.squashMergeAllowed }
        m["sshUrl"]                        = { $0.sshUrl }
        m["stargazerCount"]                = { $0.stargazerCount }
        m["templateRepository"]            = { $0.templateRepository.map(repoParentDict) }
        m["updatedAt"]                     = { JSONFieldSelector.iso8601($0.updatedAt) }
        m["url"]                           = { $0.url.absoluteString }
        m["usesCustomOpenGraphImage"]      = { $0.usesCustomOpenGraphImage }
        m["viewerCanAdminister"]           = { $0.viewerCanAdminister }
        m["viewerDefaultCommitEmail"]      = { $0.viewerDefaultCommitEmail ?? "" }
        m["viewerDefaultMergeMethod"]      = { $0.viewerDefaultMergeMethod ?? "" }
        m["viewerHasStarred"]              = { $0.viewerHasStarred }
        m["viewerPermission"]              = { $0.viewerPermission ?? "" }
        m["viewerPossibleCommitEmails"]    = { _ in [] as [Any] }
        m["viewerSubscription"]            = { $0.viewerSubscription ?? "" }
        m["visibility"]                    = { $0.visibility }
        m["watchers"]                      = { ["totalCount": $0.watchers?.totalCount ?? 0] }
        return m
    }

    static func ownerDict(_ owner: GQLOwner) -> [String: Any] {
        ["id": owner.id, "login": owner.login]
    }

    static func licenseDict(_ l: GQLLicenseInfo) -> [String: Any] {
        [
            "key": l.key,
            "name": l.name,
            "nickname": l.nickname ?? "",
            "spdxId": l.spdxId ?? "",
            "url": l.url?.absoluteString ?? "",
        ]
    }

    static func languagesArray(_ r: GraphQLRepository) -> [[String: Any]] {
        (r.languages?.edges ?? []).map {
            ["size": $0.size, "node": ["name": $0.node.name, "id": $0.node.id ?? ""]]
        }
    }

    static func topicsArray(_ r: GraphQLRepository) -> [[String: Any]] {
        (r.repositoryTopics?.nodes ?? []).map { ["name": $0.topic.name] }
    }

    static func repoParentDict(_ p: GQLRepoParent) -> [String: Any] {
        [
            "id": p.id,
            "name": p.name,
            "nameWithOwner": p.nameWithOwner,
            "owner": p.owner.map(ownerDict) ?? NSNull(),
            "isPrivate": p.isPrivate,
            "url": p.url.absoluteString,
        ]
    }

    static func latestReleaseDict(_ r: GQLLatestRelease) -> [String: Any] {
        [
            "tagName": r.tagName,
            "name": r.name ?? "",
            "url": r.url.absoluteString,
            "isDraft": r.isDraft,
            "isPrerelease": r.isPrerelease,
            "publishedAt": r.publishedAt.map(JSONFieldSelector.iso8601) ?? NSNull(),
            "createdAt": JSONFieldSelector.iso8601(r.createdAt),
        ]
    }
}
