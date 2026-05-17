// Pure-Swift unit tests for `GitClient.glob` — the in-house `*`/`?`
// matcher that replaced the libc `fnmatch(3)` call. Unlike the
// integration tests in `GitClientGrepTests`, these don't fork system
// `git`, so they run on every platform — including Windows, which
// doesn't ship `fnmatch` and is exactly the reason the helper exists.
import Foundation
import Testing
@testable import SwiftGit

@Suite("GitClient.grep glob helper")
struct GitClientGrepGlobTests {

    @Test func starMatchesAnyRun() {
        #expect(GitClient.glob(pattern: "*.swift", name: "Walker.swift"))
        #expect(GitClient.glob(pattern: "*.swift", name: "sub/Walker.swift"))
        #expect(!GitClient.glob(pattern: "*.swift", name: "Walker.md"))
    }

    @Test func questionMarkMatchesOne() {
        #expect(GitClient.glob(pattern: "a?c", name: "abc"))
        #expect(GitClient.glob(pattern: "a?c", name: "axc"))
        #expect(!GitClient.glob(pattern: "a?c", name: "ac"))
        #expect(!GitClient.glob(pattern: "a?c", name: "abcd"))
    }

    @Test func literalMustMatchExactly() {
        #expect(GitClient.glob(pattern: "README", name: "README"))
        #expect(!GitClient.glob(pattern: "README", name: "README.md"))
    }

    @Test func emptyPatternMatchesEmptyOnly() {
        #expect(GitClient.glob(pattern: "", name: ""))
        #expect(!GitClient.glob(pattern: "", name: "x"))
    }

    @Test func starAloneMatchesEverything() {
        #expect(GitClient.glob(pattern: "*", name: ""))
        #expect(GitClient.glob(pattern: "*", name: "anything/at/all.txt"))
    }
}
