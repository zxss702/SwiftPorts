import ArgumentParser
import ForgeKit
import ShellKit
import Foundation
import GitLab

struct TagList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List repository tags."
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Option(name: [.short, .customLong("limit")])
    var limit: Int = 30

    @Option(name: [.customShort("s"), .long],
            help: "Search filter (substring of tag name).")
    var search: String?

    func run() async throws {
        let target = try await CommandContext.resolveRepo(flag: repo)
        let client = try await CommandContext.apiClient(host: target.host)
        // Fetch the project to derive the web URL for OSC 8 links —
        // tags don't carry one of their own. Best-effort: if this
        // call fails we just emit unlinked tag names.
        let project: Project? = try? await client.get("projects/\(target.encodedPath)")

        var query: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(min(limit, 100))),
        ]
        if let search { query.append(URLQueryItem(name: "search", value: search)) }
        let tags: [Tag] = try await client.get(
            "projects/\(target.encodedPath)/repository/tags",
            query: query)
        if tags.isEmpty { Shell.print("No tags."); return }
        let on = TTY.isStdoutColorEnabled
        let projectWebBase = project?.webUrl.absoluteString
        for tag in tags.prefix(limit) {
            let commit = tag.commit?.shortId ?? tag.commit?.id.prefix(7).description ?? ""
            let title = tag.message?.split(separator: "\n").first.map(String.init) ?? ""
            // GitLab's tag view lives at `<project>/-/tags/<name>`.
            // URL-encode the name so refs with slashes (`v/1.0`) and
            // similar still produce a valid hyperlink.
            let nameToken: String
            if let base = projectWebBase,
               let encoded = tag.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                nameToken = OSC8.wrap(tag.name, url: "\(base)/-/tags/\(encoded)", enabled: on)
            } else {
                nameToken = tag.name
            }
            Shell.print("\(nameToken)\t\(StatusBadge.muted(commit, enabled: on))\t\(title)")
        }
    }
}
