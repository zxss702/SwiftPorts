import ArgumentParser
import GlamKit
import ShellKit
import Foundation
import GitHub
import ForgeKit

struct IssueView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View an issue."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "Issue number.")
    var number: Int

    @Option(name: .long,
            help: "Output JSON with the specified fields (comma-separated).")
    var json: String?

    @Flag(name: .long, help: "Also fetch and print the issue's comments.")
    var comments: Bool = false

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)

        if let json {
            let fields = try JSONFieldSelector.parse(raw: json, fieldMap: IssueFields.map)
            let gql = try await CommandContext.graphQLClient()
            let response: IssueViewResponse = try await gql.query(
                IssueQueries.view,
                variables: [
                    "owner":  .string(target.owner),
                    "name":   .string(target.name),
                    "number": .int(number),
                ])
            guard let issue = response.repository?.issue else {
                throw ValidationError("No issue #\(number) on \(target.slug).")
            }
            Shell.print(try JSONFieldSelector.render(item: issue, fields: fields, fieldMap: IssueFields.map))
            return
        }

        let client = try await CommandContext.apiClient()
        let issue: Issue = try await client.get(
            "repos/\(target.slug)/issues/\(number)")

        let on = TTY.isStdoutColorEnabled
        let numberToken = OSC8.wrap("#\(issue.number)", url: issue.htmlUrl.absoluteString, enabled: on)
        Shell.print("\(ANSI.bold(numberToken))  \(ANSI.bold(issue.title))")
        let stateLabel = issue.state == .open
            ? StatusBadge.open(enabled: on)
            : StatusBadge.closed(enabled: on)
        Shell.print("state: \(stateLabel)  author: @\(issue.user.login)")
        Shell.print("created: \(ISO8601DateFormatter().string(from: issue.createdAt))")
        if !issue.labels.isEmpty {
            let chips = issue.labels.map { LabelChip.colored(name: $0.name, hex: $0.color, enabled: on) }
            Shell.print("labels: \(chips.joined(separator: " "))")
        }
        Shell.print("url: \(issue.htmlUrl.absoluteString)")
        if let body = issue.body, !body.isEmpty {
            Shell.print("\n--\n\(Glam.renderBody(body))")
        }
        if comments {
            try await renderComments(target: target, client: client)
        }
    }

    /// Fetch + pretty-print the issue's discussion thread.
    private func renderComments(target: RepositoryReference, client: APIClient) async throws {
        let list: [IssueComment] = try await client.get(
            "repos/\(target.slug)/issues/\(number)/comments")
        guard !list.isEmpty else {
            Shell.print("\n--\n(no comments)")
            return
        }
        Shell.print("\n--\n\(ANSI.bold("Comments (\(list.count))"))")
        let f = ISO8601DateFormatter()
        for comment in list {
            Shell.print("\n@\(comment.user.login)  \(f.string(from: comment.createdAt))")
            if let body = comment.body, !body.isEmpty {
                Shell.print(Glam.renderBody(body))
            }
        }
    }
}
