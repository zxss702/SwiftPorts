import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct RepositoryDecodingTests {
    @Test func decodesOctocatHelloWorld() throws {
        let data = try FixtureLoader.data("repo_octocat_hello_world")
        let repo = try JSONDecoder.gitHub().decode(Repository.self, from: data)

        #expect(repo.name == "Hello-World")
        #expect(repo.fullName == "octocat/Hello-World")
        #expect(repo.owner.login == "octocat")
        #expect(repo.owner.type == .user)
        #expect(repo.private == false)
        #expect(repo.fork == false)
        #expect(repo.defaultBranch == "master")
        #expect(repo.htmlUrl.absoluteString == "https://github.com/octocat/Hello-World")
        #expect(repo.stargazersCount > 0)
        #expect(repo.visibility == .public)
    }
}
