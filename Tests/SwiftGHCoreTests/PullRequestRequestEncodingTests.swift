import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct PullRequestRequestEncodingTests {
    @Test func createBodyIncludesHeadAndBase() throws {
        let request = PullRequestCreateRequest(
            title: "Add foo",
            head: "feat/foo",
            base: "main",
            body: "Long body",
            draft: true,
            maintainerCanModify: false)
        let data = try JSONEncoder.gitHub().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["title"] as? String == "Add foo")
        #expect(object["head"] as? String == "feat/foo")
        #expect(object["base"] as? String == "main")
        #expect(object["draft"] as? Bool == true)
        #expect(object["maintainer_can_modify"] as? Bool == false)
    }

    @Test func mergeBodyIncludesMethod() throws {
        let request = PullRequestMergeRequest(
            commitTitle: "Merge",
            commitMessage: "Body",
            mergeMethod: .squash)
        let data = try JSONEncoder.gitHub().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["commit_title"] as? String == "Merge")
        #expect(object["commit_message"] as? String == "Body")
        #expect(object["merge_method"] as? String == "squash")
    }

    @Test func repoCreateBodyHonorsVisibility() throws {
        let request = RepoCreateRequest(
            name: "test", description: "x", private: true,
            visibility: .private, autoInit: true,
            licenseTemplate: "mit")
        let data = try JSONEncoder.gitHub().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["name"] as? String == "test")
        #expect(object["private"] as? Bool == true)
        #expect(object["visibility"] as? String == "private")
        #expect(object["auto_init"] as? Bool == true)
        #expect(object["license_template"] as? String == "mit")
    }
}
