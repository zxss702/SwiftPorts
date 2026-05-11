import ArgumentParser
import ForgeKit
import GlamKit
import ShellKit
import Foundation
import GitHub

struct RepoView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a repository."
    )

    @Argument(help: "Repository as OWNER/REPO. Omit to use the current directory's git remote.")
    var repository: RepositoryReference?

    @Option(name: .long,
            help: "Output JSON with the specified fields (comma-separated).")
    var json: String?

    @Flag(name: .long,
          help: "Print the repository's README rendered through GlamKit instead of the metadata.")
    var readme: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let target = try await RepositoryResolver.resolve(positional: repository)

        if let json {
            let fields = try JSONFieldSelector.parse(raw: json, fieldMap: RepoFields.map)
            let gql = try await CommandContext.graphQLClient()
            let response: RepositoryViewResponse = try await gql.query(
                RepositoryViewQueries.view,
                variables: [
                    "owner": .string(target.owner),
                    "name":  .string(target.name),
                ])
            guard let repo = response.repository else {
                throw ValidationError("No repo \(target.slug).")
            }
            Shell.print(try JSONFieldSelector.render(item: repo, fields: fields, fieldMap: RepoFields.map))
            return
        }

        let client = try await CommandContext.apiClient()

        if readme {
            let content: RepositoryContent = try await client.get(
                "repos/\(target.slug)/readme")
            if let text = content.decodedContent(), !text.isEmpty {
                Shell.print(Glam.renderBody(text))
            } else {
                Shell.print("(README is empty or could not be decoded)")
            }
            return
        }

        let repo: Repository = try await client.get("repos/\(target.slug)")
        let on = color.resolved()
        let nameToken = OSC8.wrap(repo.fullName, url: repo.htmlUrl.absoluteString, enabled: on)
        Shell.print(ANSI.bold(nameToken))
        let visibility = repo.private ? "private" : "public"
        let badges: [String] = {
            var b: [String] = []
            b.append(visibility == "public"
                     ? StatusBadge.open(visibility, enabled: on)
                     : StatusBadge.draft(visibility, enabled: on))
            if repo.archived == true { b.append(StatusBadge.failure("archived", enabled: on)) }
            if repo.fork    == true { b.append(StatusBadge.muted("fork",       enabled: on)) }
            return b
        }()
        Shell.print(badges.joined(separator: "  "))
        if let desc = repo.description, !desc.isEmpty {
            Shell.print(desc)
        }
        Shell.print("")
        let stats = [
            "★ \(repo.stargazersCount)",
            "⑂ \(repo.forksCount)",
            "issues \(repo.openIssuesCount)",
            "language \(repo.language ?? "—")",
            "license \(repo.license?.spdxId ?? "—")",
        ].joined(separator: "  ")
        Shell.print(stats)
        Shell.print("default branch: \(repo.defaultBranch)")
        Shell.print("html: \(repo.htmlUrl.absoluteString)")
        if let topics = repo.topics, !topics.isEmpty {
            Shell.print("topics: \(topics.joined(separator: ", "))")
        }
    }
}
