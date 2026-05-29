import Foundation
import Testing
@testable import GitHub
import ForgeKit

#if os(macOS) || os(Linux) || os(Windows)
/// Opt-in: actually shells out to `git`. Skipped unless we're inside
/// a git repo and `SWIFTGH_LIVE=1` is set. The test cwd at execution
/// time is the package root, which IS the SwiftPorts checkout once we
/// push, so `origin` will resolve to the real remote.
@Suite(
    .tags(.live),
    .disabled(if: ProcessInfo.processInfo.environment["SWIFTGH_LIVE"] == nil,
              "Set SWIFTGH_LIVE=1 to run live git tests.")
)
struct GitClientLiveTests {
    @Test func resolvesOriginInPackageDirectory() async throws {
        let client = ProcessGitClient()
        let url = try await client.remoteURL(named: "origin")
        // No remote configured locally is OK; this just checks the
        // shell-out path doesn't crash.
        if let url {
            print("[live] origin resolves to: \(url.absoluteString)")
        } else {
            print("[live] no 'origin' remote in package dir")
        }
    }

    @Test func currentBranchIsPopulated() async throws {
        let client = ProcessGitClient()
        let branch = try await client.currentBranch()
        #expect(branch != nil, "expected a branch in the package's git checkout")
        if let branch { print("[live] current branch: \(branch)") }
    }

    @Test func inferRepositoryReferenceWhenOriginIsGitHub() async throws {
        let client = ProcessGitClient()
        guard let url = try await client.remoteURL(named: "origin"),
              let host = url.host ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
                ?? scpHost(of: url),
              host == "github.com" else {
            print("[live] origin is not on github.com — skipping ref inference")
            return
        }
        let ref = try await client.currentRepository()
        #expect(ref != nil)
        if let ref { print("[live] inferred ref: \(ref.slug)") }
    }

    private func scpHost(of url: URL) -> String? {
        let absolute = url.absoluteString
        guard absolute.contains("@"), absolute.contains(":"), !absolute.contains("://") else { return nil }
        let after = absolute.split(separator: "@").last.map(String.init) ?? ""
        return after.split(separator: ":").first.map(String.init)
    }
}
#endif
