import ArgumentParser
import Foundation
import GitHub

/// `--format` option for `gh project *` subcommands. Mirrors upstream
/// gh, which uses `--format` instead of `--json` for ProjectV2 output.
/// Only `json` is recognised.
enum ProjectFormat: String, ExpressibleByArgument, Sendable {
    case json
}

/// Helpers shared by `project` subcommands for emitting upstream-shape
/// `--format json` output.
enum ProjectJSONOutput {
    /// Compact JSON with sorted keys + raw slashes, matching upstream's
    /// Go `encoding/json` output.
    static func render(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Convert a `ProjectV2` to the upstream JSON shape.
    static func project(_ p: ProjectV2Like) -> [String: Any] {
        var owner: [String: Any] = [:]
        if let o = p.ownerLogin { owner["login"] = o }
        if let t = p.ownerType { owner["type"] = t }
        return [
            "closed": p.closed,
            "fields": ["totalCount": p.fieldsCount ?? 0],
            "id": p.id,
            "items": ["totalCount": p.itemsCount ?? 0],
            "number": p.number,
            "owner": owner,
            "public": p.public,
            "readme": p.readme ?? "",
            "shortDescription": p.shortDescription ?? "",
            "title": p.title,
            "url": p.url.absoluteString,
        ]
    }
}

/// Common projection surface so `ProjectV2` and `ProjectV2WithItemCount`
/// can be rendered uniformly.
protocol ProjectV2Like {
    var id: String { get }
    var number: Int { get }
    var title: String { get }
    var shortDescription: String? { get }
    var url: URL { get }
    var closed: Bool { get }
    var `public`: Bool { get }
    var readme: String? { get }
    var ownerLogin: String? { get }
    var ownerType: String? { get }
    var fieldsCount: Int? { get }
    var itemsCount: Int? { get }
}

extension ProjectV2: ProjectV2Like {
    var ownerLogin: String? { owner?.login }
    var ownerType: String? { owner?.type }
    var fieldsCount: Int? { fields?.totalCount }
    var itemsCount: Int? { items?.totalCount }
}

extension ProjectV2WithItemCount: ProjectV2Like {
    var ownerLogin: String? { owner?.login }
    var ownerType: String? { owner?.type }
    var fieldsCount: Int? { fields?.totalCount }
    var itemsCount: Int? { items.totalCount }
}
