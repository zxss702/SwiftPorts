import ArgumentParser
import Foundation
import SwiftGHCore

struct PrCheckout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "checkout",
        abstract: "Check out a pull request locally.",
        discussion: """
        Fetches the PR's head ref into a local branch and switches to it.

        Run this from inside the cloned repo. Cross-fork PRs are
        fetched from the head repository's URL directly.
        """
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "PR number.")
    var number: Int

    @Option(name: [.short, .customLong("branch")],
            help: "Local branch name (default: pr-NUMBER).")
    var branch: String?

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)
        let client = try await CommandContext.apiClient()
        let pr: PullRequest = try await client.get(
            "repos/\(target.slug)/pulls/\(number)")

        let localBranch = branch ?? "pr-\(number)"
        let git = ProcessGitClient()

        // Same-repo PR: fetch from origin's pull/N/head.
        // Cross-fork PR: fetch from head.repo's clone URL by HEAD branch.
        let isCrossFork = pr.head.repo?.fullName != target.slug
        if isCrossFork, let headRepo = pr.head.repo {
            let url = URL(string: "\(headRepo.htmlUrl.absoluteString).git")!
            print("Fetching \(pr.head.ref) from \(headRepo.fullName)…")
            try await git.fetch(
                remote: url.absoluteString,
                refspec: "\(pr.head.ref):\(localBranch)")
        } else {
            print("Fetching pull/\(number)/head from origin…")
            try await git.fetch(
                remote: "origin",
                refspec: "pull/\(number)/head:\(localBranch)")
        }

        try await git.checkout(ref: localBranch)
        print("\(ANSI.green("✓")) Checked out PR #\(number) on local branch \(localBranch)")
    }
}
