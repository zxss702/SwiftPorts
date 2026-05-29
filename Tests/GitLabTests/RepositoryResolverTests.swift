#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import Testing
@testable import GitLab
@testable import GlabCommand
import ForgeKit

/// Stub `GitClient` whose `remoteURL` returns whatever URL the test
/// hands it. Other methods are unused here and trap-on-call.
private struct StubGitClient: GitClient {
    let url: URL?

    func remoteURL(named: String) async throws -> URL? { url }
    func currentBranch() async throws -> String? { nil }
    func upstreamBranch(of localBranch: String) async throws -> String? { nil }

    func clone(url: URL, directory: URL?) async throws {
        fatalError("not used in tests")
    }
    func fetch(remote: String, refspec: String) async throws {
        fatalError("not used in tests")
    }
    func checkout(ref: String) async throws { fatalError("not used in tests") }
    func push(remote: String, refspec: String, setUpstream: Bool) async throws {
        fatalError("not used in tests")
    }
    func addRemote(name: String, url: URL) async throws {
        fatalError("not used in tests")
    }
    func add(paths: [String]) async throws { fatalError("not used in tests") }
    func commit(message: String, author: GitSignature?, allowEmpty: Bool) async throws -> String {
        fatalError("not used in tests")
    }
}

@Suite struct RepositoryResolverTests {
    @Test func graftsCwdHostOntoFlagWithoutHost() async throws {
        let cwdRemote = URL(string: "git@git.cocoanetics.com:labs/AgentCorp.git")!
        let stub = StubGitClient(url: cwdRemote)
        let flag = try RepositoryReference(parsing: "labs/AgentCorp")
        #expect(flag.host == nil)

        let resolved = try await RepositoryResolver.resolve(
            flag: flag, gitClient: stub)
        #expect(resolved.host == "git.cocoanetics.com")
        #expect(resolved.pathSegments == ["labs", "AgentCorp"])
    }

    @Test func leavesExplicitHostAlone() async throws {
        let stub = StubGitClient(url: URL(string: "https://gitlab.com/foo/bar.git"))
        let flag = try RepositoryReference(parsing: "git.cocoanetics.com/labs/AgentCorp")
        let resolved = try await RepositoryResolver.resolve(
            flag: flag, gitClient: stub)
        #expect(resolved.host == "git.cocoanetics.com")
        #expect(resolved.pathSegments == ["labs", "AgentCorp"])
    }

    @Test func flagWithoutCwdRemoteFallsThroughUnchanged() async throws {
        let stub = StubGitClient(url: nil)
        let flag = try RepositoryReference(parsing: "labs/AgentCorp")
        let resolved = try await RepositoryResolver.resolve(
            flag: flag, gitClient: stub)
        #expect(resolved.host == nil)
        #expect(resolved.pathSegments == ["labs", "AgentCorp"])
    }

    @Test func noFlagInfersFromCwdEntirely() async throws {
        let cwdRemote = URL(string: "https://git.cocoanetics.com/labs/AgentCorp.git")!
        let stub = StubGitClient(url: cwdRemote)
        let resolved = try await RepositoryResolver.resolve(gitClient: stub)
        #expect(resolved.host == "git.cocoanetics.com")
        #expect(resolved.pathSegments == ["labs", "AgentCorp"])
    }

    @Test func noFlagInfersFromSCPStyleSSHRemote() async throws {
        let cwdRemote = URL(string: "git@git.cocoanetics.com:labs/AgentCorp.git")!
        let stub = StubGitClient(url: cwdRemote)
        let resolved = try await RepositoryResolver.resolve(gitClient: stub)
        #expect(resolved.host == "git.cocoanetics.com")
        #expect(resolved.pathSegments == ["labs", "AgentCorp"])
    }

    @Test func noFlagInfersDeepSubgroupsFromCwd() async throws {
        let cwdRemote = URL(string: "https://gitlab.com/group/sub/sub-sub/repo.git")!
        let stub = StubGitClient(url: cwdRemote)
        let resolved = try await RepositoryResolver.resolve(gitClient: stub)
        #expect(resolved.host == "gitlab.com")
        #expect(resolved.pathSegments == ["group", "sub", "sub-sub", "repo"])
        #expect(resolved.encodedPath == "group%2Fsub%2Fsub-sub%2Frepo")
    }

    @Test func noFlagAndNoRemoteThrows() async {
        let stub = StubGitClient(url: nil)
        await #expect(throws: RepositoryResolverError.self) {
            _ = try await RepositoryResolver.resolve(gitClient: stub)
        }
    }
}

#endif  // !os(Android)
