import ArgumentParser
import Foundation
import SwiftGHCore

struct PrReopen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reopen",
        abstract: "Reopen a closed pull request."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "PR number.")
    var number: Int

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)
        let client = try await CommandContext.apiClient()
        let pr: PullRequest = try await client.send(
            method: .patch,
            path: "repos/\(target.slug)/pulls/\(number)",
            body: ["state": "open"])
        print("\(ANSI.green("✓")) Reopened #\(pr.number)")
    }
}
