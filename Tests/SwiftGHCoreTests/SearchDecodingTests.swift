import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct SearchDecodingTests {
    @Test func decodesRepoSearch() throws {
        let data = try FixtureLoader.data("search_repos")
        let result = try JSONDecoder.gitHub().decode(
            SearchResult<Repository>.self, from: data)

        #expect(result.totalCount > 0)
        #expect(result.items.count <= 3)
        let first = try #require(result.items.first)
        #expect(!first.fullName.isEmpty)
    }
}
