#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import ArgumentParser
import Foundation
import Testing
@testable import GitHub
@testable import GhCommand

@Suite struct RepoCloneParsingTests {
    @Test func acceptsOwnerSlashName() throws {
        let cmd = try RepoClone.parse(["cli/cli"])
        #expect(cmd.repository == "cli/cli")
        #expect(cmd.directory == nil)
        #expect(cmd.https == false)
        #expect(cmd.ssh == false)
    }

    @Test func acceptsBareNameWithDirectory() throws {
        let cmd = try RepoClone.parse(["myrepo", "/tmp/dest"])
        #expect(cmd.repository == "myrepo")
        #expect(cmd.directory == "/tmp/dest")
    }

    @Test func parsesProtocolFlags() throws {
        let cmd = try RepoClone.parse(["cli/cli", "--ssh"])
        #expect(cmd.ssh == true)
    }
}

@Suite struct PrCheckoutParsingTests {
    @Test func parsesNumber() throws {
        let cmd = try PrCheckout.parse(["1234"])
        #expect(cmd.number == 1234)
        #expect(cmd.branch == nil)
    }

    @Test func parsesCustomBranch() throws {
        let cmd = try PrCheckout.parse(["1234", "--branch", "fix/x"])
        #expect(cmd.branch == "fix/x")
    }
}

@Suite struct PrCreateParsingTests {
    @Test func parsesTitleOnly() throws {
        let cmd = try PrCreate.parse(["--title", "Add foo"])
        #expect(cmd.title == "Add foo")
        #expect(cmd.body == nil)
        #expect(cmd.draft == false)
        #expect(cmd.head == nil)
        #expect(cmd.base == nil)
    }

    @Test func parsesAllFlags() throws {
        let cmd = try PrCreate.parse([
            "--title", "Hi", "--body", "ok",
            "--head", "feat/x", "--base", "main",
            "--draft", "--no-push",
        ])
        #expect(cmd.title == "Hi")
        #expect(cmd.head == "feat/x")
        #expect(cmd.base == "main")
        #expect(cmd.draft == true)
        #expect(cmd.noPush == true)
    }
}

@Suite struct PrMergeParsingTests {
    @Test func defaultsToNoMethod() throws {
        let cmd = try PrMerge.parse(["123"])
        #expect(cmd.merge == false)
        #expect(cmd.squash == false)
        #expect(cmd.rebase == false)
    }

    @Test func methodFlags() throws {
        #expect(try PrMerge.parse(["123", "--squash"]).squash == true)
        #expect(try PrMerge.parse(["123", "--rebase"]).rebase == true)
        #expect(try PrMerge.parse(["123", "--merge"]).merge == true)
    }
}

#endif  // !os(Android)
