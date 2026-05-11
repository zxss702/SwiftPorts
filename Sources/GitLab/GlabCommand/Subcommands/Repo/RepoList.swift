import ArgumentParser
import ShellKit
import Foundation
import ForgeKit
import GitLab

struct RepoList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List GitLab projects.",
        aliases: ["ls"]
    )

    @Option(name: [.customShort("h"), .customLong("hostname")],
            help: "Hostname to query (default: gitlab.com or $GITLAB_HOST).")
    var hostname: String?

    @Option(name: [.customShort("g"), .long],
            help: "List projects under a group / subgroup (full path).")
    var group: String?

    @Option(name: .long,
            help: "List projects under a user (username).")
    var user: String?

    @Flag(name: .customLong("owned"),
          help: "Limit to projects owned by the authenticated user.")
    var owned: Bool = false

    @Flag(name: .customLong("starred"),
          help: "Limit to projects starred by the authenticated user.")
    var starred: Bool = false

    @Flag(name: .customLong("membership"),
          help: "Limit to projects the authenticated user is a member of.")
    var membership: Bool = false

    @Option(name: .customLong("visibility"),
            help: "Filter by visibility: public / internal / private.")
    var visibility: String?

    @Option(name: [.customShort("s"), .long],
            help: "Search the project name and path.")
    var search: String?

    @Option(name: [.customShort("P"), .customLong("per-page")],
            help: "Items per page.")
    var perPage: Int = 30

    @Option(name: [.customShort("p"), .long],
            help: "Page number.")
    var page: Int = 1

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let client = try await CommandContext.apiClient(host: hostname)

        let path: String
        if let group {
            // GitLab's group path also needs URL-encoding.
            let enc = group
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                .replacingOccurrences(of: "/", with: "%2F") ?? group
            path = "groups/\(enc)/projects"
        } else if let user {
            path = "users/\(user)/projects"
        } else {
            path = "projects"
        }

        var query: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if owned { query.append(URLQueryItem(name: "owned", value: "true")) }
        if starred { query.append(URLQueryItem(name: "starred", value: "true")) }
        if membership { query.append(URLQueryItem(name: "membership", value: "true")) }
        if let visibility {
            query.append(URLQueryItem(name: "visibility", value: visibility))
        }
        if let search {
            query.append(URLQueryItem(name: "search", value: search))
        }

        let projects: [Project] = try await client.get(path, query: query)

        if json {
            Shell.print(try CodableOutput.prettyJSON(projects))
            return
        }
        if projects.isEmpty {
            Shell.print("No projects match.")
            return
        }
        let on = color.resolved()
        for p in projects {
            let archivedTag = (p.archived == true)
                ? "  " + StatusBadge.failure("(archived)", enabled: on)
                : ""
            let branchTag = p.defaultBranch.map {
                "  " + (on ? ANSI.dim("[\($0)]") : "[\($0)]")
            } ?? ""
            let visText = p.visibility
            let visibility: String
            switch visText {
            case "public":   visibility = "  " + StatusBadge.open(visText,    enabled: on)
            case "private":  visibility = "  " + StatusBadge.draft(visText,   enabled: on)
            case "internal": visibility = "  " + (on ? ANSI.cyan(visText)     : visText)
            default:         visibility = ""
            }
            let pathToken = OSC8.wrap(p.pathWithNamespace, url: p.webUrl.absoluteString, enabled: on)
            Shell.print("#\(p.id)\t\(pathToken)\(visibility)\(branchTag)\(archivedTag)")
            if let d = p.description, !d.isEmpty {
                Shell.print("\t" + (on ? ANSI.dim(d) : d))
            }
        }
    }
}
