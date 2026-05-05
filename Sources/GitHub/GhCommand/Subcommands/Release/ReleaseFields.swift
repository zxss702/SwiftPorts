import Foundation
import GitHub

/// Field map for `gh release list --json` and `gh release view --json`.
///
/// Upstream gh's release commands run on REST, so we keep our REST
/// path. `isLatest` requires a separate "latest release" lookup; the
/// caller passes a precomputed `latestTag` so per-row evaluation is
/// O(1) (see `withLatest(_:_:)`).
enum ReleaseFields {
    /// One row's worth of context — the release plus the repo's
    /// current "latest release" tag, used to compute `isLatest`.
    struct Context {
        let release: Release
        let latestTag: String?
    }

    static let map: [String: @Sendable (Context) -> Any?] = makeMap()

    private static func makeMap() -> [String: @Sendable (Context) -> Any?] {
        var m: [String: @Sendable (Context) -> Any?] = [:]
        m["apiUrl"]          = { $0.release.url.absoluteString }
        m["assets"]          = { $0.release.assets.map(assetDict) }
        m["author"]          = { authorDict($0.release.author) }
        m["body"]            = { $0.release.body ?? "" }
        m["createdAt"]       = { JSONFieldSelector.iso8601($0.release.createdAt) }
        m["databaseId"]      = { $0.release.id }
        m["id"]              = { $0.release.nodeId }
        m["isDraft"]         = { $0.release.draft }
        m["isImmutable"]     = { $0.release.immutable ?? false }
        m["isLatest"]        = { ctx in ctx.latestTag.map { $0 == ctx.release.tagName } ?? false }
        m["isPrerelease"]    = { $0.release.prerelease }
        m["name"]            = { $0.release.name ?? "" }
        m["publishedAt"]     = { $0.release.publishedAt.map(JSONFieldSelector.iso8601) ?? NSNull() }
        m["tagName"]         = { $0.release.tagName }
        m["tarballUrl"]      = { $0.release.tarballUrl?.absoluteString ?? "" }
        m["targetCommitish"] = { $0.release.targetCommitish }
        m["uploadUrl"]       = { $0.release.uploadUrl }
        m["url"]              = { $0.release.htmlUrl.absoluteString }
        m["zipballUrl"]      = { $0.release.zipballUrl?.absoluteString ?? "" }
        return m
    }

    static func authorDict(_ u: User) -> [String: Any] {
        ["id": u.nodeId, "login": u.login]
    }

    static func assetDict(_ a: ReleaseAsset) -> [String: Any] {
        [
            "apiUrl":        a.url.absoluteString,
            "contentType":   a.contentType,
            "createdAt":     JSONFieldSelector.iso8601(a.createdAt),
            "digest":        a.digest ?? NSNull(),
            "downloadCount": a.downloadCount,
            "id":            a.nodeId,
            "label":         a.label ?? "",
            "name":          a.name,
            "size":          a.size,
            "state":         a.state,
            "updatedAt":     JSONFieldSelector.iso8601(a.updatedAt),
            "url":           a.browserDownloadUrl.absoluteString,
        ]
    }
}
