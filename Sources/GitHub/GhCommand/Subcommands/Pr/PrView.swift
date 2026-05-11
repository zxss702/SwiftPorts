import ArgumentParser
import GlamKit
import ShellKit
import Foundation
import GitHub
import ForgeKit

struct PrView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a pull request."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "PR number.")
    var number: Int

    @Option(name: .long,
            help: "Output JSON with the specified fields (comma-separated).")
    var json: String?

    @Flag(name: .long, help: "Also fetch and print the PR's comments.")
    var comments: Bool = false

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)

        if let json {
            let fields = try JSONFieldSelector.parse(raw: json, fieldMap: PrFields.map)
            let gql = try await CommandContext.graphQLClient()
            let response: PullRequestViewResponse = try await gql.query(
                PullRequestQueries.view(),
                variables: [
                    "owner":  .string(target.owner),
                    "name":   .string(target.name),
                    "number": .int(number),
                ])
            guard let pr = response.repository?.pullRequest else {
                throw ValidationError("No PR #\(number) on \(target.slug).")
            }
            Shell.print(try JSONFieldSelector.render(item: pr, fields: fields, fieldMap: PrFields.map))
            return
        }

        let client = try await CommandContext.apiClient()
        let pr: PullRequest = try await client.get(
            "repos/\(target.slug)/pulls/\(number)")

        let on = TTY.isStdoutColorEnabled
        let numberToken = OSC8.wrap("#\(pr.number)", url: pr.htmlUrl.absoluteString, enabled: on)
        Shell.print("\(ANSI.bold(numberToken))  \(ANSI.bold(pr.title))")
        let stateLabel: String
        if pr.merged == true { stateLabel = StatusBadge.merged(enabled: on) }
        else if pr.state == .open { stateLabel = StatusBadge.open(enabled: on) }
        else { stateLabel = StatusBadge.closed(enabled: on) }
        let draftSuffix = pr.draft == true ? " \(StatusBadge.draft("(draft)", enabled: on))" : ""
        Shell.print("state: \(stateLabel)\(draftSuffix)  author: @\(pr.user.login)")
        Shell.print("\(pr.head.ref) → \(pr.base.ref)")
        Shell.print("created: \(ISO8601DateFormatter().string(from: pr.createdAt))")
        if let merged = pr.merged, merged, let when = pr.mergedAt {
            Shell.print("merged: \(ISO8601DateFormatter().string(from: when))")
        }
        if !pr.labels.isEmpty {
            let chips = pr.labels.map { LabelChip.colored(name: $0.name, hex: $0.color, enabled: on) }
            Shell.print("labels: \(chips.joined(separator: " "))")
        }
        Shell.print("url: \(pr.htmlUrl.absoluteString)")
        if let body = pr.body, !body.isEmpty {
            Shell.print("\n--\n\(Glam.renderBody(body))")
        }
        if comments {
            try await renderComments(target: target, client: client)
        }
    }

    /// Fetch + pretty-print the PR's discussion thread. PRs share
    /// GitHub's `/issues/<n>/comments` endpoint with issues — review
    /// comments live elsewhere and aren't part of this feed.
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
