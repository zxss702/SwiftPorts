import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct PullRequestDecodingTests {
    @Test func decodesCliFirstPR() throws {
        let data = try FixtureLoader.data("pr_cli_1")
        let pr = try JSONDecoder.gitHub().decode(PullRequest.self, from: data)

        #expect(pr.number == 1)
        #expect(pr.state == .closed)
        #expect(pr.user.login == "vilmibm")
        #expect(pr.head.ref.isEmpty == false)
        #expect(pr.base.ref.isEmpty == false)
        #expect(pr.merged != nil)
    }
}
