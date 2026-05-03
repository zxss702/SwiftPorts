import Foundation

/// Used by embedders without a usable `git` binary (sandboxed iOS,
/// Playgrounds, server contexts). Reads return `nil`, writes throw
/// `GitClientError.gitUnavailable` so the caller can surface a clear
/// "this command needs git" message.
public struct NoGitClient: GitClient {
    public init() {}

    // MARK: Read — return nil

    public func remoteURL(named: String) async throws -> URL? { nil }
    public func currentBranch() async throws -> String? { nil }
    public func upstreamBranch(of localBranch: String) async throws -> String? { nil }

    // MARK: Write — fail fast

    public func clone(url: URL, directory: URL?) async throws {
        throw GitClientError.gitUnavailable
    }
    public func fetch(remote: String, refspec: String) async throws {
        throw GitClientError.gitUnavailable
    }
    public func checkout(ref: String) async throws {
        throw GitClientError.gitUnavailable
    }
    public func push(remote: String, refspec: String, setUpstream: Bool) async throws {
        throw GitClientError.gitUnavailable
    }
    public func addRemote(name: String, url: URL) async throws {
        throw GitClientError.gitUnavailable
    }
}
