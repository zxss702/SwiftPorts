import ArgumentParser
import Foundation
import Testing
@testable import GitHub
@testable import GhCommand

/// Mirrors `pkg/cmd/repo/view/view_test.go::TestNewCmdView` from the
/// Go gh — argv parsing, no network.
@Suite struct RepoViewParsingTests {
    @Test func parsesRepoArg() throws {
        let cmd = try RepoView.parse(["some/repo"])
        #expect(cmd.repository?.owner == "some")
        #expect(cmd.repository?.name == "repo")
        #expect(cmd.json == nil)
    }

    @Test func parsesJSONFlag() throws {
        // `--json` is now a value-taking option (matches upstream gh's
        // field-selector form). Test passes a fields list.
        let cmd = try RepoView.parse(["cli/cli", "--json", "id,name"])
        #expect(cmd.repository?.slug == "cli/cli")
        #expect(cmd.json == "id,name")
    }

    @Test func acceptsNoArgsBecauseRepoIsOptional() throws {
        // Repo is now optional — RepositoryResolver will infer from
        // git origin at run time. Parsing must succeed even with no
        // positional, and the user only sees an error if there's no
        // git remote either.
        let cmd = try RepoView.parse([])
        #expect(cmd.repository == nil)
    }

    @Test func rejectsMalformedRepo() {
        #expect(throws: (any Error).self) {
            _ = try RepoView.parse(["not-a-slug"])
        }
    }
}
