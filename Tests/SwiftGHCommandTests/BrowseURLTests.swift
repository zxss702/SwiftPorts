import ArgumentParser
import Foundation
import Testing
@testable import SwiftGHCommand
@testable import SwiftGHCore

/// Mostly verifies the URL builder via the parsing layer; the actual
/// `Browser.open` call happens at runtime and isn't tested here.
@Suite struct BrowseURLTests {
    @Test func parsesNoArgs() throws {
        let cmd = try BrowseCommand.parse([])
        #expect(cmd.repo == nil)
        #expect(cmd.target == nil)
        #expect(cmd.branch == nil)
    }

    @Test func parsesNumericTarget() throws {
        let cmd = try BrowseCommand.parse(["42"])
        #expect(cmd.target == "42")
    }

    @Test func parsesPathAndBranch() throws {
        let cmd = try BrowseCommand.parse(["README.md", "--branch", "main"])
        #expect(cmd.target == "README.md")
        #expect(cmd.branch == "main")
    }

    @Test func parsesNoBrowserAndCommit() throws {
        let cmd = try BrowseCommand.parse(["--commit", "abc123", "--no-browser"])
        #expect(cmd.commit == "abc123")
        #expect(cmd.noBrowser == true)
    }

    @Test func parsesSectionFlags() throws {
        #expect(try BrowseCommand.parse(["--releases"]).releases == true)
        #expect(try BrowseCommand.parse(["--wiki"]).wiki == true)
        #expect(try BrowseCommand.parse(["--projects"]).projects == true)
        #expect(try BrowseCommand.parse(["--settings"]).settings == true)
    }
}

@Suite struct BrowserHelperTests {
    @Test func rejectsNonHTTPSchemes() async throws {
        await #expect(throws: BrowserError.self) {
            try await Browser.open(URL(string: "file:///etc/passwd")!)
        }
        await #expect(throws: BrowserError.self) {
            try await Browser.open(URL(string: "javascript:alert(1)")!)
        }
    }
}
