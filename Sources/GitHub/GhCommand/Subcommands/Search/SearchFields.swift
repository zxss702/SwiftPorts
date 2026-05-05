import Foundation
import GitHub

/// Field maps for `gh search *` subcommands. Search uses REST endpoints
/// upstream, so these run on our existing `Issue`, `Repository`,
/// `CodeSearchItem`, and `CommitSearchItem` models.
enum SearchFields {

    // MARK: search issues / search prs

    static let issues: [String: @Sendable (Issue) -> Any?] = makeIssuesMap()

    private static func makeIssuesMap() -> [String: @Sendable (Issue) -> Any?] {
        var m: [String: @Sendable (Issue) -> Any?] = [:]
        m["assignees"]         = { $0.assignees.map(searchUserDict) }
        m["author"]            = { searchUserDict($0.user) }
        m["authorAssociation"] = { $0.authorAssociation.rawValue }
        m["body"]              = { $0.body ?? "" }
        m["closedAt"]          = { JSONFieldSelector.iso8601($0.closedAt ?? Date(timeIntervalSince1970: -62135596800)) }
        m["commentsCount"]     = { $0.comments }
        m["createdAt"]         = { JSONFieldSelector.iso8601($0.createdAt) }
        m["id"]                = { $0.nodeId }
        m["isLocked"]          = { $0.locked }
        m["isPullRequest"]     = { $0.pullRequest != nil }
        m["labels"]            = { $0.labels.map(searchLabelDict) }
        m["number"]            = { $0.number }
        m["repository"]        = { repositoryFromURL($0.repositoryUrl) }
        m["state"]             = { $0.state.rawValue }
        m["title"]             = { $0.title }
        m["updatedAt"]         = { JSONFieldSelector.iso8601($0.updatedAt) }
        m["url"]               = { $0.htmlUrl.absoluteString }
        return m
    }

    static func searchUserDict(_ u: User) -> [String: Any] {
        [
            "id":     u.nodeId,
            "is_bot": u.type == .bot,
            "login":  u.login,
            "type":   u.type.rawValue.capitalized,
            "url":    u.htmlUrl.absoluteString,
        ]
    }

    static func searchLabelDict(_ l: Label) -> [String: Any] {
        [
            "id":          l.nodeId,
            "name":        l.name,
            "color":       l.color,
            "description": l.description ?? "",
        ]
    }

