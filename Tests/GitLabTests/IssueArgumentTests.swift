#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import Testing
@testable import GlabCommand

@Suite struct IssueArgumentTests {
    @Test func parsesPlainNumber() throws {
        let parsed = try IssueArgument.parse("123")
        #expect(parsed.iid == 123)
        #expect(parsed.repoFromURL == nil)
    }

    @Test func parsesHashPrefixedNumber() throws {
        let parsed = try IssueArgument.parse("#42")
        #expect(parsed.iid == 42)
        #expect(parsed.repoFromURL == nil)
    }

    @Test func parsesFlatURL() throws {
        let parsed = try IssueArgument.parse(
            "https://gitlab.com/foo/bar/-/issues/9")
        #expect(parsed.iid == 9)
        let repo = try #require(parsed.repoFromURL)
        #expect(repo.host == "gitlab.com")
        #expect(repo.pathSegments == ["foo", "bar"])
    }

    @Test func parsesNestedSubgroupURL() throws {
        let parsed = try IssueArgument.parse(
            "https://gitlab.com/group/sub/repo/-/issues/7")
        #expect(parsed.iid == 7)
        let repo = try #require(parsed.repoFromURL)
        #expect(repo.pathSegments == ["group", "sub", "repo"])
    }

    @Test func parsesIncidentURL() throws {
        let parsed = try IssueArgument.parse(
            "https://gitlab.com/foo/bar/-/issues/incident/42")
        #expect(parsed.iid == 42)
    }

    @Test func rejectsNonNumeric() {
        #expect(throws: IssueArgumentError.self) {
            _ = try IssueArgument.parse("abc")
        }
    }

    @Test func rejectsEmpty() {
        #expect(throws: IssueArgumentError.self) {
            _ = try IssueArgument.parse("")
        }
    }
}

#endif  // !os(Android)
