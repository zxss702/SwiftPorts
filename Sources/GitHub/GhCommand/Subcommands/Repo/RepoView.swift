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
        let repo: Repository = try await client.get("repos/\(target.slug)")
        let on = TTY.isStdoutColorEnabled

        // Match upstream `gh repo view`'s default surface — name +
        // description + README. Stats, badges, the default-branch
        // line, the HTML URL and the topic list are NOT printed by
        // default; users who want them ask for `--json` instead.
        // Without this trim the metadata block ran ~7 lines longer
        // than the reference `gh`, which made an embedded shell
        // visibly noisier than the host's `gh` side-by-side.
        let nameToken = OSC8.wrap(repo.fullName, url: repo.htmlUrl.absoluteString, enabled: on)
        Shell.print(ANSI.bold(nameToken))
        if let desc = repo.description, !desc.isEmpty {
            Shell.print(desc)
        }

        do {
            if let rendered = try await Self.fetchAndRenderReadme(client: client, slug: target.slug),
               !rendered.isEmpty {
                Shell.print("")
                Shell.print(rendered)
            }
        } catch APIError.notFound {
            // No README in this repo — silently skip, matches upstream.
        }
    }

    /// Fetch the repository's README via the contents API and run
    /// it through GlamKit. Returns `nil` when no README exists or
    /// the payload couldn't be decoded — absence is non-fatal,
    /// matching upstream `gh repo view`.
    private static func fetchAndRenderReadme(
        client: APIClient,
        slug: String
    ) async throws -> String? {
        let content: RepositoryContent = try await client.get("repos/\(slug)/readme")
        guard let text = content.decodedContent(), !text.isEmpty else { return nil }
        return Glam.renderBody(text)
    }
}
