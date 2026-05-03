import ArgumentParser
import Foundation
import Testing
@testable import SwiftGHCommand
@testable import SwiftGHCore

/// Mirrors `pkg/cmd/repo/view/view_test.go::TestNewCmdView` from the
/// Go gh — argv parsing, no network.
@Suite struct RepoViewParsingTests {
    @Test func parsesRepoArg() throws {
        let cmd = try RepoView.parse(["some/repo"])
        #expect(cmd.repository.owner == "some")
        #expect(cmd.repository.name == "repo")
        #expect(cmd.json == false)
    }

    @Test func parsesJSONFlag() throws {
        let cmd = try RepoView.parse(["cli/cli", "--json"])
        #expect(cmd.repository.slug == "cli/cli")
        #expect(cmd.json == true)
    }

    @Test func rejectsMissingRepo() {
        #expect(throws: (any Error).self) {
            _ = try RepoView.parse([])
        }
    }

    @Test func rejectsMalformedRepo() {
        #expect(throws: (any Error).self) {
            _ = try RepoView.parse(["not-a-slug"])
        }
    }
}
