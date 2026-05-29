#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import Testing
@testable import GlabCommand

@Suite struct MrArgumentTests {
    @Test func parsesPlainNumber() throws {
        let parsed = try MrArgument.parse("123")
        #expect(parsed.iid == 123)
        #expect(parsed.repoFromURL == nil)
    }

    @Test func parsesBangPrefixed() throws {
        let parsed = try MrArgument.parse("!42")
        #expect(parsed.iid == 42)
    }

    @Test func parsesHashPrefixed() throws {
        let parsed = try MrArgument.parse("#7")
        #expect(parsed.iid == 7)
    }

    @Test func parsesURL() throws {
        let parsed = try MrArgument.parse(
            "https://gitlab.com/group/sub/repo/-/merge_requests/9")
        #expect(parsed.iid == 9)
        let repo = try #require(parsed.repoFromURL)
        #expect(repo.host == "gitlab.com")
        #expect(repo.pathSegments == ["group", "sub", "repo"])
    }

    @Test func rejectsGarbage() {
        #expect(throws: MrArgumentError.self) {
            _ = try MrArgument.parse("totally-not-a-number")
        }
    }
}

#endif  // !os(Android)
