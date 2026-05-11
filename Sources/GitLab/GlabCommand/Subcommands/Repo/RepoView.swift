import ArgumentParser
import ForgeKit
import GlamKit
import ShellKit
import Foundation
import GitLab

struct RepoView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Display a project's metadata.",
        aliases: ["show"]
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Argument(help: "Optional positional override for the repo (same syntax as -R).")
    var positional: RepositoryReference?

    @Flag(name: [.customShort("w"), .long],
          help: "Open the project in your browser.")
    var web: Bool = false

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    func run() async throws {
        let target = try await CommandContext.resolveRepo(
            flag: repo, positional: positional)
        let client = try await CommandContext.apiClient(host: target.host)
        let project: Project = try await client.get(
            "projects/\(target.encodedPath)")

        if web {
            try await Browser.open(project.webUrl)
            Shell.print("Opening \(project.webUrl.absoluteString) in your browser.")
            return
        }
        if json {
            Shell.print(try CodableOutput.prettyJSON(project))
            return
        }

        let on = TTY.isStdoutColorEnabled
        let nameToken = OSC8.wrap(project.pathWithNamespace,
                                  url: project.webUrl.absoluteString,
                                  enabled: on)
        Shell.print("\(ANSI.bold(nameToken))  \(on ? ANSI.dim("(#\(project.id))") : "(#\(project.id))")")
        Shell.print("name: \(project.name)")
        if let d = project.description, !d.isEmpty { Shell.print("description: \(d)") }
        let visBadge: String
        switch project.visibility {
        case "public":   visBadge = StatusBadge.open(project.visibility,    enabled: on)
        case "private":  visBadge = StatusBadge.draft(project.visibility,   enabled: on)
        case "internal": visBadge = on ? ANSI.cyan(project.visibility)      : project.visibility
        default:         visBadge = project.visibility
        }
        Shell.print("visibility: \(visBadge)")
        if let archived = project.archived, archived {
            Shell.print(StatusBadge.failure("⚠ archived", enabled: on))
        }
        if let branch = project.defaultBranch { Shell.print("default branch: \(branch)") }
        if let stars = project.starCount { Shell.print("stars: \(stars)") }
        if let forks = project.forksCount { Shell.print("forks: \(forks)") }
        if let open = project.openIssuesCount { Shell.print("open issues: \(open)") }
        Shell.print("urls:")
        Shell.print("  web:  \(project.webUrl.absoluteString)")
        if let http = project.httpUrlToRepo { Shell.print("  http: \(http.absoluteString)") }
        if let ssh = project.sshUrlToRepo { Shell.print("  ssh:  \(ssh.absoluteString)") }

        // README is rendered by default — projects without a README
        // produce nil (best-effort), in which case we silently skip
        // the section. Matches upstream `gh repo view` / what users
        // expect from `glab repo view OWNER/REPO`.
        if let rendered = await Self.fetchAndRenderReadme(
            client: client, target: target, project: project),
           !rendered.isEmpty {
            Shell.print("")
            Shell.print(rendered)
        }
    }

    /// Fetch and render the project's README via the GitLab files
    /// API. Probes a small set of common filenames on the project's
    /// default branch. Returns `nil` when none of the candidates
    /// resolves — absence is non-fatal, matching the way upstream
    /// `gh repo view` treats a missing README.
    private static func fetchAndRenderReadme(
        client: APIClient,
        target: RepositoryReference,
        project: Project
    ) async -> String? {
        let branch = project.defaultBranch ?? "main"
        let candidates = ["README.md", "README", "README.rst", "README.txt", "readme.md"]
        for name in candidates {
            let encoded = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? name
            let path = "projects/\(target.encodedPath)/repository/files/\(encoded)"
            let query = [URLQueryItem(name: "ref", value: branch)]
            if let file = try? await client.get(path, query: query) as RepositoryFile,
               let text = file.decodedContent(), !text.isEmpty {
                return Glam.renderBody(text)
            }
        }
        return nil
    }
}