    /// Convert `https://api.github.com/repos/owner/name` → `{name, nameWithOwner}`.
    static func repositoryFromURL(_ url: URL) -> [String: Any] {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return ["name": "", "nameWithOwner": ""] }
        let owner = parts[parts.count - 2]
        let name = parts[parts.count - 1]
        return ["name": name, "nameWithOwner": "\(owner)/\(name)"]
    }

    // MARK: search repos

    static let repos: [String: @Sendable (Repository) -> Any?] = makeReposMap()

    private static func makeReposMap() -> [String: @Sendable (Repository) -> Any?] {
        var m: [String: @Sendable (Repository) -> Any?] = [:]
        m["createdAt"]       = { JSONFieldSelector.iso8601($0.createdAt) }
        m["defaultBranch"]   = { $0.defaultBranch }
        m["description"]     = { $0.description ?? "" }
        m["forksCount"]      = { $0.forksCount }
        m["fullName"]        = { $0.fullName }
        m["hasDownloads"]    = { $0.hasDownloads }
        m["hasIssues"]       = { $0.hasIssues }
        m["hasPages"]        = { $0.hasPages }
        m["hasProjects"]     = { $0.hasProjects }
        m["hasWiki"]         = { $0.hasWiki }
        m["homepage"]        = { $0.homepage ?? "" }
        m["id"]              = { $0.nodeId }
        m["isArchived"]      = { $0.archived }
        m["isDisabled"]      = { $0.disabled }
        m["isFork"]          = { $0.fork }
        m["isPrivate"]       = { $0.private }
        m["language"]        = { $0.language ?? "" }
        m["license"]         = { $0.license.map(searchLicenseDict) ?? NSNull() }
        m["name"]            = { $0.name }
        m["openIssuesCount"] = { $0.openIssuesCount }
        m["owner"]           = { searchUserDict($0.owner) }
        m["pushedAt"]        = { $0.pushedAt.map(JSONFieldSelector.iso8601) ?? "" }
        m["size"]            = { $0.size }
        m["stargazersCount"] = { $0.stargazersCount }
        m["updatedAt"]       = { JSONFieldSelector.iso8601($0.updatedAt) }
        m["url"]             = { $0.htmlUrl.absoluteString }
        m["visibility"]      = { $0.visibility?.rawValue ?? ($0.private ? "private" : "public") }
        m["watchersCount"]   = { $0.watchersCount }
        return m
    }

    static func searchLicenseDict(_ l: License) -> [String: Any] {
        [
            "key":    l.key,
            "name":   l.name,
            "spdxId": l.spdxId ?? "",
            "url":    l.url?.absoluteString ?? "",
        ]
    }

    // MARK: search code

    static let code: [String: @Sendable (CodeSearchItem) -> Any?] = makeCodeMap()

    private static func makeCodeMap() -> [String: @Sendable (CodeSearchItem) -> Any?] {
        var m: [String: @Sendable (CodeSearchItem) -> Any?] = [:]
        m["path"]        = { $0.path }
        m["repository"]  = { codeRepositoryDict($0.repository) }
        m["sha"]         = { $0.sha }
        m["textMatches"] = { _ in [] as [Any] }
        m["url"]         = { $0.htmlUrl.absoluteString }
        return m
    }

    /// Slim repo shape used by `search code` — upstream emits 5 keys.
    static func codeRepositoryDict(_ r: MinimalRepository) -> [String: Any] {
        [
            "id":            r.nodeId,
            "isFork":        r.fork,
            "isPrivate":     r.private,
            "nameWithOwner": r.fullName,
            "url":           r.htmlUrl.absoluteString,
        ]
    }

    /// Richer repo shape used by `search commits` — adds description,
    /// fullName, name, and owner.
    static func commitRepositoryDict(_ r: MinimalRepository) -> [String: Any] {
        [
            "id":          r.nodeId,
            "name":        r.name,
            "fullName":    r.fullName,
            "url":         r.htmlUrl.absoluteString,
            "description": r.description ?? "",
            "isFork":      r.fork,
            "isPrivate":   r.private,
            "owner":       searchUserDict(r.owner),
        ]
    }

    // MARK: search commits

    static let commits: [String: @Sendable (CommitSearchItem) -> Any?] = makeCommitsMap()

    private static func makeCommitsMap() -> [String: @Sendable (CommitSearchItem) -> Any?] {
        var m: [String: @Sendable (CommitSearchItem) -> Any?] = [:]
        m["author"]     = { $0.author.map(searchUserDict) ?? NSNull() }
        m["commit"]     = { commitInnerDict($0) }
        m["committer"]  = { $0.committer.map(searchUserDict) ?? NSNull() }
        m["id"]         = { commitNodeId($0) }
        m["parents"]    = { _ in [] as [Any] }
        m["repository"] = { commitRepositoryDict($0.repository) }
        m["sha"]        = { $0.sha }
        m["url"]        = { $0.htmlUrl.absoluteString }
        return m
    }

    /// Synthesize the GraphQL node ID for a commit from REST data.
    /// GitHub's legacy node-ID format for commits is
    /// `base64("06:Commit<repo_db_id>:<sha>")` — the leading "06" is
    /// the literal length of "Commit". The format pre-dates the Relay
    /// node IDs used elsewhere and is still what `gh search commits
    /// --json id` emits.
    static func commitNodeId(_ c: CommitSearchItem) -> String {
        let payload = "06:Commit\(c.repository.id):\(c.sha)"
        return Data(payload.utf8).base64EncodedString()
    }

    static func commitInnerDict(_ c: CommitSearchItem) -> [String: Any] {
        [
            "author": [
                "name":  c.commit.author.name,
                "email": c.commit.author.email,
                "date":  JSONFieldSelector.iso8601(c.commit.author.date),
            ],
            "committer": [
                "name":  c.commit.committer.name,
                "email": c.commit.committer.email,
                "date":  JSONFieldSelector.iso8601(c.commit.committer.date),
            ],
            "message": c.commit.message,
            "tree": c.commit.tree.map { ["sha": $0.sha] as [String: Any] } ?? ["sha": ""],
            "commentCount": c.commit.commentCount ?? 0,
        ]
    }
}
