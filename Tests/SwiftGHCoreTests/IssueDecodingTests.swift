import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct IssueDecodingTests {
    @Test func decodesCliFirstIssue() throws {
        let data = try FixtureLoader.data("issue_cli_1")
        let issue = try JSONDecoder.gitHub().decode(Issue.self, from: data)

        #expect(issue.number == 1)
        #expect(issue.state == .closed)
        #expect(issue.title == "interactive pr list")
        #expect(issue.user.login == "vilmibm")
        #expect(issue.locked == true)
        #expect(issue.activeLockReason == "spam")
        #expect(issue.pullRequest != nil)  // it was actually a PR
    }
}
