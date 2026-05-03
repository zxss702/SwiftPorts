import Foundation
import Testing
@testable import SwiftGHCore

/// Opt-in: hits real `api.github.com` unauthenticated.
///
/// Excluded by default (rate-limit safety). Run with:
///
///     SWIFTGH_LIVE=1 swift test
///
/// or filter by tag:
///
///     swift test --filter "Live"
@Suite(
    .tags(.live),
    .disabled(if: ProcessInfo.processInfo.environment["SWIFTGH_LIVE"] == nil,
              "Set SWIFTGH_LIVE=1 to run live tests against api.github.com.")
)
struct LiveAPITests {
    @Test func fetchesOctocatHelloWorld() async throws {
        let client = APIClient()
        let repo: Repository = try await client.get("repos/octocat/Hello-World")
        #expect(repo.fullName == "octocat/Hello-World")
        #expect(repo.owner.login == "octocat")
    }

    @Test func fetchesCliCliLatestRelease() async throws {
        let client = APIClient()
        let release: Release = try await client.get("repos/cli/cli/releases/latest")
        #expect(release.tagName.hasPrefix("v"))
        #expect(!release.assets.isEmpty)
    }

    @Test func searchesRepos() async throws {
        let client = APIClient()
        let result: SearchResult<Repository> = try await client.get(
            "search/repositories",
            query: [
                URLQueryItem(name: "q", value: "swift cli"),
                URLQueryItem(name: "per_page", value: "3"),
            ])
        #expect(result.totalCount > 0)
        #expect(!result.items.isEmpty)
    }
}

extension Tag {
    @Tag static var live: Self
}
