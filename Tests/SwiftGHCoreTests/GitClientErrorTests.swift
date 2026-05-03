import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct GitClientErrorTests {
    @Test func noGitClientThrowsForWrites() async throws {
        let git = NoGitClient()
        await #expect(throws: GitClientError.self) {
            try await git.clone(url: URL(string: "https://example.com/x.git")!, directory: nil)
        }
        await #expect(throws: GitClientError.self) {
            try await git.fetch(remote: "origin", refspec: "main")
        }
        await #expect(throws: GitClientError.self) {
            try await git.checkout(ref: "main")
        }
        await #expect(throws: GitClientError.self) {
            try await git.push(remote: "origin", refspec: "main", setUpstream: false)
        }
        await #expect(throws: GitClientError.self) {
            try await git.addRemote(name: "origin",
                                    url: URL(string: "https://example.com/x.git")!)
        }
    }

    @Test func noGitClientReadsReturnNil() async throws {
        let git = NoGitClient()
        #expect(try await git.remoteURL(named: "origin") == nil)
        #expect(try await git.currentBranch() == nil)
        #expect(try await git.upstreamBranch(of: "main") == nil)
        #expect(try await git.currentRepository() == nil)
    }

    @Test func gitFailedErrorMessageIncludesArgsAndStderr() {
        let error = GitClientError.gitFailed(
            args: ["fetch", "origin", "main"],
            exitCode: 128,
            stderr: "fatal: 'origin' does not appear to be a git repository\n")
        let description = error.errorDescription ?? ""
        #expect(description.contains("fetch origin main"))
        #expect(description.contains("128"))
        #expect(description.contains("does not appear to be a git repository"))
    }

    @Test func gitUnavailableHasFriendlyMessage() {
        let error = GitClientError.gitUnavailable
        #expect(error.errorDescription?.contains("git binary") == true)
    }
}
