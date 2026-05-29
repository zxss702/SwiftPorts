#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import ArgumentParser
import Foundation
import Testing
@testable import GitHub
@testable import GhCommand

/// Upstream `gh` exposes the repository selector as `-R, --repo`
/// (uppercase short). Regression coverage for the cases reported in
/// SwiftBash#51 — `-R` must be accepted as the short alias and the
/// help text must advertise it.
@Suite struct GhRepoFlagParityTests {
    @Test func issueListAcceptsUppercaseR() throws {
        let cmd = try IssueList.parse(["-R", "cli/cli"])
        #expect(cmd.repo?.slug == "cli/cli")
    }

    @Test func issueListAcceptsLongRepo() throws {
        let cmd = try IssueList.parse(["--repo", "cli/cli"])
        #expect(cmd.repo?.slug == "cli/cli")
    }

    @Test func issueListRejectsLowercaseR() {
        #expect(throws: (any Error).self) {
            _ = try IssueList.parse(["-r", "cli/cli"])
        }
    }

    @Test func issueCreateAcceptsUppercaseR() throws {
        let cmd = try IssueCreate.parse([
            "-R", "cli/cli", "--title", "hello",
        ])
        #expect(cmd.repo?.slug == "cli/cli")
    }

    @Test func prListAcceptsUppercaseR() throws {
        let cmd = try PrList.parse(["-R", "cli/cli"])
        #expect(cmd.repo?.slug == "cli/cli")
    }

    @Test func searchIssuesAcceptsUppercaseR() throws {
        let cmd = try SearchIssuesCommand.parse(["bug", "-R", "cli/cli"])
        #expect(cmd.repo == "cli/cli")
    }

    @Test func browseAcceptsUppercaseR() throws {
        let cmd = try BrowseCommand.parse(["-R", "cli/cli"])
        #expect(cmd.repo?.slug == "cli/cli")
    }
}

#endif  // !os(Android)
